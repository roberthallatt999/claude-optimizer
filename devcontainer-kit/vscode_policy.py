"""
vscode_policy: a project's VS Code extensions and settings for its dev container.

VS Code layers settings, later ones winning:

  1. User: the Mac's own settings.json. VS Code applies it inside every container window too, so
     personal preferences (rulers, whitespace, git safety) belong there and nowhere else.
  2. Remote: devcontainer.json customizations.vscode.settings. ai-devcontainer.py writes the
     stack's choices (formatters picked from what the repo uses, template file associations), then
     the project's [vscode] section from ai-config.conf on top.
  3. Workspace: the project's .vscode/settings.json. It wins over both, so a stale one silently
     undoes the kit's choices; workspace_overrides() lists where it does.

[vscode] in ai-config.conf (committed, so it survives a fresh clone):

    [vscode]
    extensions = +streetsidesoftware.code-spell-checker, -usernamehw.errorlens
    editor.wordWrap = "on"                   # the value is JSON; a bare word is a string
    twig: editor.formatOnSave = true         # language-specific: "[twig]": {...}

Settings that keep the container cut off from the Mac's logins and network are locked: a project
can't set them (ai-config.conf is writable on the Mac, where another tool may edit it).
Standard library only.
"""
from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

SECTION = "vscode"
EXTENSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*\.[A-Za-z0-9][A-Za-z0-9._-]*$")
KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")
LANGUAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.+-]*$")
BARE_WORD_RE = re.compile(r"^[A-Za-z0-9_./@-]+$")

# Every container needs these; a project can't remove them.
REQUIRED_EXTENSIONS = ("anthropic.claude-code",)
# Isolation settings ai-devcontainer.py sets itself, and families that could route around it
# (terminal environment and shells, proxies, remote and container behaviour, workspace trust).
LOCKED_KEYS = ("git.terminalAuthentication", "github.gitAuthentication")
LOCKED_PREFIXES = ("terminal.integrated.env.", "terminal.integrated.profiles.",
                   "terminal.integrated.defaultProfile.", "terminal.integrated.automationProfile.",
                   "terminal.integrated.shell", "http.", "remote.", "dev.containers.", "security.")


@dataclass
class VSCodeConfig:
    add: list = field(default_factory=list)          # extension IDs to add
    remove: list = field(default_factory=list)       # extension IDs to leave out
    settings: dict = field(default_factory=dict)     # {"key": value, "[lang]": {"key": value}}
    problems: list = field(default_factory=list)

    def __bool__(self) -> bool:
        return bool(self.add or self.remove or self.settings)


def is_locked(key: str) -> bool:
    return key in LOCKED_KEYS or key.startswith(LOCKED_PREFIXES)


def parse_value(raw: str) -> tuple[bool, object]:
    """JSON, with or without a trailing '# comment'; else a bare word as a string.
    (ok, value). A malformed value ('[120') is refused rather than kept as a string."""
    without_comment = re.split(r"\s+[#;]", raw, maxsplit=1)[0].strip()
    for text in (raw.strip(), without_comment):
        try:
            return True, json.loads(text)
        except ValueError:
            continue
    if BARE_WORD_RE.match(without_comment):
        return True, without_comment
    return False, None


