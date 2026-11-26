#!/usr/bin/env python3
"""
ai-devcontainer: give a project a sandboxed VS Code dev container for Claude Code.

It looks at a project (DDEV config, composer.json, package.json, .mcp.json, the
.claude guardrails) and writes a .devcontainer/ folder:

  * Claude runs in a container; DDEV keeps running on the Mac. A DDEV project's
    container joins DDEV's network and reaches its database as host `db`.
  * Default-deny egress firewall and an egress proxy with a per-project allowlist.
    `sandbox-domains allow` inside asks on the Mac; `block` applies at once.
  * No ~/.ssh, ~/.aws, ~/.gitconfig, ssh-agent or Docker socket inside. Tokens stay in the
    Mac's Keychain; the egress proxy adds them to requests on the way out.
  * The project's guardrails (.claude/hooks, settings, ai-config.conf, .mcp.json)
    and .devcontainer/ itself are mounted read-only, and a root-owned managed
    settings file re-registers the safety hook and turns off claude.ai connectors.

What the container may reach and sign in to comes from sandbox_policy.py: the active
ai-config profile, the project's [sandbox] section in ai-config.conf, and the integrations
they switch on (devcontainer-kit/integrations/, or private ones in
~/.config/ai-config/devcontainer/integrations/). Nothing here names an organization.

Everything it can't decide on its own is listed under "Manual follow-ups".

Usage:
  ai-devcontainer.py --root DIR            survey every project under DIR (dry run)
  ai-devcontainer.py --project DIR         one project (dry run)
  ai-devcontainer.py ... --list            one line per project
  ai-devcontainer.py ... --out DIR         write previews to DIR/<project>/.devcontainer
  ai-devcontainer.py ... --write [--force] write .devcontainer/ into the project(s)
  ai-devcontainer.py ... --update          regenerate files you haven't edited; stage the rest
                                           in .claude/ai-config/pending/.devcontainer/
  ai-devcontainer.py ... --profile NAME    use this ai-config profile instead of the active one
  ai-devcontainer.py ... --only a,b        limit --root to these folder names
  ai-devcontainer.py --project DIR --vscode-overrides
                                           settings .vscode/settings.json changes from the kit's
                                           or the user's (tab-separated; ai-config --doctor)

Standard library only. Run it on the Mac, outside any container.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sandbox_policy  # noqa: E402
import vscode_policy  # noqa: E402

VERSION = "2.1.0"
TOOL = "ai-devcontainer"
# Mac-side state shared by every container on this Mac: the DDEV relay, the egress CA, each
# project's token file. Kit 1.x used ~/.cache/cps-devcontainer; ensure-relay.sh links one to
# the other so containers built with either keep working.
STATE = "${HOME}/.cache/ai-devcontainer"
EE_MIGRATE_RELAY_NOTE = (
    "`.admin-scripts/ee-migrate.sh <staging|prod> status|rehearse|apply --expect=…` hands itself to the relay "
    "(as `ddev ee-migrate …`), which runs it on the Mac with your SSH, so no server credential is in here. "
    "`rehearse` and `apply` open the Allow/Deny dialog; `status` doesn't. The relay runs only the copy you "
    "approved: after a change to the script, approve it in a Mac terminal with "
    "`perl ~/.cache/ai-devcontainer/relay/ddev-relay.pl --approve-ee-migrate` (shows the diff). Those runs keep "
    "their stamps in the relay's state folder, so a rehearsal done here and one done in a Mac terminal don't "
    "count for each other. `local test` runs here directly.")
KIT = Path(__file__).resolve().parent
KIT_SCRIPTS = ("ddev-shim.sh", "ensure-ddev.sh", "ensure-relay.sh", "init-firewall.sh", "ddev-relay.pl",
               "ddev-relay-client.sh", "sandbox-domains.sh", "egress-proxy.sh", "egress-credentials.sh",
               "philter-setup.sh")
# Written once and never regenerated: domains approved or blocked from inside, or by you.
KEEP_FILES = ("domains.conf",)
MANIFEST = ".ai-devcontainer.manifest"
FILES = KIT / "files"

CLAUDE_HOSTS = ["api.anthropic.com", "claude.ai", "claude.com", "platform.claude.com", "downloads.claude.ai"]
VSCODE_HOSTS = ["marketplace.visualstudio.com", "vscode.blob.core.windows.net", "update.code.visualstudio.com",
                "main.vscode-cdn.net"]
NPM_HOSTS = ["registry.npmjs.org"]
COMPOSER_HOSTS = ["packagist.org", "repo.packagist.org", "getcomposer.org",
                  "objects.githubusercontent.com", "raw.githubusercontent.com", "codeload.github.com"]
PYTHON_HOSTS = ["pypi.org", "files.pythonhosted.org"]
CRAFT_HOSTS = ["composer.craftcms.com", "api.craftcms.com"]
CONTEXT7_HOSTS = ["context7.com", "mcp.context7.com"]
# DDEV config keys whose list items are extra host names for the same site (usually French).
HOSTNAME_KEYS = ("additional_hostnames", "additional_fqdns")
GITHUB_HOSTS = {"github.com", "api.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com"}
# Core and every wpackagist plugin/theme zip download from downloads.; checksums and version checks from api.
WORDPRESS_HOSTS = ["downloads.wordpress.org", "api.wordpress.org"]
# The egress proxy (a compose service): lets through only the allowlist's host names, so CDN
# address changes don't matter to anything that honours HTTP(S)_PROXY.
PROXY_HOST = "egress-proxy"
PROXY_PORT = 3128

PHP_EXTS = "pdo_mysql mysqli intl zip gd bcmath exif"
NODE_FRAMEWORK_PORTS = {"next": 3000, "@docusaurus/core": 3000, "astro": 4321, "@sveltejs/kit": 5173, "nuxt": 3000,
                        "vite": 5173, "browser-sync": 3000}
PORT_LABELS = {3000: "BrowserSync / dev server", 3001: "BrowserSync UI", 4321: "Astro", 5173: "Vite"}
# BrowserSync's control UI sits next to its proxy port.
EXTRA_PORTS = {"browser-sync": [3001]}
# Tokens: each integration with a [credential] names a Keychain item on the Mac.
# egress-credentials.sh (initializeCommand) reads .devcontainer/token-hosts.conf, copies those
# tokens into EGRESS_DIR/projects/<key>/credentials.env, and mounts it into the egress proxy
# only; the proxy intercepts TLS for those hosts with this Mac's CA and sets Authorization
# itself. The container sees EGRESS_PLACEHOLDER and the CA's certificate.
EGRESS_DIR = f"{STATE}/egress"
EGRESS_PLACEHOLDER = "ai-egress-placeholder"
EGRESS_CA_IN_CONTAINER = "/run/ai-egress/ca.crt"
# Playwright for checking pages in a real browser (the webapp-testing skill writes Python
# scripts). Python package and Chromium are baked into the image at build time, which runs on
# the Mac outside the firewall. The npm package of the same version uses the same browser build.
PLAYWRIGHT_VERSION = "1.64.1"
# gitleaks release baked into the image for the safety guard's commit scan.
GITLEAKS_VERSION = "8.30.1"
# .ddev subfolders mounted writable inside the read-only .ddev mount. Only DDEV's own containers
# read them; no exec-host hook or host command lives there. php/, mysql/ and apache/ are equally
# container-only if a project ever needs them. Never config*.yaml, commands/, providers/,
# web-build/, db-build/, web-entrypoint.d/ or homeadditions/.
WRITABLE_DDEV_DIRS = ("nginx_full",)
PLAYWRIGHT_BROWSERS = "/opt/ms-playwright"
# wrangler needs Node 22, which projects on 18 or 20 don't have, so it gets its own runtime.
WRANGLER_NODE = "22"

# DDEV's own commands; everything else under .ddev/commands/web is the project's.
# --profile on the command line (None: the active profile, as profile.sh resolves it).
PROFILE_OVERRIDE: str | None = None

DDEV_DEFAULT_WEB_CMDS = {"README.txt", "blackfire", "drush", "magento", "typo3", "xhprof", "artisan", "craft"}


@dataclass
class Project:
    path: Path
    folder: str
    ddev: dict = field(default_factory=dict)
    web_env_names: list = field(default_factory=list)
    ddev_links: list = field(default_factory=list)       # external_links from .ddev overrides
    ddev_foreign_mounts: list = field(default_factory=list)
    ddev_addons: list = field(default_factory=list)
    custom_web_cmds: list = field(default_factory=list)
    custom_host_cmds: list = field(default_factory=list)
    composer: dict = field(default_factory=dict)
    package: dict = field(default_factory=dict)
    package_dir: str = ""                                # where package.json was found ("" = root)
    mcp: dict = field(default_factory=dict)
    stack: list = field(default_factory=list)
    php: str | None = None
    node: str | None = None
    python: bool = False
    git_name: str = ""
    db_name: str = "db"                                  # the DDEV database the site uses (`ddev mysql`)
    git_email: str = ""
    notes: list = field(default_factory=list)            # manual follow-ups
    info: list = field(default_factory=list)             # things handled automatically
    policy: sandbox_policy.Policy | None = None          # what the sandbox may reach (sandbox_policy.py)
    refused: set = field(default_factory=set)            # new hosts not confirmed this run (left out)
    vscode: vscode_policy.VSCodeConfig = field(default_factory=vscode_policy.VSCodeConfig)  # [vscode]

    @property
    def key(self) -> str:
        """This project's name for Mac-side state: its relay token and its egress folder. The
        DDEV project name (what kit 1.x used), else the folder name."""
        name = self.ddev_name if self.uses_ddev and self.ddev_name else self.folder
        name = re.sub(r"[^A-Za-z0-9_.-]", "-", name)[:48] or "project"
        # Plus a hash of the folder's path: two projects with the same name (a client's "site"
        # and another's) must never share a relay token or a token folder.
        return f"{name}-{hashlib.sha256(str(self.path.resolve()).encode()).hexdigest()[:8]}"

    @property
    def ddev_name(self) -> str | None:
        return self.ddev.get("name")

    @property
    def uses_ddev(self) -> bool:
        """Join DDEV's network only when the container needs something there: a PHP app's
        database, an add-on, or a host another override links to. A Node-only project
        that merely has a .ddev folder (e.g. Docusaurus) runs standalone."""
        return bool(self.ddev) and bool(self.php or self.ddev_links or self.ddev_addons)

    @property
    def site_host(self) -> str | None:
        """The DDEV site's primary host name (mysite.test), served by ddev-router."""
        if not (self.uses_ddev and self.php and self.ddev_name):
            return None
        return f"{self.ddev_name}.{self.ddev.get('project_tld') or 'ddev.site'}"

    @property
    def site_hosts(self) -> list[str]:
        """Every name DDEV serves the site on: the primary host, additional_hostnames under the
        project TLD and additional_fqdns as written. A bilingual site's second-language name
        (fr-name.mysite.test) must resolve and bypass the proxy like the primary one.
        Wildcards can't be a link alias, so they're left out."""
        if not self.site_host:
            return []
        tld = self.ddev.get("project_tld") or "ddev.site"
        hosts = [self.site_host]
        hosts += [f"{h}.{tld}" for h in self.ddev.get("additional_hostnames_list", [])]
        hosts += self.ddev.get("additional_fqdns_list", [])
        return [h for h in dict.fromkeys(hosts) if "*" not in h]

    @property
    def node_modules(self) -> str | None:
        """/workspace path of the project's node_modules, when it has a package.json."""
        if not self.package:
            return None
        return "/workspace/" + (f"{self.package_dir}/" if self.package_dir else "") + "node_modules"

    @property
    def deps(self) -> dict:
        p = self.package
        return {**p.get("dependencies", {}), **p.get("devDependencies", {})}


