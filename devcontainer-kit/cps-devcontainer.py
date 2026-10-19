#!/usr/bin/env python3
"""
cps-devcontainer: give a project a sandboxed VS Code dev container for Claude Code.

It looks at a project (DDEV config, composer.json, package.json, .mcp.json, the
.claude guardrails) and writes a .devcontainer/ folder following the pattern proven
on Statements Studio:

  * Claude runs in a container; DDEV keeps running on the Mac. A DDEV project's
    container joins DDEV's network and reaches its database as host `db`.
  * Default-deny egress firewall with a per-project allowlist.
  * No ~/.ssh, ~/.aws, ~/.gitconfig, ssh-agent or Docker socket inside.
  * The project's guardrails (.claude/hooks, settings, ai-config.conf, .mcp.json)
    and .devcontainer/ itself are mounted read-only, and a root-owned managed
    settings file re-registers the safety hook and turns off claude.ai connectors.

Everything it can't decide on its own is listed under "Manual follow-ups".

Usage:
  cps-devcontainer.py --root DIR            survey every project under DIR (dry run)
  cps-devcontainer.py --project DIR         one project (dry run)
  cps-devcontainer.py ... --list            one line per project
  cps-devcontainer.py ... --out DIR         write previews to DIR/<project>/.devcontainer
  cps-devcontainer.py ... --write [--force] write .devcontainer/ into the project(s)
  cps-devcontainer.py ... --only a,b        limit --root to these folder names

Standard library only. Run it on the Mac, outside any container.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

VERSION = "1.2.0"
KIT = Path(__file__).resolve().parent
FILES = KIT / "files"

CLAUDE_HOSTS = ["api.anthropic.com", "claude.ai", "claude.com", "platform.claude.com", "downloads.claude.ai"]
VSCODE_HOSTS = ["marketplace.visualstudio.com", "vscode.blob.core.windows.net", "update.code.visualstudio.com"]
NPM_HOSTS = ["registry.npmjs.org"]
COMPOSER_HOSTS = ["packagist.org", "repo.packagist.org", "getcomposer.org",
                  "objects.githubusercontent.com", "raw.githubusercontent.com", "codeload.github.com"]
PYTHON_HOSTS = ["pypi.org", "files.pythonhosted.org"]
CRAFT_HOSTS = ["composer.craftcms.com", "api.craftcms.com"]
CONTEXT7_HOSTS = ["context7.com", "mcp.context7.com"]
GITHUB_HOSTS = {"github.com", "api.github.com", "raw.githubusercontent.com", "objects.githubusercontent.com"}

PHP_EXTS = "pdo_mysql mysqli intl zip gd bcmath exif"
NODE_FRAMEWORK_PORTS = {"next": 3000, "@docusaurus/core": 3000, "astro": 4321, "@sveltejs/kit": 5173, "nuxt": 3000}

# DDEV's own commands; everything else under .ddev/commands/web is the project's.
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
    mcp: dict = field(default_factory=dict)
    stack: list = field(default_factory=list)
    php: str | None = None
    node: str | None = None
    python: bool = False
    git_name: str = ""
    git_email: str = ""
    notes: list = field(default_factory=list)            # manual follow-ups
    info: list = field(default_factory=list)             # things handled automatically

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
    """Top-level scalars, database.type/version, and web_environment variable NAMES only."""
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
                cfg[key] = val
            continue
        if block == "database":
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
    # CMS sites often keep the front-end build in the docroot (cps: public/package.json).
    for folder in dict.fromkeys(["", p.ddev.get("docroot", ""), "public"]):
        p.package = read_json(path / folder / "package.json")
        if p.package:
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
        if not ver and (path / ".nvmrc").exists():
            ver = (path / ".nvmrc").read_text().strip().lstrip("v")
        if not ver:
            m = re.search(r"(\d+)", p.package.get("engines", {}).get("node", ""))
            ver = m.group(1) if m else "lts"
        p.node = ver.split(".")[0] if ver != "lts" else "lts"

    # Git identity (what the Mac uses for this repo)
    for key, attr in (("user.name", "git_name"), ("user.email", "git_email")):
        try:
            val = subprocess.run(["git", "-C", str(path), "config", "--get", key],
                                 capture_output=True, text=True, timeout=5).stdout.strip()
        except Exception:
            val = ""
        setattr(p, attr, val)

    assess(p)
    return p


def assess(p: Project) -> None:
    """Work out what is automatic and what needs a person."""
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
                       "read-only, with writable overlays only where needed (Statements Studio: cps:ro + "
                       "cps/public/uploads:rw). Never mount ~/.aws or ~/.ssh.")
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
    if private:
        p.notes.append("Private Composer repositories need credentials (auth.json), which the container "
                       "doesn't have: run `composer install/update` on the Mac via DDEV. Repos: " + ", ".join(private))
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
        if (p.path / rel).exists():
            out.append(f"      - ../{rel}:/workspace/{rel}:ro")
    out.append("      - ../.devcontainer:/workspace/.devcontainer:ro")
    return out


def gen_dockerfile(p: Project) -> str:
    image, user = base_image(p)
    apt = "iptables ipset iproute2 dnsutils aggregate jq curl python3 sudo"
    if any(p.path.glob("*.sh")):
        apt += " shellcheck perl rsync"       # shell-script repos (e.g. claude-config-repo's test suites)
    if p.uses_ddev and p.php:
        apt += " mariadb-client"
    lines = [f"# Generated by cps-devcontainer {VERSION}. Edit freely; re-running with --force overwrites it.",
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
    lines += [
        "# Root-owned, baked into the image: nothing inside the container can edit these.",
        "# (A non-standard path: a dev container feature once replaced /usr/local/bin/init-firewall.sh.)",
        "COPY init-firewall.sh /usr/local/sbin/sandbox-firewall.sh",
        "COPY allowed-domains.txt /etc/claude-firewall/allowed-domains.txt",
        "COPY ddev-shim.sh /usr/local/bin/ddev",
        "COPY managed-settings.json /etc/claude-code/managed-settings.json",
        "RUN chmod 755 /usr/local/sbin/sandbox-firewall.sh /usr/local/bin/ddev \\",
        "    && chmod 644 /etc/claude-firewall/allowed-domains.txt /etc/claude-code/managed-settings.json",
        "",
        f"# The base image gives \"{user}\" passwordless sudo for everything, which would let",
        "# anything inside run `sudo iptables -F`. Allow only the firewall script.",
        "RUN rm -f /etc/sudoers.d/* \\",
        f"    && echo \"{user} ALL=(root) NOPASSWD: /usr/local/sbin/sandbox-firewall.sh\" > /etc/sudoers.d/{user}-firewall \\",
        f"    && chmod 0440 /etc/sudoers.d/{user}-firewall",
        "",
        f"RUN mkdir -p /home/{user}/.claude && chown -R {user}:{user} /home/{user}/.claude",
        "",
    ] + history_lines(user)
    return "\n".join(lines)


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


def gen_compose(p: Project) -> str:
    _, user = base_image(p)
    vol = ["      # The project, writable.", "      - ..:/workspace:cached",
           "      # Guardrails and the sandbox definition, read-only inside (edit them on the Mac)."]
    vol += guardrail_mounts(p)
    vol += ["      # Claude Code sign-in + settings survive rebuilds.", f"      - claude-config:/home/{user}/.claude",
            "      # Shell history (bash/zsh) survives rebuilds.", "      - command-history:/commandhistory",
            "      # Deliberately NOT mounted: ~/.aws, ~/.ssh, ~/.gitconfig, the Docker socket."]
    env = [f"      CLAUDE_CONFIG_DIR: /home/{user}/.claude",
           '      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"']
    if p.php:
        env.append('      # The base image enables Xdebug; off unless asked for (XDEBUG_MODE=debug php …).')
        env.append('      XDEBUG_MODE: "off"')
    if p.uses_ddev:
        env.append(f"      DDEV_PROJECT: {p.ddev_name}")
        env.append(f"      DDEV_DOCROOT: \"{p.ddev.get('docroot', '')}\"")
    if p.git_name or p.git_email:
        name = p.git_name or "CHANGE ME"
        email = p.git_email or "change-me@example.com"
        env += [f"      GIT_AUTHOR_NAME: {json.dumps(name)}", f"      GIT_AUTHOR_EMAIL: {email}",
                f"      GIT_COMMITTER_NAME: {json.dumps(name)}", f"      GIT_COMMITTER_EMAIL: {email}"]
    out = [f"# Generated by cps-devcontainer {VERSION}.", "services:", "  claude:",
           "    build:", "      context: .", "      dockerfile: Dockerfile",
           "    command: sleep infinity", "    volumes:", *vol, "    environment:", *env]
    if p.uses_ddev:
        links = []
        if p.php and not any(l.split(":")[-1] == "db" for l in p.ddev_links):
            links.append(f"      - ddev-{p.ddev_name}-db:db")
        for addon in p.ddev_addons:
            links.append(f"      - ddev-{p.ddev_name}-{addon}:{addon}")
        links += [f"      - {l}" for l in p.ddev_links]
        out += ["    # The same host names DDEV's web container sees.", "    external_links:", *links]
    out += ["    cap_add:", "      - NET_ADMIN", "      - NET_RAW"]
    if p.uses_ddev:
        out += ["    networks:", "      - ddev", "", "networks:", "  ddev:", "    external: true",
                "    name: ddev_default"]
    out += ["", "volumes:", "  claude-config:", "  command-history:", ""]
    return "\n".join(out)


def gen_devcontainer_json(p: Project) -> str:
    image, user = base_image(p)
    features = {}
    # The Claude Code feature installs through npm and fails without Node, so every image
    # except javascript-node (which ships it) gets the Node feature, project uses Node or not.
    if "javascript-node" not in image:
        features["ghcr.io/devcontainers/features/node:1"] = {"version": p.node or "lts"}
    if p.python and (p.php or p.node):
        features["ghcr.io/devcontainers/features/python:1"] = {"version": "3.12"}
    features["ghcr.io/devcontainers/features/github-cli:1"] = {}
    features["ghcr.io/anthropics/devcontainer-features/claude-code:1.0"] = {}

    ext = []
    if p.php:
        ext += ["bmewburn.vscode-intelephense-client", "xdebug.php-debug"]
    if "craftcms" in p.stack:
        ext.append("mblode.twig-language-2")
    if "tailwind" in p.stack:
        ext.append("bradlc.vscode-tailwindcss")
    if "astro" in p.stack:
        ext.append("astro-build.astro-vscode")
    if p.python:
        ext.append("ms-python.python")

    cfg = {
        "name": f"{p.folder} · Claude sandbox",
        "dockerComposeFile": "docker-compose.yml",
        "service": "claude",
        "workspaceFolder": "/workspace",
        "remoteUser": user,
    }
    if p.uses_ddev and p.php:
        n = p.ddev_name
        cfg["initializeCommand"] = (
            f"docker inspect -f '{{{{.State.Running}}}}' ddev-{n}-db 2>/dev/null | grep -q true "
            f"|| {{ echo 'DDEV project {n} is not running. Run: ddev start'; exit 1; }}")
    elif p.uses_ddev:
        cfg["initializeCommand"] = ("docker network inspect ddev_default >/dev/null 2>&1 "
                                    "|| { echo 'DDEV is not running. Run: ddev start'; exit 1; }")
    cfg["features"] = features
    cfg["postStartCommand"] = "sudo /usr/local/sbin/sandbox-firewall.sh"
    cfg["waitFor"] = "postStartCommand"
    # No route back to the Mac's git credentials: no SSH agent, and none of the variables through
    # which VS Code's Git extension answers HTTPS password prompts with the Mac's GitHub login.
    cfg["remoteEnv"] = {"SSH_AUTH_SOCK": "", **{v: "" for v in VSCODE_GIT_ASKPASS_VARS},
                        "GIT_TERMINAL_PROMPT": "0"}
    ports = sorted({port for dep, port in NODE_FRAMEWORK_PORTS.items() if dep in p.deps})
    if ports:
        cfg["forwardPorts"] = ports
    # Stops VS Code injecting the askpass variables into terminals, and the GitHub extension
    # supplying a token to git, so `git push` from the container has no credentials.
    cfg["customizations"] = {"vscode": {"extensions": ext, "settings": {
        "git.terminalAuthentication": False, "github.gitAuthentication": False}}}
    header = (f"// Generated by cps-devcontainer {VERSION}. Claude sandbox for {p.folder}.\n"
              "// DDEV (if used) keeps running on the Mac; this container joins its network.\n")
    return header + json.dumps(cfg, indent=2) + "\n"


VSCODE_GIT_ASKPASS_VARS = ("GIT_ASKPASS", "VSCODE_GIT_ASKPASS_MAIN", "VSCODE_GIT_ASKPASS_NODE",
                           "VSCODE_GIT_ASKPASS_EXTRA_ARGS", "VSCODE_GIT_IPC_HANDLE")


def gen_allowed_domains(p: Project) -> str:
    groups = [("Claude Code", CLAUDE_HOSTS), ("VS Code extensions", VSCODE_HOSTS)]
    if p.package or p.node or any(s.get("command") == "npx" for s in p.mcp.values()):
        groups.append(("npm", NPM_HOSTS))
    if p.composer:
        groups.append(("Composer / Packagist", COMPOSER_HOSTS))
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
    if p.python:
        groups.append(("Python packages", PYTHON_HOSTS))
    if "context7" in p.mcp:
        groups.append(("Context7 docs MCP", CONTEXT7_HOSTS))
    out = [f"# Generated by cps-devcontainer {VERSION}.",
           "# Hosts the sandbox may reach. GitHub's IP ranges are added automatically, and the",
           "# container's own network (DDEV's, when used) is always reachable.",
           "# Edit on the Mac, then Dev Containers: Rebuild Container.", ""]
    for title, hosts in groups:
        out.append(f"# {title}")
        out += hosts
        out.append("")
    out.append("# Deliberately absent: AWS/S3, production sites, your servers.")
    return "\n".join(out) + "\n"


def gen_managed_settings(p: Project) -> str:
    cfg = {
        "$schema": "https://json.schemastore.org/claude-code-settings.json",
        "disableClaudeAiConnectors": True,
        "permissions": {
            "deny": ["Read(**/.env)", "Read(**/.env.*)", "Read(**/.env.php)", "Read(**/*.key)", "Read(**/*.pem)",
                     "Read(**/.aws/**)", "Read(**/.ssh/**)", "Read(**/auth.json)", "Read(**/*.sql)"],
            "ask": ["Bash(git push:*)", "Bash(gh pr create:*)", "Bash(gh pr merge:*)",
                    "Bash(gh pr edit:*)", "Bash(gh release create:*)"],
        },
    }
    if (p.path / ".claude" / "hooks" / "safety-guard.sh").exists():
        cfg["hooks"] = {"PreToolUse": [{
            "matcher": "Bash|Read|Edit|MultiEdit|Write|NotebookEdit|Grep|mcp__.*",
            "hooks": [{"type": "command", "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/safety-guard.sh",
                       "timeout": 10}]}]}
    return json.dumps(cfg, indent=2) + "\n"


def gen_readme(p: Project) -> str:
    where = ("DDEV keeps running on the Mac and serves the site. This container joins DDEV's "
             "network and reaches the database as host `db`." if p.uses_ddev else
             "Standalone container; nothing else needs to run first.")
    lines = [f"# Claude sandbox · {p.folder}", "",
             f"Generated by cps-devcontainer {VERSION}. {where}", "",
             "## Start", ""]
    if p.uses_ddev:
        lines.append(f"1. On the Mac: `ddev start` (project `{p.ddev_name}`).")
    lines += ["1. VS Code: **Dev Containers: Reopen in Container**.",
              "1. In the container terminal: `claude` (sign in once; it persists).", "",
              "## Where to run what", "",
              "| Container (you or Claude) | Mac terminal |", "| --- | --- |",
              "| Editing, tests, linters, builds | `ddev start/stop`, DB imports/exports |",
              "| `ddev <tool>` → mapped by the shim (artisan, craft, composer, npm, php, mysql, custom web commands) | Anything needing SSH, AWS or production |",
              "| `git commit` | `git push`, `gh pr …`, deploys |", "",
              "The container has no git credentials: no SSH agent, no credential helper, and VS Code's "
              "Git askpass is switched off, so `git push` fails here by design. Push from the Mac.", ""]
    if p.info:
        lines += ["## Handled automatically", ""] + [f"- {i}" for i in p.info] + [""]
    lines += ["## Manual follow-ups", ""]
    lines += [f"- [ ] {n}" for n in p.notes] if p.notes else ["None."]
    lines += ["", "## If something's blocked", "",
              "- A site you need: add it to `allowed-domains.txt` on the Mac, rebuild.",
              "- npm/Composer or the DB stops answering (after `ddev restart`, or CDN IPs rotate): "
              "`sudo /usr/local/sbin/sandbox-firewall.sh`.",
              "- `.devcontainer/` and the guardrail files are read-only inside: edit them on the Mac.", ""]
    return "\n".join(lines)


def write_kit(p: Project, dest: Path) -> list[str]:
    dest.mkdir(parents=True, exist_ok=True)
    files = {
        "Dockerfile": gen_dockerfile(p),
        "docker-compose.yml": gen_compose(p),
        "devcontainer.json": gen_devcontainer_json(p),
        "allowed-domains.txt": gen_allowed_domains(p),
        "managed-settings.json": gen_managed_settings(p),
        "README.md": gen_readme(p),
    }
    for name, text in files.items():
        (dest / name).write_text(text)
    for name in ("init-firewall.sh", "ddev-shim.sh"):
        shutil.copy2(FILES / name, dest / name)
        (dest / name).chmod(0o755)
    return sorted(files) + ["ddev-shim.sh", "init-firewall.sh"]


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


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--root", type=Path, help="folder holding many projects")
    g.add_argument("--project", type=Path, help="a single project folder")
    ap.add_argument("--only", default="", help="comma-separated folder names (with --root)")
    ap.add_argument("--list", action="store_true", help="one summary line per project")
    ap.add_argument("--out", type=Path, help="write previews to OUT/<project>/.devcontainer")
    ap.add_argument("--write", action="store_true", help="write .devcontainer/ into each project")
    ap.add_argument("--force", action="store_true", help="overwrite an existing .devcontainer/")
    ap.add_argument("--version", action="version", version=VERSION)
    a = ap.parse_args()

    paths = [a.project.resolve()] if a.project else find_projects(a.root.resolve(),
                                                                   {s for s in a.only.split(",") if s})
    if not paths:
        print("No projects found.", file=sys.stderr)
        return 2
    projects = [detect(pth) for pth in paths]

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
            if dest.exists() and not a.force:
                print(f"  -> SKIPPED: {dest} exists (use --force to overwrite; your edits would be lost)")
                continue
            local = p.path / ".claude" / "settings.local.json"
            if (p.path / ".claude").is_dir() and not local.exists():
                local.write_text("{}\n")
                print("  -> created empty .claude/settings.local.json so it can be mounted read-only")
            write_kit(p, dest)
            print(f"  -> written to {dest}")
    if not (a.out or a.write):
        print("\nDry run. Add --out DIR to preview files, or --write to create .devcontainer/ folders.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
