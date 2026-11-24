"""
sandbox_policy: what a project's sandbox may reach and which services it may sign in to.

Shared by every sandbox backend (the dev container in ai-devcontainer.py today; Enclave later).
It reads three layers, later ones winning:

  1. the active ai-config profile (global-skills/noslop/scripts/profile.sh), whose
     devcontainer_* keys set defaults for every project in that context;
  2. the project's ai-config.conf [sandbox] section;
  3. integrations: one file per service (Plausible, Cloudflare, Mailtrap, ...), built in under
     devcontainer-kit/integrations/ or private under ~/.config/ai-config/devcontainer/integrations/
     (a private file wins on a name clash).

Nothing here names an organization: domains and hosts come from the profile and the project.
Standard library only.
"""
from __future__ import annotations

import configparser
import os
import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

KIT = Path(__file__).resolve().parent
REPO = KIT.parent
BUILTIN_INTEGRATIONS = KIT / "integrations"
PROFILE_SH = REPO / "global-skills" / "noslop" / "scripts" / "profile.sh"
AI_CONFIG_HOME = Path(os.environ.get("AI_CONFIG_HOME", Path.home() / ".config" / "ai-config"))

# Integrations every sandbox gets, whatever the profile says.
CORE_INTEGRATIONS = ("github",)
# Hosts Claude Code needs to run at all: a block of one of these is refused, not applied.
UNBLOCKABLE = ("api.anthropic.com", "claude.ai", "claude.com", "platform.claude.com", "downloads.claude.ai")