# ---------------------------------------------------------------- detection

def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def unquote(s: str) -> str:
    return s.strip().strip("'\"")


def parse_ddev_config(path: Path) -> tuple[dict, list]:
    """Top-level scalars, database.type/version, additional_hostnames/fqdns (as lists under
    '<key>_list'), and web_environment variable NAMES only."""
    cfg, env_names, block = {}, [], None
    for raw in path.read_text().splitlines():
        line = raw.split(" #")[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not line.strip():
            continue
        if not raw.startswith((" ", "\t", "-")):
            block = None
            m = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
            if m:
                key, val = m.group(1), unquote(m.group(2))
                if val in ("", "[]"):
                    block = key
                elif key in HOSTNAME_KEYS and val.startswith("["):
                    # Flow style: additional_hostnames: [soinsdenosenfants, www]
                    cfg[f"{key}_list"] = [unquote(h.strip()) for h in val.strip("[]").split(",") if h.strip()]
                cfg[key] = val
            continue
        if block in HOSTNAME_KEYS:
            m = re.match(r"^\s*-\s*(\S+)\s*$", line)
            if m:
                cfg.setdefault(f"{block}_list", []).append(unquote(m.group(1)))
        elif block == "database":
            m = re.match(r"^\s+(type|version):\s*(.*)$", line)
            if m:
                cfg[f"database_{m.group(1)}"] = unquote(m.group(2))
        elif block == "web_environment":
            m = re.match(r"^\s*-\s*([A-Za-z_][A-Za-z0-9_]*)=", line)
            if m:
                env_names.append(m.group(1))
    return cfg, env_names


def parse_ddev_overrides(p: Project) -> None:
    """external_links (kept) and volumes that point outside the project (flagged)."""
    for f in sorted((p.path / ".ddev").glob("docker-compose.*.yaml")):
        text = f.read_text()
        if "#ddev-generated" in text:
            continue
        section = None
        for raw in text.splitlines():
            if raw.lstrip().startswith("#") or not raw.strip():
                continue
            m = re.match(r"^\s+([a-z_]+):\s*$", raw)
            if m:
                section = m.group(1)
                continue
            m = re.match(r"^\s+-\s*(.+)$", raw)
            if not m:
                continue
            item = unquote(m.group(1))
            if section == "external_links":
                p.ddev_links.append(item)
            elif section == "volumes":
                host = item.split(":")[0]
                target = item.split(":")[1] if ":" in item else ""
                own = host.rstrip("/").endswith("/" + p.folder) or host in (".", "..")
                if own and target.startswith("/var/www/html"):
                    continue            # DDEV re-mounting the project itself
                p.ddev_foreign_mounts.append(f"{item}  ({f.name})")


def detect(path: Path) -> Project:
    p = Project(path=path, folder=path.name)
    ddev_cfg = path / ".ddev" / "config.yaml"
    if ddev_cfg.exists():
        p.ddev, p.web_env_names = parse_ddev_config(ddev_cfg)
        parse_ddev_overrides(p)
        meta = path / ".ddev" / "addon-metadata"
        if meta.is_dir():
            p.ddev_addons = sorted(d.name for d in meta.iterdir() if d.is_dir())
        for kind, bucket in (("web", p.custom_web_cmds), ("host", p.custom_host_cmds)):
            d = path / ".ddev" / "commands" / kind
            if d.is_dir():
                for f in sorted(d.iterdir()):
                    if f.is_file() and f.name not in DDEV_DEFAULT_WEB_CMDS and not f.name.startswith("."):
                        try:
                            if "#ddev-generated" in f.read_text(errors="ignore"):
                                continue
                        except Exception:
                            pass
                        bucket.append(f.name)

    p.composer = read_json(path / "composer.json")
    # CMS sites often keep the front-end build in the docroot (public/package.json), and
    # WordPress sites in the theme (web/app/themes/<theme>).
    docroot = p.ddev.get("docroot", "")
    themes = sorted(str(d.relative_to(path)) for pattern in ("web/app/themes/*", "wp-content/themes/*",
                                                             f"{docroot}/wp-content/themes/*" if docroot else "")
                    if pattern for d in path.glob(pattern) if (d / "package.json").is_file())
    for folder in dict.fromkeys(["", docroot, "public", *themes]):
        p.package = read_json(path / folder / "package.json")
        if p.package:
            p.package_dir = folder
            break
    p.mcp = read_json(path / ".mcp.json").get("mcpServers", {})
    req = p.composer.get("require", {})

    # Stack
    if (path / "system" / "ee").is_dir():
        p.stack.append("expressionengine")
    if "expressionengine/coilpack" in req:
        p.stack.append("coilpack")
    if (path / "craft").exists() or "craftcms/cms" in req:
        p.stack.append("craftcms")
    if (path / "artisan").exists():
        p.stack.append("laravel")
    if "roots/wordpress" in req or (path / "wp-config.php").exists() or p.ddev.get("type") == "wordpress":
        p.stack.append("wordpress")
    for dep, name in (("next", "nextjs"), ("@docusaurus/core", "docusaurus"), ("astro", "astro"),
                      ("sanity", "sanity"), ("tailwindcss", "tailwind"), ("vite", "vite")):
        if dep in p.deps:
            p.stack.append(name)
    p.python = (path / "requirements.txt").exists() or (path / "pyproject.toml").exists()
    if p.python:
        p.stack.append("python")

    # PHP
    has_php_files = any(path.glob("*.php"))
    if p.composer or has_php_files or {"expressionengine", "craftcms", "laravel", "wordpress"} & set(p.stack):
        ver = p.ddev.get("php_version")
        if not ver:
            m = re.search(r"(\d+\.\d+)", req.get("php", ""))
            ver = m.group(1) if m else "8.3"
        p.php = ver

    # Node
    if p.package:
        ver = p.ddev.get("nodejs_version", "")
        # The .nvmrc next to package.json. A root one doesn't speak for a theme's build
        # (a root .nvmrc saying 16 next to a Vite theme that needs 18+).
        nvmrc = path / p.package_dir / ".nvmrc"
        if not ver and nvmrc.exists():
            ver = nvmrc.read_text().strip().lstrip("v")
        if not ver:
            # "^20" or "20.x" pins a major; ">=18" is only a floor, so LTS.
            engines = p.package.get("engines", {}).get("node", "")
            m = re.search(r"(\d+)", engines)
            ver = m.group(1) if m and ">" not in engines else "lts"
        p.node = ver.split(".")[0] if ver != "lts" else "lts"

    # Git identity (what the Mac uses for this repo)
    for key, attr in (("user.name", "git_name"), ("user.email", "git_email")):
        try:
            val = subprocess.run(["git", "-C", str(path), "config", "--get", key],
                                 capture_output=True, text=True, timeout=5).stdout.strip()
        except Exception:
            val = ""
        setattr(p, attr, val)

    p.policy = sandbox_policy.resolve(path, PROFILE_OVERRIDE, extra=["context7"] if "context7" in p.mcp else [])
    p.vscode = vscode_policy.read_vscode(path)
    assess(p)
    return p


SYSTEM_DATABASES = {"mysql", "performance_schema", "sys", "test", "information_schema"}


def detect_db_name(p: Project) -> None:
    """Find the database the site really uses. Many sites import production into a
    database named after it (admin_site), leaving DDEV's own `db` empty, so `ddev mysql`
    must not assume `db`. Each database is a folder in the project's DDEV volume: take the
    populated one written most recently (an abandoned import can sit beside the live one)."""
    kind = p.ddev.get("database_type") or "mariadb"
    if kind not in ("mariadb", "mysql") or not shutil.which("docker"):
        return
    volume = f"{p.ddev_name}-{kind}"
    script = ('cd /v || exit 1; for d in */; do d=${d%/}; '
              't=$(find "$d" -maxdepth 1 \\( -name "*.ibd" -o -name "*.frm" \\) -exec stat -c %Y {} + 2>/dev/null '
              '| sort -n | tail -1); if [ -n "$t" ]; then echo "$t $d"; fi; done')
    try:
        out = subprocess.run(["docker", "run", "--rm", "--network", "none", "-v", f"{volume}:/v:ro",
                              "alpine:3.20", "sh", "-c", script],
                             capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        out = None
    found = []
    for line in (out.stdout.splitlines() if out and out.returncode == 0 else []):
        stamp, _, name = line.partition(" ")
        if name and name not in SYSTEM_DATABASES and stamp.isdigit():
            found.append((int(stamp), name))
    if not found:
        p.notes.append(f"Couldn't read DDEV volume {volume} to find the site's database; `ddev mysql` "
                       "uses `db`. Pass --db-name if the site imports into another database.")
        return
    found.sort(reverse=True)
    p.db_name = found[0][1]
    others = ", ".join(n for _, n in found[1:])
    p.info.append(f"Database: `{p.db_name}` (most recently written in {volume}"
                  + (f"; also there: {others}" if others else "") + "). `ddev mysql` opens it; "
                  "override with --db-name.")


def assess(p: Project) -> None:
    """Work out what is automatic and what needs a person."""
    if p.policy:
        p.info += p.policy.info
        p.notes += p.policy.notes
        if p.policy.integrations:
            p.info.append("Integrations: " + ", ".join(i.name for i in p.policy.integrations))
    p.notes += p.vscode.problems
    if p.vscode:
        parts = [f"+{e}" for e in p.vscode.add] + [f"-{e}" for e in p.vscode.remove]
        parts += [f"{len(p.vscode.settings)} setting(s)"] if p.vscode.settings else []
        p.info.append("VS Code from ai-config.conf [vscode]: " + ", ".join(parts))
    if p.ddev and not p.uses_ddev:
        p.info.append(f"Has a DDEV config ('{p.ddev_name}') but nothing in the container needs it: standalone.")
    elif p.ddev and p.php and any(l.split(":")[-1] == "db" for l in p.ddev_links):
        p.info.append(f"DDEV project '{p.ddev_name}': joins ddev_default; `db` follows the .ddev override "
                      f"(not ddev-{p.ddev_name}-db), exactly as in DDEV's web container.")
    elif p.ddev and p.php:
        p.info.append(f"DDEV project '{p.ddev_name}': joins ddev_default, database ddev-{p.ddev_name}-db as host `db`.")
    elif p.ddev:
        p.info.append(f"DDEV project '{p.ddev_name}': joins ddev_default for the hosts its overrides link to.")
    if p.ddev:
        if p.ddev_addons:
            p.info.append("DDEV add-ons reachable by name: " + ", ".join(p.ddev_addons))
        for addon in p.ddev_addons:
            # The metadata is often committed while .ddev/docker-compose.*.yaml is gitignored, so a
            # checkout can record an add-on DDEV no longer starts. Linking to it would stop the
            # container from starting.
            manifest = p.path / ".ddev" / "addon-metadata" / addon / "manifest.yaml"
            text = manifest.read_text() if manifest.exists() else ""
            repo = re.search(r"^repository:\s*(\S+)", text, re.M)
            missing = [f for f in re.findall(r"^\s*-\s*(docker-compose\.[\w.-]+\.ya?ml)\s*$", text, re.M)
                       if not (p.path / ".ddev" / f).exists()]
            if missing:
                p.notes.append(f"DDEV add-on '{addon}' is recorded in .ddev/addon-metadata, but "
                               f"{', '.join(missing)} is missing, so DDEV doesn't run it and the container "
                               f"won't start. On the Mac: `ddev add-on get {repo.group(1) if repo else addon}` "
                               "and `ddev restart`, or remove the link from docker-compose.yml.")
        if p.ddev_links:
            p.info.append("Carried over from .ddev overrides: external_links " + ", ".join(p.ddev_links))
    if not p.ddev:
        p.info.append("No DDEV: standalone container, no database.")

    for m in p.ddev_foreign_mounts:
        if re.search(r"\.(aws|ssh|gnupg|docker|kube|config/gh)\b", m):
            p.info.append(f"Not carried over (credentials stay on the Mac): {m}")
            continue
        p.notes.append(f"DDEV mounts something outside the project: {m}. Mount it in docker-compose.yml "
                       "read-only, with writable overlays only where needed (e.g. site:ro + "
                       "site/public/uploads:rw). Never mount ~/.aws or ~/.ssh.")
    if p.web_env_names:
        p.notes.append("DDEV sets these in the web container: " + ", ".join(p.web_env_names) +
                       ". If the app reads them from the environment (not .env), add them to the "
                       "`environment:` block. Values aren't copied here because some may be secrets.")
    if p.custom_web_cmds:
        p.info.append("Custom DDEV web commands run through the shim: " +
                      ", ".join(f"ddev {c}" for c in p.custom_web_cmds))
    if [c for c in p.custom_host_cmds if c != "README.txt"]:
        p.notes.append("Host-side DDEV commands (run on the Mac only): " + ", ".join(p.custom_host_cmds))

    for name, srv in p.mcp.items():
        cmd = srv.get("command", "")
        args = srv.get("args", [])
        if cmd == "ddev":
            sub = args[0] if args else ""
            if sub in p.custom_web_cmds:
                p.info.append(f"MCP server '{name}' (ddev {sub}) runs through the shim.")
            else:
                p.notes.append(f"MCP server '{name}' runs `ddev {' '.join(args)}`, which the shim can't map; "
                               "it will fail to connect in the container.")
        elif srv.get("type") in ("http", "sse") or srv.get("url"):
            host = re.sub(r"^https?://([^/:]+).*$", r"\1", srv.get("url", ""))
            p.notes.append(f"MCP server '{name}' is remote ({host}); add {host} to allowed-domains.txt "
                           "only if Claude should reach it from the sandbox.")

    repos = [r.get("url", "") for r in p.composer.get("repositories", []) if isinstance(r, dict)]
    private = [u for u in repos if u and not any(h in u for h in ("packagist.org", "wpackagist.org",
                                                                  "composer.craftcms.com"))]
    github_private = [u for u in private if "github.com" in u]
    other_private = [u for u in private if u not in github_private]
    if other_private and (p.path / "auth.json").exists():
        # Composer reads auth.json next to composer.json before the global one, and the project
        # mount brings it in. Claude can't read it (managed deny + safety guard); Composer can.
        p.info.append("Composer logins come from the project's own auth.json (gitignored, inside the project "
                      "mount) for: " + ", ".join(other_private))
    elif other_private:
        p.notes.append("Private Composer repositories need logins in an auth.json next to composer.json "
                       "(gitignored); until then run `composer install/update` on the Mac via DDEV. Repos: "
                       + ", ".join(other_private))
    if github_private:
        p.info.append("Private GitHub repos for Composer (" + ", ".join(github_private) + ") clone with the gh "
                      "login when there's no github-oauth entry in auth.json; that login's token must "
                      "be able to read them.")
    if "wordpress" in p.stack:
        p.info.append("WP-CLI installed in the image; `ddev wp` maps to it if the project defines that command.")
    if p.php and p.php < "8.2":
        p.notes.append(f"PHP {p.php}: check that mcr.microsoft.com/devcontainers/php:{p.php} still pulls.")
    if p.node and p.node.isdigit() and int(p.node) < 18:
        p.notes.append(f"Node {p.node} is end-of-life; the devcontainers node feature may not install it. "
                       "If the build fails, raise the version in devcontainer.json.")
    if not (p.path / ".claude" / "hooks" / "safety-guard.sh").exists():
        p.notes.append("No .claude/hooks/safety-guard.sh: the container still has the managed deny/ask rules, "
                       "but consider running ai-config on this project first.")
    if not p.git_email:
        p.notes.append("No git user.email for this repo: set GIT_* in docker-compose.yml.")


# ---------------------------------------------------------------- generation

def base_image(p: Project) -> tuple[str, str]:
    """(image, remote user)."""
    if p.php:
        return f"mcr.microsoft.com/devcontainers/php:{p.php}", "vscode"
    if p.node:
        tag = p.node if p.node != "lts" else "22"
        return f"mcr.microsoft.com/devcontainers/javascript-node:{tag}", "node"
    if p.python:
        return "mcr.microsoft.com/devcontainers/python:3.12", "vscode"
    return "mcr.microsoft.com/devcontainers/base:ubuntu", "vscode"


def guardrail_mounts(p: Project) -> list[str]:
    out = []
    for rel in (".claude/hooks", ".claude/settings.json", ".claude/settings.local.json", "ai-config.conf", ".mcp.json"):
        # ai-config.conf always: it sets what the sandbox reaches, so the container must not be
        # able to create one either (--write creates an empty one first).
        if (p.path / rel).exists() or rel == "ai-config.conf":
            out.append(f"      - ../{rel}:/workspace/{rel}:ro")
    out.append("      - ../.devcontainer:/workspace/.devcontainer:ro")
    if (p.path / ".git").is_dir():
        # Git on the Mac runs hooks and the commands .git/config names (core.fsmonitor,
        # core.hooksPath, filter drivers, aliases); VS Code runs `git status` constantly. Writable,
        # either would let the sandbox run code outside itself. Commits still work inside; setting
        # an upstream (`push -u`, `branch -u`) fails there, so do that on the Mac. A Mac-side
        # `git config` replaces the file, so the container sees the old copy until it's recreated.
        out.append("      # Git hooks and config, read-only: git on the Mac runs what they name (hooks, core.fsmonitor, filters).")
        out.append("      - ../.git/hooks:/workspace/.git/hooks:ro")
        out.append("      - ../.git/config:/workspace/.git/config:ro")
    if (p.path / ".ddev").is_dir():
        # DDEV runs exec-host hooks on the Mac at the next `ddev start` (ensure-ddev.sh), so a
        # writable .ddev would let the sandbox schedule commands outside itself.
        out.append("      # DDEV config, read-only: its exec-host hooks run on the Mac at the next `ddev start`.")
        out.append("      - ../.ddev:/workspace/.ddev:ro")
        for sub in WRITABLE_DDEV_DIRS:
            if (p.path / ".ddev" / sub).is_dir():
                # Exception: only nginx inside the DDEV web container reads this; nothing in it runs
                # on the Mac. Mount the directory, not a file: editors save via temp file + rename,
                # which fails on a single-file bind mount.
                out += [f"      # Exception: {sub} is read only by nginx inside the DDEV web container and never",
                        "      # runs on the Mac, so it stays writable. Mount the directory, not the file: editors save",
                        "      # via temp file + rename, which fails on a single-file bind mount.",
                        f"      - ../.ddev/{sub}:/workspace/.ddev/{sub}"]
    return out


def gen_dockerfile(p: Project) -> str:
    image, user = base_image(p)
    apt = "iptables ipset iproute2 dnsutils aggregate jq curl python3 sudo"
    if any(p.path.glob("*.sh")):
        apt += " shellcheck perl rsync"       # shell-script repos (their test suites)
    if p.uses_ddev and p.php:
        apt += " mariadb-client"
    lines = [f"# Generated by {TOOL} {VERSION}. Edit freely: `ai-config --refresh` keeps an edited copy and stages",
             "# the new version in .claude/ai-config/pending/.devcontainer/.",
             f"FROM {image}", ""]
    if p.php:
        lines += [
            "# Firewall tools, DB client, jq/python3 for the safety-guard hook, PHP extensions.",
            "RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \\",
            f"    && apt-get install -y --no-install-recommends {apt} \\",
            "       libicu-dev libzip-dev libpng-dev libjpeg-dev libfreetype6-dev libwebp-dev \\",
            "    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \\",
            f"    && docker-php-ext-install -j\"$(nproc)\" {PHP_EXTS} \\",
            "    && apt-get clean && rm -rf /var/lib/apt/lists/*",
            "",
            "# Match DDEV: no PHP memory limit (the stock 128M is too small for test suites).",
            "RUN echo 'memory_limit = -1' > /usr/local/etc/php/conf.d/zz-memory.ini",
            "",
        ]
        if "wordpress" in p.stack:
            lines += ["# WP-CLI, at the path DDEV uses.",
                      "RUN curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \\",
                      "    && chmod 755 /usr/local/bin/wp", ""]
    else:
        lines += ["# Firewall tools and jq/python3 for the safety-guard hook.",
                  "RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \\",
                  f"    && apt-get install -y --no-install-recommends {apt} \\",
                  "    && apt-get clean && rm -rf /var/lib/apt/lists/*", ""]
    if p.uses_ddev and p.php:
        lines += ["# DDEV's MariaDB has no TLS; newer MariaDB clients require it by default.",
                  "RUN mkdir -p /etc/mysql/mariadb.conf.d \\",
                  "    && printf '[client]\\nskip-ssl\\n' > /etc/mysql/mariadb.conf.d/99-ddev-no-ssl.cnf", ""]
    images = {x for i in (p.policy.integrations if p.policy else []) for x in i.image}
    lines += node_and_claude_lines(p, image, user)
    lines += wrangler_lines() if "wrangler" in images else []
    lines += playwright_lines(user) if "playwright" in images else []
    lines += gitleaks_lines() + [
        "# Root-owned, baked into the image: nothing inside the container can edit these.",
        "# (A non-standard path: a dev container feature once replaced /usr/local/bin/init-firewall.sh.)",
        "# allowed-domains.txt isn't copied: the firewall reads it from the read-only .devcontainer",
        "# mount at every start, so an allowlist edit needs a reopen, not a rebuild.",
        "COPY init-firewall.sh /usr/local/sbin/sandbox-firewall.sh",
        "COPY ddev-shim.sh /usr/local/bin/ddev",
        "COPY managed-settings.json /etc/claude-code/managed-settings.json",
        "# sandbox-domains: ask the Mac for a domain, or block one. It runs the client from the",
        "# read-only .devcontainer mount, so it updates without a rebuild.",
        "RUN printf '%s\\n' '#!/bin/sh' 'exec bash /workspace/.devcontainer/sandbox-domains.sh \"$@\"' \\",
        "      > /usr/local/bin/sandbox-domains \\",
        "    && chmod 755 /usr/local/bin/sandbox-domains",
        "RUN chmod 755 /usr/local/sbin/sandbox-firewall.sh /usr/local/bin/ddev \\",
        "    && chmod 644 /etc/claude-code/managed-settings.json",
        "",
        "# New Docker volumes start out owned by root; this hands the fixed list below to the",
        "# container user. Root-owned, no arguments, so sudo can't be pointed at anything else.",
        "RUN printf '%s\\n' '#!/bin/sh' \\",
        *[f"    '{line}' \\" for line in own_volume_lines(p, user)],
        "    > /usr/local/sbin/sandbox-own-volumes.sh \\",
        "    && chmod 755 /usr/local/sbin/sandbox-own-volumes.sh",
        "",
        "# Trusts this Mac's egress-proxy CA (its certificate only; the key stays in the proxy), so the",
        "# proxy can add tokens to requests (token-hosts.conf lists which). Root-owned, no arguments.",
        "RUN printf '%s\\n' '#!/bin/sh' 'set -e' \\",
        f"    '[ -s {EGRESS_CA_IN_CONTAINER} ] || exit 0' \\",
        f"    'install -m 644 {EGRESS_CA_IN_CONTAINER} /usr/local/share/ca-certificates/ai-egress-ca.crt' \\",
        "    'update-ca-certificates >/dev/null' \\",
        "    > /usr/local/sbin/sandbox-trust-ca.sh \\",
        "    && chmod 755 /usr/local/sbin/sandbox-trust-ca.sh",
        "",
        f"# The base image gives \"{user}\" passwordless sudo for everything, which would let",
        "# anything inside run `sudo iptables -F`. Allow only the three root-owned scripts.",
        "RUN rm -f /etc/sudoers.d/* \\",
        f"    && echo \"{user} ALL=(root) NOPASSWD: /usr/local/sbin/sandbox-firewall.sh, "
        f"/usr/local/sbin/sandbox-own-volumes.sh, /usr/local/sbin/sandbox-trust-ca.sh\" > /etc/sudoers.d/{user}-firewall \\",
        f"    && chmod 0440 /etc/sudoers.d/{user}-firewall",
        "",
        f"RUN mkdir -p /home/{user}/.claude && chown -R {user}:{user} /home/{user}/.claude",
        "",
        "# The vscode-extensions volume starts as a copy of this folder, so it belongs to the user.",
        f"RUN mkdir -p /home/{user}/.vscode-server/extensions && chown -R {user}:{user} /home/{user}/.vscode-server",
        "",
    ] + history_lines(user) + github_lines(p, user)
    return "\n".join(lines)


def gitleaks_lines() -> list[str]:
    """gitleaks, the safety guard's optional second secret scan at commit time.

    A pinned release binary, checked against the release's checksum file. Downloaded at build
    time, which runs on the Mac outside the firewall, so github.com needs no allowlist entry.
    """
    v = GITLEAKS_VERSION
    base = f"https://github.com/gitleaks/gitleaks/releases/download/v{v}"
    return [f"# gitleaks {v}: the safety guard's second secret scan when Claude commits (its own pattern",
            "# check runs without it). Checksum-verified release binary; bump the version in the kit to update.",
            "RUN arch=\"$(dpkg --print-architecture)\" && case \"$arch\" in amd64) arch=x64 ;; esac \\",
            f"    && tarball=\"gitleaks_{v}_linux_${{arch}}.tar.gz\" && cd /tmp \\",
            f"    && curl -fsSLO \"{base}/${{tarball}}\" \\",
            f"    && curl -fsSL \"{base}/gitleaks_{v}_checksums.txt\" | grep \" ${{tarball}}$\" | sha256sum -c - \\",
            "    && tar -xzf \"$tarball\" -C /usr/local/bin gitleaks \\",
            "    && chmod 755 /usr/local/bin/gitleaks && rm -f \"$tarball\"",
            ""]


def wrangler_lines() -> list[str]:
    """wrangler (Cloudflare's CLI) for the noslop skill's web version, on its own Node runtime.

    Current wrangler needs Node 22; many projects run 18 or 20. Node and npm are copied from the
    official image into /opt/wrangler, and /usr/local/bin/wrangler runs wrangler with that Node,
    so the project's own Node is untouched.
    """
    tag = f"node:{WRANGLER_NODE}-bookworm-slim"
    return [f"# wrangler for the noslop skill's Cloudflare pages, on its own Node {WRANGLER_NODE} (the project's",
            "# Node may be older). Cached layer; Rebuild Without Cache to update it.",
            f"COPY --from={tag} /usr/local/bin/node /opt/wrangler/bin/node",
            f"COPY --from={tag} /usr/local/lib/node_modules/npm /opt/wrangler/npm",
            "RUN /opt/wrangler/bin/node /opt/wrangler/npm/bin/npm-cli.js install --global --prefix /opt/wrangler \\",
            "      --no-fund --no-audit --loglevel=error wrangler@4 \\",
            "    && printf '%s\\n' '#!/bin/sh' \\",
            "      'exec /opt/wrangler/bin/node /opt/wrangler/lib/node_modules/wrangler/bin/wrangler.js \"$@\"' \\",
            "      > /usr/local/bin/wrangler \\",
            "    && chmod 755 /usr/local/bin/wrangler",
            ""]


def playwright_lines(user: str) -> list[str]:
    """Python Playwright and headless Chromium with its system libraries, as a cached layer.

    Installing at runtime fails: `playwright install --with-deps` needs apt and root, and the
    browser CDN wasn't allowlisted. The browsers folder belongs to the user, so `npx playwright
    install chromium` for another version can add its build next to this one.
    """
    return [f"# Playwright {PLAYWRIGHT_VERSION} (Python) and headless Chromium with its system libraries, so Claude",
            "# can open pages and take screenshots. `python` is python3. Cached layer; bump the version",
            "# in the kit to update.",
            f"ENV PLAYWRIGHT_BROWSERS_PATH={PLAYWRIGHT_BROWSERS}",
            "RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \\",
            "    && apt-get install -y --no-install-recommends python3-pip python-is-python3 \\",
            "    && python3 -m pip install --no-cache-dir --break-system-packages --root-user-action=ignore \\",
            f"         playwright=={PLAYWRIGHT_VERSION} \\",
            "    && python3 -m playwright install --with-deps chromium \\",
            f"    && chown -R {user}:{user} {PLAYWRIGHT_BROWSERS} \\",
            "    && apt-get clean && rm -rf /var/lib/apt/lists/*",
            ""]


def node_major(p: Project) -> str:
    """The official node image tag for the project's Node version ("20.11" -> "20", unset -> "lts")."""
    ver = (p.node or "lts").lstrip("v")
    return ver.split(".")[0] if ver[:1].isdigit() else "lts"


def node_and_claude_lines(p: Project, image: str, user: str) -> list[str]:
    """Node (when the base image lacks it) and the Claude Code CLI, as ordinary image layers.

    Dev container features run after the whole Dockerfile and were never reused from the build
    cache, so every rebuild downloaded Node and Claude Code again (1.5-2 min on the PHP images).
    These layers sit above the COPY lines, so they're rebuilt only when this block changes.
    Global npm installs go to a user-owned prefix, as on the javascript-node images.
    """
    claude = ["# Claude Code CLI, native build: it carries its own runtime, so the project's Node version",
              "# (18 and 20 here; current npm releases need 22) can't hold it back. It updates itself in",
              "# ~/.local; Rebuild Without Cache to start from the latest.",
              f"USER {user}",
              "RUN curl -fsSL https://claude.ai/install.sh | bash",
              "USER root",
              f"ENV PATH=/home/{user}/.local/bin:$PATH",
              ""]
    if "javascript-node" in image:
        return claude
    tag = f"{node_major(p)}-bookworm-slim"
    return [f"# Node {node_major(p)}, copied from the official image (no nvm download on rebuilds).",
            f"COPY --from=node:{tag} /usr/local/bin/node /usr/local/bin/node",
            f"COPY --from=node:{tag} /usr/local/lib/node_modules /usr/local/lib/node_modules",
            "RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \\",
            "    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \\",
            "    && ln -sf ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack",
            "# Global npm installs go to a user-owned prefix, on PATH for every shell.",
            f"RUN mkdir -p /usr/local/share/npm-global /usr/local/etc \\",
            f"    && chown {user}:{user} /usr/local/share/npm-global \\",
            "    && echo 'prefix=/usr/local/share/npm-global' > /usr/local/etc/npmrc \\",
            "    && echo 'export PATH=/usr/local/share/npm-global/bin:$PATH' > /etc/profile.d/npm-global.sh",
            "ENV PATH=/usr/local/share/npm-global/bin:$PATH",
            ""] + claude


def history_lines(user: str) -> list[str]:
    """Dockerfile lines that keep bash/zsh history on the command-history volume."""
    return [
        "# Shell history survives rebuilds: it lives on the command-history volume, written after",
        "# every command. A local Docker volume, never committed or shared with the Mac.",
        "RUN mkdir -p /commandhistory \\",
        "    && touch /commandhistory/.bash_history /commandhistory/.zsh_history \\",
        f"    && chown -R {user}:{user} /commandhistory \\",
        "    && printf '%s\\n' 'export HISTFILE=/commandhistory/.bash_history' \\",
        "         'PROMPT_COMMAND=\"history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}\"' >> /etc/bash.bashrc \\",
        "    && mkdir -p /etc/zsh \\",
        "    && printf '%s\\n' 'HISTFILE=/commandhistory/.zsh_history' 'SAVEHIST=10000' 'HISTSIZE=10000' \\",
        "         'setopt INC_APPEND_HISTORY' >> /etc/zsh/zshrc",
        "",
    ]


# Hosts publish IPv6 addresses the container can't route, and PHP/Composer tried them first
# ("Network is unreachable"). With IPv6 off they use IPv4 straight away.
IPV6_OFF = ["    sysctls:", "      net.ipv6.conf.all.disable_ipv6: 1", "      net.ipv6.conf.default.disable_ipv6: 1"]


def no_proxy_hosts(p: Project) -> list[str]:
    """Names that must not go through the proxy: this container's network and the Mac."""
    hosts = ["localhost", "127.0.0.1", "host.docker.internal"]
    if p.uses_ddev:
        if p.php:
            hosts.append("db")
        hosts += p.ddev_addons
        hosts += [l.split(":")[-1] for l in p.ddev_links]
        hosts += p.site_hosts
    return list(dict.fromkeys(hosts))


VSCODE_GIT_ASKPASS_VARS = ("GIT_ASKPASS", "VSCODE_GIT_ASKPASS_MAIN", "VSCODE_GIT_ASKPASS_NODE",
                           "VSCODE_GIT_ASKPASS_EXTRA_ARGS", "VSCODE_GIT_IPC_HANDLE")


def vscode_tooling(p: Project) -> tuple[list[str], dict]:
    """Extensions and editor settings for the project's stack.

    Format on save only touches the lines you changed (modificationsIfAvailable), so saving a
    legacy file doesn't reformat all of it, and Prettier only runs where the repo has a config.
    EE templates are never formatted on save: Prettier doesn't understand {exp:} / {if} tags.
    """
    dev = p.composer.get("require-dev", {}) | p.composer.get("require", {})
    ext = list(ALWAYS_EXTENSIONS)
    settings: dict = {
        "editor.formatOnSave": True,
        "editor.formatOnSaveMode": "modificationsIfAvailable",
        "editor.defaultFormatter": "esbenp.prettier-vscode",
        "prettier.requireConfig": True,
    }
    if p.php:
        ext += ["bmewburn.vscode-intelephense-client", "xdebug.php-debug"]
        php_formatter = "bmewburn.vscode-intelephense-client"
        if "laravel/pint" in dev:
            ext.append("open-southeners.laravel-pint")
            php_formatter = "open-southeners.laravel-pint"
        if "squizlabs/php_codesniffer" in dev:
            # The repo's own standard (phpcbf) wins over Intelephense's built-in style.
            ext.append("obliviousharmony.vscode-php-codesniffer")
            php_formatter = "obliviousharmony.vscode-php-codesniffer"
        settings["[php]"] = {"editor.defaultFormatter": php_formatter}
    if "laravel" in p.stack:
        ext += ["laravel.vscode-laravel", "onecentlin.laravel-blade", "shufo.vscode-blade-formatter"]
        settings["[blade]"] = {"editor.defaultFormatter": "shufo.vscode-blade-formatter"}
    if "expressionengine" in p.stack:
        ext += ["jrrdnx.expressionengine", "mrmlnc.vscode-apache"]
        settings["files.associations"] = {"**/system/user/templates/**/*.html": "expressionengine"}
        settings["[expressionengine]"] = {"editor.formatOnSave": False}
    if "craftcms" in p.stack:
        ext.append("mblode.twig-language-2")
        settings["[twig]"] = {"editor.formatOnSave": False}
    if "tailwind" in p.stack:
        ext.append("bradlc.vscode-tailwindcss")
    if "alpinejs" in p.deps or "expressionengine" in p.stack:
        ext.append("adrianwilczynski.alpine-js-intellisense")
    if "eslint" in p.deps:
        ext.append("dbaeumer.vscode-eslint")
    if "astro" in p.stack:
        ext.append("astro-build.astro-vscode")
    if p.python:
        ext.append("ms-python.python")
    return vscode_policy.apply(list(dict.fromkeys(ext)), settings, p.vscode)


def container_settings(p: Project) -> dict:
    """devcontainer.json's customizations.vscode.settings. The isolation keys go last, so nothing
    can override them (vscode_policy refuses them in [vscode] too).

    They stop VS Code injecting the askpass variables into terminals, and the GitHub extension
    supplying the Mac's token to git, so the only GitHub login inside is gh's."""
    return {**vscode_tooling(p)[1], "git.terminalAuthentication": False, "github.gitAuthentication": False}


# Installed in every container: Claude Code (it signs in with the CLI's login on the claude-config volume,
# via CLAUDE_CONFIG_DIR), API requests, formatting, and everyday editing.
ALWAYS_EXTENSIONS = ["anthropic.claude-code", "humao.rest-client", "editorconfig.editorconfig", "esbenp.prettier-vscode",
                     "usernamehw.errorlens", "mhutchie.git-graph", "mikestead.dotenv"]


def gallery_hosts(extensions: list[str]) -> list[str]:
    """Marketplace hosts that serve these extensions' packages.

    VS Code downloads each extension from <publisher>.gallerycdn.vsassets.io (falling back to
    <publisher>.gallery.vsassets.io). When the container can't reach them, VS Code downloads on the
    Mac and copies the package in; that relay never finished for Claude Code's large per-platform
    package, so the extension silently went missing.
    """
    publishers = sorted({e.split(".", 1)[0].lower() for e in extensions})
    return [f"{pub}.{cdn}.vsassets.io" for pub in publishers for cdn in ("gallerycdn", "gallery")]


def home_path(path: str, user: str) -> str:
    """'~/.config/x' -> '/home/<user>/.config/x' (inside the container)."""
    return f"/home/{user}/" + path[2:] if path.startswith("~/") else path


def mac_path(path: str) -> str:
    """'~/.config/x' -> '${HOME}/.config/x' (a docker-compose source on the Mac)."""
    return "${HOME}/" + path[2:] if path.startswith("~/") else path


def integrations_with(p: Project, attr: str) -> list:
    return [i for i in (p.policy.integrations if p.policy else []) if getattr(i, attr)]


def own_volume_lines(p: Project, user: str) -> list[str]:
    # New Docker volumes start out root-owned. gh keeps its (token-free) settings in ~/.config/gh.
    paths = [f"/home/{user}/.config/gh"]
    paths += [home_path(i.mount["target"], user) for i in integrations_with(p, "mount") if i.mount.get("volume")]
    paths += [p.node_modules] if p.node_modules else []
    return ["set -e"] + [f"mkdir -p {d} && chown {user}:{user} {d}" for d in dict.fromkeys(paths)]


def github_lines(p: Project, user: str) -> list[str]:
    """Dockerfile lines that let git push/pull through gh, whose token the egress proxy supplies."""
    item = p.policy.settings.get("github_keychain", "ai-devcontainer-github") if p.policy else "ai-devcontainer-github"
    return [
        "# GitHub from inside: git asks gh, which holds only GH_TOKEN's placeholder; the egress proxy",
        f"# swaps in the real token (Keychain item {item} on the Mac). SSH remotes are",
        "# rewritten to HTTPS in here only. The Mac's SSH key and keychain never come in.",
        f"RUN mkdir -p /home/{user}/.config/gh && chown -R {user}:{user} /home/{user}/.config \\",
        "    && git config --system credential.https://github.com.helper '' \\",
        "    && git config --system --add credential.https://github.com.helper '!gh auth git-credential' \\",
        "    && git config --system url.https://github.com/.insteadOf git@github.com: \\",
        "    && git config --system --add url.https://github.com/.insteadOf ssh://git@github.com/",
        "",
    ]


# Global skills every container gets when they exist on the Mac (ai-config links them into
# ~/.claude/skills). Integrations add their own ([skills]).
GLOBAL_SKILLS = [("noslop", "pages for a reader (its profile comes from ~/.config/ai-config, mounted below)"),
                 ("humanizer", "prose edits")]


def shared_skill_mounts(p: Project, user: str, home: Path | None = None) -> list[str]:
    home = home or Path.home()
    wanted = list(GLOBAL_SKILLS)
    for it in integrations_with(p, "skills"):
        for s in it.skills:
            if s not in [w[0] for w in wanted]:
                wanted.append((s, it.description or it.name))
    lines: list[str] = []
    for name, what in wanted:
        # Only skills that exist on this Mac: Docker would otherwise create an empty, root-owned folder.
        if (home / ".claude" / "skills" / name / "SKILL.md").exists():
            lines += [f"      # {what}: the Mac's {name} skill, read-only.",
                      f"      - ${{HOME}}/.claude/skills/{name}:/home/{user}/.claude/skills/{name}:ro"]
    # Only what profile.sh reads: the profiles and this Mac's default. Not the rest of the
    # private repo (its own skills, its .git history).
    cfg = home / ".config" / "ai-config"
    if (cfg / "profiles").is_dir():
        lines += ["      # ai-config profiles (who pages are from, the share domain), read-only.",
                  f"      - ${{HOME}}/.config/ai-config/profiles:/home/{user}/.config/ai-config/profiles:ro"]
        if (cfg / "profile").is_file():
            lines += [f"      - ${{HOME}}/.config/ai-config/profile:/home/{user}/.config/ai-config/profile:ro"]
    return lines


def common_hooks_mount(user: str, home: Path | None = None) -> list[str]:
    """The trusted safety guard from this checkout, read-only so Claude can't edit it.

    A bind mount of the checkout rather than a copy: the container runs whatever version
    has been pulled, with nothing to sync.
    """
    home = home or Path.home()
    hooks = KIT.parent / "projects" / "common" / "hooks"
    if not (hooks / "safety-guard.sh").is_file():
        return []
    try:
        src = "${HOME}/" + hooks.relative_to(home).as_posix()
    except ValueError:
        src = hooks.as_posix()
    return ["      # Commit check: the trusted safety guard from the ai-config checkout, read-only so Claude can't edit it.",
            f"      - {src}:/home/{user}/.claude/hooks:ro"]


def integration_mounts(p: Project, user: str) -> tuple[list[str], list[str]]:
    """(volume lines for the claude service, named volumes) for integrations with a [mount]."""
    lines, volumes = [], []
    egress = f"{EGRESS_DIR}/projects/{p.key}/mounts"
    for it in integrations_with(p, "mount"):
        m = it.mount
        target = home_path(m["target"], user)
        files = [*m.get("copy", []), *([m["placeholder"]] if m.get("placeholder") else [])]
        lines.append(f"      # {it.description or it.name}: the Mac's config, read-only; its key file is a placeholder.")
        if m.get("volume"):
            vol = f"{it.name}-config"
            volumes.append((vol, m["volume"]))
            lines.append(f"      - {vol}:{target}")
            lines += [f"      - {egress}/{it.name}/{f}:{target}/{f}:ro" for f in files]
        else:
            lines.append(f"      - {egress}/{it.name}:{target}:ro")
    return lines, volumes


def gen_compose(p: Project) -> str:
    _, user = base_image(p)
    vol = ["      # The project, writable.", "      - ..:/workspace:cached",
           "      # Guardrails and the sandbox definition, read-only inside (edit them on the Mac)."]
    vol += guardrail_mounts(p)
    vol += ["      # Claude Code sign-in + settings survive rebuilds.", f"      - claude-config:/home/{user}/.claude",
            "      # Shell history (bash/zsh) survives rebuilds.", "      - command-history:/commandhistory",
            "      # Tokens never come in. The egress proxy adds them on the way out; inside are placeholders",
            "      # and the certificate of this Mac's interception CA (egress-credentials.sh).",
            f"      - {EGRESS_DIR}/ca.crt:{EGRESS_CA_IN_CONTAINER}:ro"]
    mount_lines, named = integration_mounts(p, user)
    vol += mount_lines
    vol += shared_skill_mounts(p, user)
    vol += common_hooks_mount(user)
    vol += ["      # VS Code extensions survive rebuilds (Claude Code's alone is 135 MB).",
            f"      - vscode-extensions:/home/{user}/.vscode-server/extensions"]
    if p.node_modules:
        vol += ["      # Linux node_modules, kept apart from the Mac's: native modules (sharp, esbuild) are per OS.",
                f"      - node-modules:{p.node_modules}"]
    vol += ["      # This project's token for the relay on the Mac (ensure-relay.sh writes it): domain requests",
            "      # (sandbox-domains) and, for DDEV projects, ddev start/stop/logs. No other project's token is here.",
            f"      - {STATE}/relay/tokens/{p.key}.token:/run/ddev-relay/token:ro",
            "      # Deliberately NOT mounted: ~/.aws, ~/.ssh, ~/.gitconfig, the Mac's ~/.config/gh, the Docker socket,",
            "      # the CA's key and credentials.env (egress proxy only)."]
    env = [f"      CLAUDE_CONFIG_DIR: /home/{user}/.claude",
           "      # gh (and git, through gh's credential helper) send this; the egress proxy swaps in the",
           "      # real token for the GitHub hosts only.",
           f"      GH_TOKEN: {EGRESS_PLACEHOLDER}",
           "      # Node and Python's requests don't read the system trust store that sandbox-trust-ca.sh fills.",
           f"      NODE_EXTRA_CA_CERTS: {EGRESS_CA_IN_CONTAINER}",
           "      REQUESTS_CA_BUNDLE: /etc/ssl/certs/ca-certificates.crt",
           "      # Not CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: it also stops the plan-usage fetch, so",
           "      # Account & Usage shows nothing. These are the parts of it worth keeping. Claude Code",
           "      # lives in the image, so it updates on rebuild, not in place.",
           '      DISABLE_TELEMETRY: "1"',
           '      DISABLE_ERROR_REPORTING: "1"',
           '      DISABLE_BUG_COMMAND: "1"',
           '      DISABLE_AUTOUPDATER: "1"']
    if p.policy and p.policy.profile:
        env += ["      # The ai-config profile this project uses on the Mac (folder maps don't match /workspace).",
                f"      AI_CONFIG_PROFILE: {p.policy.profile}"]
    if p.package:
        env += ["      # Node resolves `localhost` to ::1 here, so dev servers (Vite) listen on IPv6 only and",
                "      # VS Code's port forwarding, which connects to 127.0.0.1, hangs. Prefer IPv4.",
                '      NODE_OPTIONS: "--dns-result-order=ipv4first"']
    if p.php:
        env.append('      # The base image enables Xdebug; off unless asked for (XDEBUG_MODE=debug php …).')
        env.append('      XDEBUG_MODE: "off"')
    if p.uses_ddev:
        env.append(f"      DDEV_PROJECT: {p.ddev_name}")
        if p.php and p.db_name != "db":
            env.append("      # The database the site uses; `ddev mysql` opens it (DDEV's own `db` is empty here).")
            env.append(f"      DDEV_DB_NAME: {p.db_name}")
        env.append(f"      DDEV_DOCROOT: \"{p.ddev.get('docroot', '')}\"")
    if p.git_name or p.git_email:
        name = p.git_name or "CHANGE ME"
        email = p.git_email or "change-me@example.com"
        env += [f"      GIT_AUTHOR_NAME: {json.dumps(name)}", f"      GIT_AUTHOR_EMAIL: {email}",
                f"      GIT_COMMITTER_NAME: {json.dumps(name)}", f"      GIT_COMMITTER_EMAIL: {email}"]
    proxy = f"http://{PROXY_HOST}:{PROXY_PORT}"
    no_proxy = ",".join(no_proxy_hosts(p))
    env += ["      # Web traffic goes through the egress proxy, which allows allowed-domains.txt (and",
            "      # domains.conf) by host name, so CDN address changes don't matter (curl, Composer, npm,",
            "      # git, gh, Claude Code and WP-CLI all honour these). Local names go direct.",
            *[f'      {var}: "{proxy}"' for var in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy")],
            f'      NO_PROXY: "{no_proxy}"', f'      no_proxy: "{no_proxy}"']
    out = [f"# Generated by {TOOL} {VERSION}.", "services:", "  claude:",
           "    build:", "      context: .", "      dockerfile: Dockerfile",
           "    command: sleep infinity", "    volumes:", *vol, "    environment:", *env]
    if p.uses_ddev:
        links = []
        if p.php and not any(l.split(":")[-1] == "db" for l in p.ddev_links):
            links.append(f"      - ddev-{p.ddev_name}-db:db")
        for addon in p.ddev_addons:
            links.append(f"      - ddev-{p.ddev_name}-{addon}:{addon}")
        links += [f"      - {l}" for l in p.ddev_links]
        if p.site_hosts:
            links += ["      # The site itself (every language's host name), through DDEV's router, so",
                      "      # BrowserSync/Vite/Playwright can reach it.",
                      *[f"      - ddev-router:{h}" for h in p.site_hosts]]
        out += ["    # The same host names DDEV's web container sees.", "    external_links:", *links]
    out += ["    cap_add:", "      - NET_ADMIN", "      - NET_RAW", *IPV6_OFF,
            "    depends_on:", f"      - {PROXY_HOST}"]
    if p.uses_ddev:
        # default is this project's own network, where the proxy lives; the proxy never joins
        # ddev_default, so another project's proxy can't answer to the same name.
        out += ["    networks:", "      - ddev", "      - default"]
    out += ["", f"  {PROXY_HOST}:",
            "    # Squid: CONNECT/HTTP only to host names in allowed-domains.txt and domains.conf [allow],",
            "    # never to domains.conf [block]; re-read every 15 s. The folder, not the files, is mounted so",
            "    # an editor's save-by-rename shows up.",
            "    build:", "      context: .", "      dockerfile: Dockerfile.proxy",
            "    restart: unless-stopped", "    volumes:", "      - .:/etc/sandbox:ro",
            "      # This Mac's interception CA (key included) and this project's real tokens: here only,",
            "      # never in the claude service. Written on the Mac by egress-credentials.sh from the Keychain.",
            f"      - {EGRESS_DIR}/ca.crt:/etc/sandbox-egress-ca/ca.crt:ro",
            f"      - {EGRESS_DIR}/ca.key:/etc/sandbox-egress-ca/ca.key:ro",
            f"      - {EGRESS_DIR}/projects/{p.key}:/etc/sandbox-egress:ro", *IPV6_OFF]
    if p.uses_ddev:
        out += ["", "networks:", "  ddev:", "    external: true", "    name: ddev_default"]
    out += ["", "volumes:", "  claude-config:", "  command-history:", "  vscode-extensions:"]
    for vol_key, name in named:
        out += [f"  {vol_key}:", f"    name: {name}"]
    if p.node_modules:
        out.append("  node-modules:")
    out.append("")
    return "\n".join(out)


def init_command(p: Project) -> str:
    """Runs on the Mac before the container starts: the egress CA and this project's tokens, the
    relay (every project: domain requests), and DDEV (DDEV projects)."""
    ws = "\"${localWorkspaceFolder}\""
    cmd = f"/bin/bash {ws}/.devcontainer/egress-credentials.sh {ws} {p.key}"
    if p.uses_ddev:
        cmd += f" && /bin/bash {ws}/.devcontainer/ensure-ddev.sh {ws} {p.key}"
    else:
        cmd += f" && /bin/bash {ws}/.devcontainer/ensure-relay.sh {ws} {p.key}"
    return cmd.replace('""', '"')


def gen_devcontainer_json(p: Project) -> str:
    image, user = base_image(p)
    features = {}
    # Node and Claude Code are installed by the Dockerfile (node_and_claude_lines), where the
    # build cache keeps them; features were reinstalled on every rebuild.
    if p.python and (p.php or p.node):
        features["ghcr.io/devcontainers/features/python:1"] = {"version": "3.12"}
    features["ghcr.io/devcontainers/features/github-cli:1"] = {}

    ext = vscode_tooling(p)[0]

    cfg = {
        "name": f"{p.folder} · Claude sandbox",
        "dockerComposeFile": "docker-compose.yml",
        "service": "claude",
        "workspaceFolder": "/workspace",
        "remoteUser": user,
    }
    cfg["initializeCommand"] = init_command(p)
    cfg["features"] = features
    # philter-setup.sh runs as the user (it writes the user's Claude config) and never fails.
    cfg["postStartCommand"] = ("sudo /usr/local/sbin/sandbox-trust-ca.sh "
                               "&& sudo /usr/local/sbin/sandbox-firewall.sh "
                               "&& sudo /usr/local/sbin/sandbox-own-volumes.sh "
                               "&& bash /workspace/.devcontainer/philter-setup.sh")
    cfg["waitFor"] = "postStartCommand"
    # No route back to the Mac's git credentials: no SSH agent, and none of the variables through
    # which VS Code's Git extension answers HTTPS password prompts with the Mac's GitHub login.
    # GitHub still works: git asks gh, whose token the egress proxy adds.
    cfg["remoteEnv"] = {"SSH_AUTH_SOCK": "", **{v: "" for v in VSCODE_GIT_ASKPASS_VARS},
                        "GIT_TERMINAL_PROMPT": "0"}
    ports = sorted({port for dep, port in NODE_FRAMEWORK_PORTS.items() if dep in p.deps}
                   | {port for dep, extra in EXTRA_PORTS.items() if dep in p.deps for port in extra})
    if ports:
        # Labels only, no forwardPorts: a static forward grabs the Mac's port as soon as the window
        # opens, which stopped DDEV's router (it needs 3000/3001/5173 for other projects). VS Code
        # auto-forwards a port once something listens on it, and picks another if it's taken.
        cfg["portsAttributes"] = {str(port): {"label": PORT_LABELS.get(port, "dev server"),
                                              "onAutoForward": "notify"} for port in ports}
    cfg["customizations"] = {"vscode": {"extensions": ext, "settings": container_settings(p)}}
    header = (f"// Generated by {TOOL} {VERSION}. Claude sandbox for {p.folder}.\n"
              "// DDEV (if used) keeps running on the Mac; this container joins its network.\n")
    return header + json.dumps(cfg, indent=2, ensure_ascii=False) + "\n"


def allowed_groups(p: Project) -> list[tuple[str, list[str]]]:
    """(title, hosts) groups for allowed-domains.txt, before the block list is applied."""
    groups = [("Claude Code", CLAUDE_HOSTS), ("VS Code extensions", VSCODE_HOSTS),
              ("VS Code extension downloads (one CDN host per publisher)", gallery_hosts(vscode_tooling(p)[0]))]
    if p.package or p.node or any(s.get("command") == "npx" for s in p.mcp.values()):
        groups.append(("npm", NPM_HOSTS))
    if p.composer:
        groups.append(("Composer / Packagist", COMPOSER_HOSTS))
    if "wordpress" in p.stack or "wpackagist.org" in json.dumps(p.composer.get("repositories", [])):
        groups.append(("WordPress core, plugin and theme downloads (wpackagist points here), checksums", WORDPRESS_HOSTS))
    if "craftcms" in p.stack:
        groups.append(("Craft CMS (plugin repo, licensing)", CRAFT_HOSTS))
    extra = []
    for r in p.composer.get("repositories", []):
        if isinstance(r, dict):
            host = re.sub(r"^https?://([^/:]+).*$", r"\1", r.get("url", ""))
            if host and "://" not in host and host not in GITHUB_HOSTS and host not in CRAFT_HOSTS:
                extra.append(host)
    if extra:
        groups.append(("Composer repositories from composer.json", sorted(set(extra))))
    if "connect.advancedcustomfields.com" in extra:
        groups.append(("ACF Pro downloads (redirected to signed Google Cloud Storage URLs)", ["storage.googleapis.com"]))
    if p.python:
        groups.append(("Python packages", PYTHON_HOSTS))
    pol = p.policy
    for it in (pol.integrations if pol else []):
        hosts = list(it.hosts)
        if it.name == "github":
            # Actions logs and artifacts live on Azure blob shards GitHub names one by one.
            hosts += [f"productionresultssa{i}.blob.core.windows.net" for i in range(20)]
        if hosts:
            groups.append((f"{it.description or it.name} [integration: {it.name}]", hosts))
    if pol and pol.domains:
        groups.append(("Your organization's domains and all their subdomains (profile devcontainer_domains, "
                       "[sandbox] domains)", pol.domains))
    if pol and pol.hosts:
        groups.append(("Exact host names, for tools that ignore the proxy (profile devcontainer_hosts, "
                       "[sandbox] hosts)", pol.hosts))
    return groups


def gen_allowed_domains(p: Project) -> str:
    block = p.policy.block if p.policy else []
    out = [f"# Generated by {TOOL} {VERSION}. Regenerated by `ai-config --refresh`: add your own",
           "# domains to domains.conf [allow] instead (or `sandbox-domains allow <name>` inside).",
           "# Hosts the sandbox may reach, by exact name; a leading dot (.example.org) also allows every",
           "# subdomain, but only through the proxy. The egress proxy matches them by name and",
           "# re-reads this file every 15 s; the firewall also allows their current addresses (for",
           "# anything that ignores HTTPS_PROXY), GitHub's IP ranges and the container's own network.",
           "# Inside, the file is read-only.", ""]
    seen: set = set()
    for title, hosts in allowed_groups(p):
        keep = [h for h in hosts if h not in seen and h not in p.refused and not sandbox_policy.blocked(h, block)]
        seen.update(keep)
        if keep:
            out.append(f"# {title}")
            out += keep
            out.append("")
    if block:
        out.append("# Left out on purpose (profile devcontainer_block, [sandbox] block): " + ", ".join(block))
    out.append("# Deliberately absent: AWS/S3, and SSH or admin ports on your servers.")
    return "\n".join(out) + "\n"


def gen_domains_conf(p: Project) -> str:
    """The first domains.conf: written once, never regenerated."""
    block = p.policy.block if p.policy else []
    return "\n".join([
        f"# Created by {TOOL} {VERSION}; never regenerated. Domains you (or Claude, with your",
        "# approval on the Mac) add to the sandbox, and domains to keep out even when a list above",
        "# allows them. One name per line; a leading dot means every subdomain (proxy only).",
        "#",
        "#   inside the container:  sandbox-domains allow api.example.com \"why\"   (asks on the Mac)",
        "#                          sandbox-domains block ads.example.com          (at once)",
        "#   on the Mac:            edit this file; the proxy picks it up within 15 s.",
        "",
        "[allow]",
        "",
        "[block]",
        *block,
        ""])


def gen_token_hosts_conf(p: Project) -> str:
    """Which Keychain items the egress proxy injects, and where. Nothing secret: names only."""
    lines = [f"# Generated by {TOOL} {VERSION}. Read on the Mac by egress-credentials.sh (which tokens to copy",
             "# from the Keychain) and in the proxy by egress-proxy.sh (where to add them). Names only.",
             "# variable<TAB>keychain service<TAB>scheme<TAB>hosts"]
    for it in integrations_with(p, "credential"):
        c = it.credential
        hosts = [h for h in c["hosts"] if h not in p.refused]
        if hosts:
            lines.append("\t".join([c["variable"], c["keychain"], c["scheme"], " ".join(hosts)]))
    return "\n".join(lines) + "\n"


def gen_mounts_conf(p: Project) -> str:
    """Config folders egress-credentials.sh copies (key files replaced by the placeholder)."""
    lines = [f"# Generated by {TOOL} {VERSION}. Read on the Mac by egress-credentials.sh.",
             "# name<TAB>Mac folder<TAB>files to copy (comma-separated)<TAB>placeholder file"]
    for it in integrations_with(p, "mount"):
        m = it.mount
        lines.append("\t".join([it.name, m["source"], ",".join(m.get("copy", [])) or "-", m.get("placeholder") or "-"]))
    return "\n".join(lines) + "\n"


def gen_managed_settings(p: Project) -> str:
    deny = ["Read(**/.env)", "Read(**/.env.*)", "Read(**/.env.php)", "Read(**/*.key)", "Read(**/*.pem)",
            "Read(**/.aws/**)", "Read(**/.ssh/**)", "Read(**/auth.json)", "Read(**/*.sql)"]
    for it in (p.policy.integrations if p.policy else []):
        deny += it.deny
    cfg = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json",
        "disableClaudeAiConnectors": True,
        "permissions": {
            "deny": list(dict.fromkeys(deny)),
            # A push or merge to main or staging deploys, and so can a release or a workflow run:
            # those always ask. Other gh commands (PRs, issues, runs, logs, the API) don't; the
            # safety guard still asks before an explicit -X POST/PUT/PATCH/DELETE to the API.
            "ask": ["Bash(git push:*)", "Bash(gh pr merge:*)", "Bash(gh release create:*)",
                    "Bash(gh release upload:*)", "Bash(gh workflow run:*)", "Bash(gh run rerun:*)"],
            # The philter-scrub mod's calls go through the permission check like any tool. Without
            # these, every scrub asks (or, headless, is denied and the mod blocks the prompt).
            "allow": ["mcp__philter__redact_text", "mcp__philter__list_policies"],
        },
        # Read by safety-guard.sh: PR and issue writes stop asking here (they still do on the Mac).
        # Managed settings are root-owned, so nothing inside can turn this on for itself.
        "env": {"AI_CONFIG_GH_LIGHT_WRITES": "allow"},
    }
    if (p.path / ".claude" / "hooks" / "safety-guard.sh").exists():
        cfg["hooks"] = {"PreToolUse": [{
            "matcher": "Bash|Read|Edit|MultiEdit|Write|NotebookEdit|Grep|mcp__.*",
            "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/safety-guard.sh",
                       "timeout": 10}]}]}
    return json.dumps(cfg, indent=2) + "\n"