def read_vscode(project: Path) -> VSCodeConfig:
    """The [vscode] section of ai-config.conf. Keys keep their case (VS Code's are
    case-sensitive). Never fatal: a bad line is a problem, and the rest still applies."""
    cfg = VSCodeConfig()
    conf = project / "ai-config.conf"
    if not conf.is_file():
        return cfg
    inside = False
    for n, raw in enumerate(conf.read_text(errors="replace").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        m = re.match(r"^\[([^\]]+)\]$", line)
        if m:
            inside = m.group(1).strip().lower() == SECTION
            continue
        if not inside:
            continue
        where = f"ai-config.conf line {n} [{SECTION}]"
        if "=" not in line:
            cfg.problems.append(f"{where}: expected key = value")
            continue
        key, value = (s.strip() for s in line.split("=", 1))
        if key == "extensions":
            read_extensions(value, cfg, where)
            continue
        language = None
        if ":" in key:
            language, key = (s.strip() for s in key.split(":", 1))
            if not LANGUAGE_RE.match(language):
                cfg.problems.append(f"{where}: '{language}' isn't a language ID (e.g. php, twig, markdown)")
                continue
        if not KEY_RE.match(key):
            cfg.problems.append(f"{where}: '{key}' isn't a VS Code setting name")
            continue
        if is_locked(key):
            cfg.problems.append(f"{where}: {key} is locked (it keeps the container away from the Mac's "
                                "logins and network); ignored")
            continue
        ok, parsed = parse_value(value)
        if not ok:
            cfg.problems.append(f"{where}: {key}: '{value}' isn't valid JSON (quote strings: \"on\"); ignored")
            continue
        if language:
            cfg.settings.setdefault(f"[{language}]", {})[key] = parsed
        else:
            cfg.settings[key] = parsed
    return cfg


def read_extensions(value: str, cfg: VSCodeConfig, where: str) -> None:
    """'+a, -b c': '-' leaves one out, '+' or no sign adds it. Unlike [sandbox] integrations, a
    plain list never replaces the kit's: that would drop Claude Code."""
    value = re.split(r"\s[#;]", " " + value, maxsplit=1)[0]
    for item in (v for v in re.split(r"[,\s]+", value) if v):
        sign, ext = (item[0], item[1:]) if item[0] in "+-" else ("+", item)
        if not EXTENSION_RE.match(ext):
            cfg.problems.append(f"{where}: '{ext}' isn't an extension ID (publisher.name)")
        elif sign == "-" and ext.lower() in REQUIRED_EXTENSIONS:
            cfg.problems.append(f"{where}: {ext} can't be removed: every container needs it")
        elif sign == "-":
            cfg.remove.append(ext.lower())
        else:
            cfg.add.append(ext.lower())


def apply(extensions: list, settings: dict, cfg: VSCodeConfig) -> tuple[list, dict]:
    """The kit's extensions and settings with the project's [vscode] on top. Inputs unchanged."""
    ext = [e for e in extensions if e.lower() not in cfg.remove]
    ext += [e for e in cfg.add if e not in (x.lower() for x in ext)]
    merged = {k: (dict(v) if isinstance(v, dict) else v) for k, v in settings.items()}
    for key, value in cfg.settings.items():
        if key.startswith("[") and isinstance(merged.get(key), dict):
            merged[key].update(value)
        else:
            merged[key] = value
    return list(dict.fromkeys(ext)), merged


# ---------------------------------------------------------------- .vscode/settings.json

# How the editor looks and behaves for one person, not facts about a codebase. A project's
# .vscode/settings.json that sets them overrides the developer's own choice in that project.
PERSONAL_KEYS = ("editor.rulers", "editor.wordWrap", "editor.renderWhitespace", "editor.fontSize",
                 "editor.fontFamily", "editor.lineHeight", "editor.minimap.enabled",
                 "editor.bracketPairColorization.enabled", "editor.guides.bracketPairs",
                 "editor.cursorStyle", "editor.cursorBlinking", "editor.smoothScrolling",
                 "workbench.colorTheme", "workbench.iconTheme", "window.zoomLevel",
                 "terminal.integrated.fontSize", "git.confirmSync", "git.enableSmartCommit")

def strip_jsonc(text: str) -> str:
    """JSON with comments and trailing commas -> JSON. Strings are copied untouched, so a URL's
    '//' survives."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
            i = n if i < 0 else i
        elif text.startswith("/*", i):
            i = text.find("*/", i + 2)
            i = n if i < 0 else i + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def read_jsonc(path: Path) -> dict | None:
    """A VS Code settings file, or None when it's missing or unreadable."""
    try:
        data = json.loads(strip_jsonc(path.read_text(errors="replace")))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def flatten(settings: dict) -> dict:
    """{"key": v, "[php]": {"k": v}} -> {"key": v, "[php] k": v}; objects such as
    files.associations become one entry per member, since VS Code merges them by member."""
    flat = {}
    for key, value in settings.items():
        if key.startswith("[") and isinstance(value, dict):
            for k, v in value.items():
                flat[f"{key} {k}"] = v
        elif isinstance(value, dict):
            for k, v in value.items():
                flat[f"{key} › {k}"] = v
        else:
            flat[key] = value
    return flat


def personal_settings(workspace: dict) -> list[tuple[str, object]]:
    """Personal-preference keys a workspace file sets, top-level or per language."""
    return sorted((k, v) for k, v in flatten(workspace).items() if k.split(" ")[-1] in PERSONAL_KEYS)


def workspace_overrides(workspace: dict, theirs: dict) -> list[tuple[str, object, object]]:
    """Settings .vscode/settings.json sets to something other than `theirs` (the kit's or the
    user's): [(key, workspace value, their value)], sorted by key."""
    mine, other = flatten(workspace), flatten(theirs)
    return sorted((k, mine[k], other[k]) for k in mine.keys() & other.keys() if mine[k] != other[k])