# A host name, optionally with a leading dot (= every subdomain, through the proxy). No IPs, no
# wildcards, no bare top-level domain.
DOMAIN_RE = re.compile(r"^\.?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def valid_domain(name: str) -> bool:
    return bool(DOMAIN_RE.match(name)) and len(name) <= 253


def split_list(value: str) -> list[str]:
    """'a, b c' -> ['a', 'b', 'c']; '#' or ';' starts a comment."""
    value = re.split(r"\s[#;]", " " + value, maxsplit=1)[0]
    return [v for v in re.split(r"[,\s]+", value) if v]


@dataclass
class Integration:
    name: str
    source: Path
    description: str = ""
    requires: list = field(default_factory=list)
    hosts: list = field(default_factory=list)
    credential: dict | None = None      # variable, keychain, scheme, hosts
    mount: dict | None = None           # source, target, copy, placeholder, volume
    skills: list = field(default_factory=list)
    deny: list = field(default_factory=list)
    image: list = field(default_factory=list)   # built-in Dockerfile blocks: playwright, wrangler


@dataclass
class Policy:
    profile: str                         # "" when none applies
    settings: dict
    integrations: list                   # [Integration], in a stable order
    domains: list                        # the organization's domains (leading dot = subdomains)
    hosts: list                          # exact names, for tools that ignore the proxy
    block: list
    notes: list = field(default_factory=list)   # follow-ups for a person
    info: list = field(default_factory=list)

    def has(self, name: str) -> bool:
        return any(i.name == name for i in self.integrations)

    def get(self, name: str) -> Integration | None:
        return next((i for i in self.integrations if i.name == name), None)


# ---------------------------------------------------------------- inputs

def read_profile(project: Path, name: str | None = None) -> dict:
    """The profile's key=value lines (profile=, from=, and its keys). {} when none applies."""
    if not PROFILE_SH.is_file():
        return {}
    env = dict(os.environ)
    if name:
        env["AI_CONFIG_PROFILE"] = name
    try:
        out = subprocess.run(["bash", str(PROFILE_SH)], cwd=project, env=env, capture_output=True,
                             text=True, timeout=10).stdout
    except Exception:
        return {}
    values = {}
    for line in out.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    if values.get("profile") in (None, "", "none"):
        return {}
    return values


def read_project_section(project: Path, section: str = "sandbox") -> tuple[dict, list]:
    """key = value lines under [section] in ai-config.conf. Tolerant: other sections may hold
    lines this parser doesn't understand. Returns (values, problems)."""
    conf = project / "ai-config.conf"
    values, problems, inside = {}, [], False
    if not conf.is_file():
        return values, problems
    for n, raw in enumerate(conf.read_text(errors="replace").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        m = re.match(r"^\[([^\]]+)\]$", line)
        if m:
            inside = m.group(1).strip().lower() == section
            continue
        if not inside:
            continue
        if "=" not in line:
            problems.append(f"ai-config.conf line {n}: expected key = value under [{section}]")
            continue
        k, v = line.split("=", 1)
        values[k.strip().lower()] = re.split(r"\s+[#;]", v.strip(), maxsplit=1)[0].strip()
    return values, problems


def integration_dirs() -> list[Path]:
    """Private first, so a private file of the same name wins."""
    return [AI_CONFIG_HOME / "devcontainer" / "integrations", BUILTIN_INTEGRATIONS]


def available_integrations() -> dict[str, Path]:
    found: dict[str, Path] = {}
    for d in integration_dirs():
        if d.is_dir():
            for f in sorted(d.glob("*.conf")):
                found.setdefault(f.stem, f)
    return found


def fill(text: str, settings: dict) -> tuple[str, list]:
    """'{plausible_host}' -> its value. Returns (text, missing keys)."""
    missing = []

    def sub(m):
        key = m.group(1)
        if settings.get(key):
            return settings[key]
        missing.append(key)
        return m.group(0)
    return re.sub(r"\{([a-z0-9_]+)\}", sub, text), missing


def parse_integration(name: str, path: Path, settings: dict,
                      trusted: dict | None = None) -> tuple[Integration | None, list]:
    """One integration file. Returns (integration or None, problems).

    `settings` fills [hosts]; `trusted` (the profile and derived names only, never the
    project's [sandbox] values) fills [credential] and [mount]. ai-config.conf lives in the
    project, which the sandbox can write, so it must never decide where a token is sent or
    which Mac folder is mounted."""
    trusted = settings if trusted is None else trusted
    cp = configparser.ConfigParser(allow_no_value=True, delimiters=("=",), inline_comment_prefixes=(";", "#"),
                                   interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read_string(path.read_text())
    except Exception as e:
        return None, [f"integration {name} ({path}): {e}"]
    problems: list = []
    meta = cp["integration"] if cp.has_section("integration") else {}
    it = Integration(name=name, source=path, description=(meta.get("description") or "").strip())
    it.requires = split_list(meta.get("requires") or "")
    unmet = [k for k in it.requires if not settings.get(k)]
    if unmet:
        return None, [f"integration {name} needs {', '.join(unmet)} (set it in the profile or under "
                      f"[sandbox] in ai-config.conf); left out"]

    def lines(section):
        if not cp.has_section(section):
            return []
        out = []
        for key in cp[section]:
            text, missing = fill(key.strip(), settings)
            if missing:
                problems.append(f"integration {name}: [{section}] {key} needs {', '.join(missing)}; skipped")
                continue
            out.append(text)
        return out

    it.hosts = [h.lower() for h in lines("hosts")]
    for h in it.hosts:
        if not valid_domain(h):
            problems.append(f"integration {name}: '{h}' isn't a host name; skipped")
    it.hosts = [h for h in it.hosts if valid_domain(h)]
    it.skills = [s for s in lines("skills") if NAME_RE.match(s)]
    it.deny = lines("deny")
    it.image = [s for s in lines("image") if s in ("playwright", "wrangler")]
    for section, attr in (("credential", "credential"), ("mount", "mount")):
        if cp.has_section(section):
            values, missing = {}, []
            for k, v in cp[section].items():
                text, miss = fill((v or "").strip(), trusted)
                values[k] = text
                missing += miss
            if missing:
                problems.append(f"integration {name}: [{section}] needs {', '.join(sorted(set(missing)))} from the "
                                "profile (a project's [sandbox] can't set where a token goes); left out")
                continue
            setattr(it, attr, values)
    if it.credential:
        c = it.credential
        c["hosts"] = [h.lower() for h in split_list(c.get("hosts", "")) if valid_domain(h.lower())]
        if not (re.match(r"^[A-Z][A-Z0-9_]{1,63}$", c.get("variable", "")) and NAME_RE.match(c.get("keychain", ""))
                and c.get("scheme") in ("bearer", "github", "token") and c["hosts"]):
            problems.append(f"integration {name}: [credential] needs variable (UPPER_CASE), keychain, "
                            "scheme (bearer, token or github) and hosts; left out")
            it.credential = None
    if it.mount:
        m = it.mount
        if not (m.get("source", "").startswith("~/") and m.get("target", "").startswith("~/")):
            problems.append(f"integration {name}: [mount] source and target must start with ~/; left out")
            it.mount = None
        else:
            m["copy"] = [f for f in split_list(m.get("copy", "")) if NAME_RE.match(f)]
            if m.get("placeholder") and not NAME_RE.match(m["placeholder"]):
                m["placeholder"] = ""
    return it, problems


# ---------------------------------------------------------------- resolution

def derived_settings(profile: str, values: dict) -> dict:
    """Names that follow from the profile, so one profile's tokens and volumes never mix with
    another's. With no profile: generic names."""
    cf = values.get("cloudflare") or profile
    if cf and cf != "cps" and NAME_RE.match(cf):
        cf_dir, cf_key = f"~/.config/ai-config-cloudflare/{cf}", f"cloudflare-api-{cf}"
    else:
        # cloudflare.sh keeps the cps profile (and no profile) on its original locations.
        cf_dir, cf_key = "~/.config/cps-cloudflare", "cloudflare-api"
    prefix = profile or "ai"
    return {
        "profile": profile,
        "volume_prefix": prefix,
        "github_keychain": values.get("devcontainer_github_keychain") or f"{prefix}-devcontainer-github",
        "cloudflare_dir": cf_dir,
        "cloudflare_keychain": cf_key,
    }


def resolve_names(profile_list: list[str], project_value: str | None) -> list[str]:
    """Profile list, then the project's: '+x' adds, '-x' removes, a plain list replaces."""
    names = list(profile_list)
    if project_value is None:
        return names
    items = split_list(project_value)
    if items and not any(i[0] in "+-" for i in items):
        return items
    for i in items:
        if i.startswith("-"):
            names = [n for n in names if n != i[1:]]
        elif i.startswith("+") and i[1:] not in names:
            names.append(i[1:])
    return names


def resolve(project: Path, profile_name: str | None = None, extra: list[str] | None = None) -> Policy:
    """The sandbox policy for one project. `extra`: integrations the caller detected (context7
    when .mcp.json names it)."""
    prof = read_profile(project, profile_name)
    profile = prof.get("profile", "")
    proj, problems = read_project_section(project)
    settings = {k: v for k, v in prof.items() if k not in ("from",)}
    settings.update(derived_settings(profile, prof))
    # From the Mac only: fills [credential] and [mount] (where tokens go, what's mounted).
    trusted = dict(settings)
    # Project values may fill [hosts] ({key} substitution), never the names derived from the
    # profile (Keychain items, volumes, folders).
    for k, v in proj.items():
        if k not in ("integrations", "domains", "hosts", "block") and k not in trusted:
            settings[k] = v
        elif k in trusted and k not in ("integrations", "domains", "hosts", "block") and v != trusted[k]:
            problems.append(f"[sandbox] {k} is ignored: it's a profile setting, and the project can't change it")

    notes, info = list(problems), []
    if profile:
        info.append(f"Profile: {profile} (from {prof.get('from', '?')})")
    else:
        info.append("No ai-config profile applies here: only the core integrations and the project's own "
                    "[sandbox] settings are used.")
    names = list(CORE_INTEGRATIONS)
    for n in resolve_names(split_list(prof.get("devcontainer_integrations", "")), proj.get("integrations")):
        if n not in names:
            names.append(n)
    for n in extra or []:
        if n not in names:
            names.append(n)
    available = available_integrations()
    integrations = []
    for n in names:
        if n not in available:
            notes.append(f"integration '{n}' not found (built-in: {', '.join(sorted(available))}; private ones go "
                         f"in {AI_CONFIG_HOME / 'devcontainer' / 'integrations'})")
            continue
        it, probs = parse_integration(n, available[n], settings, trusted)
        notes += probs
        if it:
            integrations.append(it)

    def domains_from(*values):
        out = []
        for v in values:
            for d in split_list(v or ""):
                d = d.lower()
                if valid_domain(d):
                    out.append(d)
                else:
                    notes.append(f"'{d}' isn't a host name; skipped")
        return list(dict.fromkeys(out))

    domains = domains_from(prof.get("devcontainer_domains"), proj.get("domains"))
    hosts = domains_from(prof.get("devcontainer_hosts"), proj.get("hosts"))
    block = domains_from(prof.get("devcontainer_block"), proj.get("block"))
    refused = [b for b in block if b.lstrip(".") in UNBLOCKABLE]
    if refused:
        notes.append(f"Not blocked (Claude Code needs them): {', '.join(refused)}")
        block = [b for b in block if b not in refused]
    return Policy(profile=profile, settings=settings, integrations=integrations, domains=domains,
                  hosts=hosts, block=block, notes=notes, info=info)


# ---------------------------------------------------------------- domains.conf

def read_domains_conf(path: Path) -> tuple[list[str], list[str]]:
    """([allow], [block]) from .devcontainer/domains.conf. Missing file: two empty lists."""
    allow, block, section = [], [], None
    if not path.is_file():
        return allow, block
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line in ("[allow]", "[block]"):
            section = line[1:-1]
            continue
        name = line.split()[0].lower()
        if valid_domain(name):
            (allow if section == "allow" else block if section == "block" else []).append(name)
    return list(dict.fromkeys(allow)), list(dict.fromkeys(block))


def safe_write(root: Path, path: Path, data: bytes, mode: int = 0o644) -> None:
    """Write `path` (under `root`) without following links. The sandbox can write the project
    folder, so a file or folder it replaced with a link must never send a write from the Mac
    somewhere else. Raises OSError when any part of the path is a link or leaves `root`."""
    root = root.resolve()
    rel = path.relative_to(root)
    cur = root
    for part in rel.parts[:-1]:
        cur = cur / part
        if cur.is_symlink():
            raise OSError(f"refusing to write through a link: {cur}")
        if not cur.exists():
            cur.mkdir(mode=0o755)
        elif not cur.is_dir():
            raise OSError(f"not a folder: {cur}")
    target = cur / rel.parts[-1]
    if target.is_symlink():
        raise OSError(f"refusing to write through a link: {target}")
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)


def blocked(name: str, block: list[str]) -> bool:
    """True when `name` is on the block list, or under a blocked '.domain'."""
    bare = name.lstrip(".")
    for b in block:
        if bare == b.lstrip(".") or (b.startswith(".") and bare.endswith(b)):
            return True
    return False