def gen_readme(p: Project) -> str:
    pol = p.policy
    where = ("DDEV keeps running on the Mac and serves the site. This container joins DDEV's "
             "network and reaches the database as host `db`." if p.uses_ddev else
             "Standalone container; nothing else needs to run first.")
    lines = [f"# Claude sandbox · {p.folder}", "",
             f"Generated by {TOOL} {VERSION}" + (f" for the `{pol.profile}` profile" if pol and pol.profile else "")
             + f". {where}", "",
             "## Start", ""]
    if p.uses_ddev:
        lines.append(f"1. Nothing to start by hand: opening the container runs `ensure-ddev.sh` on the Mac, which "
                     f"starts DDEV project `{p.ddev_name}` (and any project it links to) and stops it again when "
                     f"the container closes. A project that was already running is left running.")
    lines += ["1. VS Code: **Dev Containers: Reopen in Container**.",
              "1. In the container terminal: `claude` (sign in once; it persists).", "",
              "## Where to run what", "",
              "| Container (you or Claude) | Mac terminal |", "| --- | --- |",
              "| Editing, tests, linters, builds, watch / live reload | `ddev config`, `ddev add-on`, `ddev exec/ssh`, `ddev delete/poweroff` |",
              "| `ddev <tool>` → mapped by the shim (artisan, craft, composer, npm, php, mysql, custom web commands) | Anything needing SSH, AWS or production servers |",
              "| `git commit/pull/push/merge`, `gh pr …`, `gh run …` (Claude asks before every push, merge and workflow run) | |",
              ""]
    lines += ["## Domains", "",
              "`allowed-domains.txt` is generated (from the stack, the integrations, the profile and "
              "`[sandbox]` in `ai-config.conf`). `domains.conf` is yours and is never regenerated.", "",
              "```sh",
              "sandbox-domains list                         # what's allowed and blocked, and where it came from",
              "sandbox-domains allow api.example.com \"why\"  # asks on the Mac (Deny is the default)",
              "sandbox-domains block ads.example.com        # at once, no dialog",
              "sandbox-domains unblock ads.example.com      # asks on the Mac",
              "```", "",
              "Both files are read-only in here: Claude can ask for a domain, never grant one. Requests are "
              "logged in `~/.cache/ai-devcontainer/relay/relay.log` on the Mac.", ""]
    if pol and pol.integrations:
        lines += ["## Integrations", ""] + [f"- `{i.name}`: {i.description}" for i in pol.integrations] + [
            "", "Change them with `integrations = +name, -name` under `[sandbox]` in `ai-config.conf`, then "
            "`ai-config --refresh` and **Rebuild Container**.", ""]
    if p.uses_ddev:
        lines += ["## DDEV from inside", "",
                  "`ddev start`, `stop`, `restart`, `describe`, `list`, `logs`, `snapshot` and `import-db`/`export-db` "
                  "(files inside the project) go to a relay on the Mac (`ddev-relay.pl`, started by `ensure-relay.sh`), "
                  "which runs them for this project only. `snapshot restore` and `import-db` open an Allow/Deny dialog "
                  "on the Mac and take a snapshot first. Everything else is refused: `exec`/`ssh` above all, since the "
                  "web container can write `.ddev`, whose hooks run on the Mac.", ""]
        if (p.path / ".admin-scripts" / "ee-migrate.sh").is_file():
            lines += [EE_MIGRATE_RELAY_NOTE, ""]
    creds = integrations_with(p, "credential")
    gh_item = pol.settings.get("github_keychain", "ai-devcontainer-github") if pol else "ai-devcontainer-github"
    org = pol.settings.get("github_org") if pol else None
    lines += ["## Tokens", "",
              "No token is inside the container. The real ones stay in the Mac's Keychain; "
              "`egress-credentials.sh` (run on the Mac before the container starts) hands them to the "
              "`egress-proxy` service only, which adds them to HTTPS requests for these hosts:", ""]
    lines += [f"- `{i.name}`: Keychain item `{i.credential['keychain']}` → " + ", ".join(f"`{h}`" for h in i.credential["hosts"])
              for i in creds]
    lines += ["",
              f"Inside, `GH_TOKEN` and the skills' key files hold the placeholder `{EGRESS_PLACEHOLDER}`. "
              "`gh` and git (through gh) work as usual; SSH remotes are rewritten to HTTPS inside only.",
              "",
              "Set up GitHub once per Mac, in a Mac terminal (it asks for the token without echoing it), "
              "then reopen the container:",
              "",
              "```sh",
              f'security add-generic-password -U -s {gh_item} -a "$USER" -w',
              "```",
              "",
              "Use a fine-grained token limited to " + (f"the {org} repos" if org else "the repos this work needs")
              + ": Contents, Pull requests and Actions read/write (add Workflows only to edit "
              "`.github/workflows` from here). Revoking it on GitHub cuts off every container at once.",
              "",
              "After a kit upgrade, use **Dev Containers: Rebuild and Reopen in Container** (or **Rebuild "
              "Container** from inside): plain Reopen restarts the old container with its old mounts.",
              ""]
    preview = []
    if p.site_host:
        preview.append(f"- https://{p.site_host} in the Mac's browser shows edits made here straight away: "
                       "DDEV serves the same files.")
    ports = sorted({port for dep, port in NODE_FRAMEWORK_PORTS.items() if dep in p.deps})
    if ports:
        preview.append("- Live reload: run the project's watch script here, then open "
                       + " or ".join(f"http://localhost:{port}" for port in ports) + " on the Mac.")
    if p.node_modules:
        preview.append(f"- `{p.node_modules.removeprefix('/workspace/')}` is a Linux copy on a Docker volume, "
                       "separate from the Mac's: run `npm ci` here once after the first build.")
    if preview:
        lines += ["## Preview", ""] + preview + [""]
    if p.info:
        lines += ["## Handled automatically", ""] + [f"- {i}" for i in p.info] + [""]
    lines += ["## Manual follow-ups", ""]
    lines += [f"- [ ] {n}" for n in p.notes] if p.notes else ["None."]
    lines += ["", "## If something's blocked", "",
              "- A site you need: `sandbox-domains allow <name>` and approve it on the Mac, or add it to "
              "`domains.conf` [allow] on the Mac. The egress proxy picks it up within 15 s; tools that ignore "
              "`HTTPS_PROXY` need `sudo /usr/local/sbin/sandbox-firewall.sh` inside (sandbox-domains runs it).",
              f"- Proxy refusals show in `docker logs` of the `{PROXY_HOST}` container on the Mac (`TCP_DENIED` "
              "= not on the list).",
              "- The DB stops answering after `ddev restart`: `sudo /usr/local/sbin/sandbox-firewall.sh`.",
              "- Prompts or tool output withheld by Philter: Philter runs on the Mac; `/scrub` shows its state, "
              "`bash /workspace/.devcontainer/philter-setup.sh` reconnects.",
              "- `.devcontainer/` and the guardrail files are read-only inside: edit them on the Mac.", ""]
    return "\n".join(lines)


def gen_proxy_dockerfile() -> str:
    return "\n".join([
        f"# Generated by {TOOL} {VERSION}. The egress proxy (see egress-proxy.sh).",
        "FROM debian:bookworm-slim",
        "# squid-openssl: TLS interception for the few hosts it injects tokens into;",
        "# ca-certificates: it verifies those hosts' real certificates itself.",
        "RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \\",
        "    && apt-get install -y --no-install-recommends squid-openssl ca-certificates \\",
        "    && apt-get clean && rm -rf /var/lib/apt/lists/*",
        "COPY egress-proxy.sh /usr/local/sbin/egress-proxy.sh",
        "RUN chmod 755 /usr/local/sbin/egress-proxy.sh",
        f"EXPOSE {PROXY_PORT}",
        'ENTRYPOINT ["/usr/local/sbin/egress-proxy.sh"]',
        ""])


def render_kit(p: Project) -> dict[str, str]:
    """Generated files (name -> text), without the copied scripts or domains.conf."""
    return {
        "Dockerfile": gen_dockerfile(p),
        "docker-compose.yml": gen_compose(p),
        "Dockerfile.proxy": gen_proxy_dockerfile(),
        "devcontainer.json": gen_devcontainer_json(p),
        "allowed-domains.txt": gen_allowed_domains(p),
        "token-hosts.conf": gen_token_hosts_conf(p),
        "mounts.conf": gen_mounts_conf(p),
        "managed-settings.json": gen_managed_settings(p),
        "README.md": gen_readme(p),
    }


def sha(text: bytes) -> str:
    return hashlib.sha256(text).hexdigest()


def kit_contents(p: Project) -> dict[str, bytes]:
    files = {name: text.encode() for name, text in render_kit(p).items()}
    for name in KIT_SCRIPTS:
        files[name] = (FILES / name).read_bytes()
    return files


def listed_hosts(path: Path, column: int | None = None) -> set:
    """Host names in a generated allowed-domains.txt (column None) or token-hosts.conf (column 3)."""
    out: set = set()
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0]
        if column is None:
            if line.strip():
                out.add(line.strip())
        else:
            parts = line.split("\t")
            if len(parts) > column:
                out.update(parts[column].split())
    return out


def confirm_widening(p: Project, dest: Path, yes: bool) -> None:
    """A refresh that would let the sandbox reach new hosts, or send a token to new ones, lists
    them and asks first. The project (composer.json, .mcp.json) is writable from inside, so a
    widening may not be the developer's. First generation: nothing to compare, no question.
    Unconfirmed hosts go in p.refused and are left out of this run's files."""
    if not (dest / MANIFEST).is_file():
        return
    files = render_kit(p)
    new_allow = {l.strip() for l in files["allowed-domains.txt"].splitlines() if l.strip() and not l.startswith("#")}
    new_cred = {h for l in files["token-hosts.conf"].splitlines() if not l.startswith("#")
                for h in (l.split("\t")[3].split() if len(l.split("\t")) > 3 else [])}
    added_allow = sorted(new_allow - listed_hosts(dest / "allowed-domains.txt"))
    added_cred = sorted(new_cred - listed_hosts(dest / "token-hosts.conf", 3))
    if not (added_allow or added_cred):
        return
    print("  ! This refresh widens the sandbox:")
    for h in added_allow:
        print(f"      + reach {h}")
    for h in added_cred:
        print(f"      + send a token to {h}")
    ok = yes
    if not ok and sys.stdin.isatty():
        ok = input("    Apply? [y/N] ").strip().lower() in ("y", "yes")
    if not ok:
        p.refused = set(added_allow) | set(added_cred)
        print("    Left out: rerun on a terminal to confirm, or with --yes (ai-config: --force).")


def write_kit(p: Project, dest: Path, update: bool = False) -> list[str]:
    """Write the kit into dest. update=True: a file whose current content isn't what this tool
    last wrote (manifest) is kept, and the new version staged in
    <project>/.claude/ai-config/pending/.devcontainer/. domains.conf is created once, never replaced."""
    dest.mkdir(parents=True, exist_ok=True)
    manifest_path = dest / MANIFEST
    old = {}
    if manifest_path.is_file():
        for line in manifest_path.read_text().splitlines():
            if "\t" in line:
                name, digest = line.split("\t", 1)
                old[name] = digest
    staged, written, manifest = [], [], {}
    for name, data in kit_contents(p).items():
        target = dest / name
        if update and target.exists() and target.read_bytes() != data and old.get(name) != sha(target.read_bytes()):
            # .claude/ai-config is writable from inside the container: never follow a link there.
            pend = p.path / ".claude" / "ai-config" / "pending" / ".devcontainer" / name
            try:
                sandbox_policy.safe_write(p.path, pend, data)
            except OSError as e:
                print(f"  -> not staging {name}: {e}")
                continue
            staged.append(name)
            manifest[name] = old.get(name, "")
            continue
        if not (target.exists() and target.read_bytes() == data):
            target.write_bytes(data)
            written.append(name)
        if name in KIT_SCRIPTS or name.endswith(".sh"):
            target.chmod(0o755)
        manifest[name] = sha(data)
    for name in KEEP_FILES:
        if not (dest / name).exists():
            (dest / name).write_text(gen_domains_conf(p))
            written.append(name)
    manifest_path.write_text("".join(f"{n}\t{d}\n" for n, d in sorted(manifest.items()) if d))
    record_kit_root()
    if staged:
        print(f"  -> kept your edits to {', '.join(staged)}; new versions in .claude/ai-config/pending/.devcontainer/")
    return written


def state_dir() -> Path:
    """~/.cache/ai-devcontainer. On a Mac that ran kit 1.x, a link to ~/.cache/cps-devcontainer, so
    the relay, its tokens and the egress CA stay where running 1.x containers mount them
    (ensure-relay.sh does the same)."""
    cache = Path.home() / ".cache"
    new, old = cache / "ai-devcontainer", cache / "cps-devcontainer"
    if not new.exists() and not new.is_symlink() and old.is_dir() and not old.is_symlink():
        try:
            new.symlink_to(old)
        except OSError:
            pass
    return new


def record_kit_root() -> None:
    """Tell the relay where this checkout is (it compares ee-migrate.sh against the kit's template)."""
    relay = state_dir() / "relay"
    try:
        relay.mkdir(parents=True, exist_ok=True)
        (relay / "kit-root").write_text(str(KIT.parent) + "\n")
    except OSError:
        pass


# ---------------------------------------------------------------- CLI

def summary_line(p: Project) -> str:
    rt = []
    if p.php:
        rt.append(f"php {p.php}")
    if p.node:
        rt.append(f"node {p.node}")
    if p.python:
        rt.append("python")
    ddev = (f"ddev:{p.ddev_name}" if p.uses_ddev else f"(ddev:{p.ddev_name} unused)") if p.ddev else "no-ddev"
    state = "HAS .devcontainer" if (p.path / ".devcontainer").exists() else ""
    return (f"{p.folder:24} {ddev:26} {'/'.join(rt) or '-':22} {','.join(p.stack) or '-':40} "
            f"{len(p.notes)} follow-up(s) {state}")


def report(p: Project) -> None:
    print(f"\n=== {p.folder}  ({p.path})")
    print("  " + summary_line(p))
    for i in p.info:
        print(f"  + {i}")
    for n in p.notes:
        print(f"  ! {n}")


def find_projects(root: Path, only: set[str]) -> list[Path]:
    out = []
    for d in sorted(root.iterdir()):
        if not d.is_dir() or d.name.startswith("."):
            continue
        if only and d.name not in only:
            continue
        if (d / ".git").exists() or (d / ".ddev").exists() or (d / "CLAUDE.md").exists():
            out.append(d)
    return out


def vscode_user_settings() -> Path:
    """The Mac's (or Linux's) VS Code user settings.json; AI_CONFIG_VSCODE_USER_SETTINGS overrides."""
    override = os.environ.get("AI_CONFIG_VSCODE_USER_SETTINGS")
    if override:
        return Path(override)
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Code" / "User" / "settings.json"
    return Path.home() / ".config" / "Code" / "User" / "settings.json"


def print_vscode_overrides(path: Path) -> int:
    """One tab-separated line per setting the project's .vscode/settings.json changes: 'kit'
    (overrides .devcontainer/devcontainer.json), 'user' (overrides the developer's own settings) or
    'personal' (a preference that belongs in user settings), then the key, the workspace value and
    the overridden value as JSON (null for 'personal'). No output when there's nothing to compare.
    Read-only."""
    workspace = vscode_policy.read_jsonc(path / ".vscode" / "settings.json")
    if workspace is None:
        return 0
    rows = []
    # What the container really applies, whichever kit version (or person) wrote it.
    container = vscode_policy.read_jsonc(path / ".devcontainer" / "devcontainer.json") or {}
    kit = container.get("customizations", {}).get("vscode", {}).get("settings", {})
    if isinstance(kit, dict):
        rows += [("kit", *r) for r in vscode_policy.workspace_overrides(workspace, kit)]
    user = vscode_policy.read_jsonc(vscode_user_settings()) or {}
    seen = {r[1] for r in rows}
    rows += [("user", *r) for r in vscode_policy.workspace_overrides(workspace, user) if r[0] not in seen]
    seen |= {r[1] for r in rows}
    same_as_user = vscode_policy.flatten(user)
    rows += [("personal", k, v, None) for k, v in vscode_policy.personal_settings(workspace)
             if k not in seen and same_as_user.get(k, object()) != v]
    for source, key, mine, theirs in rows:
        print("\t".join((source, key, json.dumps(mine), json.dumps(theirs))))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--root", type=Path, help="folder holding many projects")
    g.add_argument("--project", type=Path, help="a single project folder")
    ap.add_argument("--only", default="", help="comma-separated folder names (with --root)")
    ap.add_argument("--list", action="store_true", help="one summary line per project")
    ap.add_argument("--out", type=Path, help="write previews to OUT/<project>/.devcontainer")
    ap.add_argument("--write", action="store_true", help="write .devcontainer/ into each project")
    ap.add_argument("--force", action="store_true", help="overwrite an existing .devcontainer/ (domains.conf is kept)")
    ap.add_argument("--update", action="store_true",
                    help="write, keeping files you edited (new versions staged in .claude/ai-config/pending/.devcontainer/)")
    ap.add_argument("--profile", help="ai-config profile to use (default: the active one, as profile.sh resolves it)")
    ap.add_argument("--yes", action="store_true", help="apply a refresh that widens the sandbox without asking (still listed)")
    ap.add_argument("--db-name", help="the site's database (with --project); default: detected from DDEV's volume")
    ap.add_argument("--vscode-overrides", action="store_true",
                    help="(with --project) list settings .vscode/settings.json changes from the kit's or yours")
    ap.add_argument("--version", action="version", version=VERSION)
    a = ap.parse_args()
    if a.db_name and not a.project:
        ap.error("--db-name needs --project")
    if a.vscode_overrides and not a.project:
        ap.error("--vscode-overrides needs --project")
    if a.profile and not sandbox_policy.NAME_RE.match(a.profile):
        ap.error("--profile: letters, digits, dot, dash or underscore")
    global PROFILE_OVERRIDE
    PROFILE_OVERRIDE = a.profile
    if a.update:
        a.write = True

    paths = [a.project.resolve()] if a.project else find_projects(a.root.resolve(),
                                                                   {s for s in a.only.split(",") if s})
    if not paths:
        print("No projects found.", file=sys.stderr)
        return 2
    if a.vscode_overrides:
        return print_vscode_overrides(paths[0])
    projects = [detect(pth) for pth in paths]
    for p in projects:
        if a.db_name:
            p.db_name = a.db_name
        elif p.uses_ddev and p.php:
            detect_db_name(p)

    if a.list:
        for p in projects:
            print(summary_line(p))
        return 0

    rc = 0
    for p in projects:
        report(p)
        if a.out:
            dest = a.out.resolve() / p.folder / ".devcontainer"
            write_kit(p, dest)
            print(f"  -> preview written to {dest}")
        elif a.write:
            dest = p.path / ".devcontainer"
            ours = (dest / MANIFEST).is_file()
            if dest.exists() and not (a.force or (a.update and ours)):
                why = ("it wasn't written by ai-devcontainer 2.x" if not ours else "it exists")
                print(f"  -> SKIPPED: {dest}: {why} (--update keeps your edits; --force overwrites them)")
                continue
            local = p.path / ".claude" / "settings.local.json"
            if (p.path / ".claude").is_dir() and not local.exists():
                local.write_text("{}\n")
                print("  -> created empty .claude/settings.local.json so it can be mounted read-only")
            # Mounted read-only, so it must exist before the container starts: otherwise the
            # container could create the file that sets what it may reach.
            conf = p.path / "ai-config.conf"
            if not conf.exists():
                sandbox_policy.safe_write(p.path, conf, b"# ai-config project policy (docs/guides/project-policy.md).\n"
                                          b"# [sandbox] here sets what the dev container may reach (docs/guides/sandbox.md).\n")
                print("  -> created ai-config.conf so it can be mounted read-only (commit it)")
            confirm_widening(p, dest, a.yes)
            changed = write_kit(p, dest, update=a.update and not a.force)
            print(f"  -> {dest}: " + (f"{len(changed)} file(s) written" if changed else "already current"))
    if not (a.out or a.write):
        print("\nDry run. Add --out DIR to preview files, or --write to create .devcontainer/ folders.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
