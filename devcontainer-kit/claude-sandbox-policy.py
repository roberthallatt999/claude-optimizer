#!/usr/bin/env python3
"""
claude-sandbox-policy: the sandbox policy (sandbox_policy.py) as Claude Code's own sandbox.

Claude Code can run its Bash commands in an OS sandbox (Seatbelt on macOS, bubblewrap on
Linux) with a network allowlist enforced by its own proxy. No Docker, no container: the
lightest of the three sandboxes. This writes the "sandbox" block of the project's
.claude/settings.local.json (docs: https://code.claude.com/docs/en/sandboxing):

  enabled                    true
  failIfUnavailable          true: refuse to run unsandboxed when the sandbox can't start
  allowUnsandboxedCommands   false: no dangerouslyDisableSandbox retry outside it
  network.allowedDomains     the hosts the dev container would allow (".example.org" becomes
                             "*.example.org" plus "example.org")
  network.deniedDomains      the blocks

Only Bash is sandboxed: Read/Edit/Write, WebFetch, MCP servers and hooks are not, so the
safety guard and permission rules stay the main control for those. Tokens aren't injected
(there's no egress proxy of ours); commands that need one use your normal login.

Keys you set yourself inside "sandbox" are kept. The record of what this tool wrote lives
outside the project (~/.cache/ai-devcontainer/claude-sandbox/<key>.json: sandboxed commands can
write the project folder, and a record there could be edited to drop one of your own
deniedDomains); a refresh that would add hosts lists them and asks. A marker in
.claude/ai-config/claude-sandbox.json only keeps the choice sticky.

Usage:
  claude-sandbox-policy.py --project DIR            show what would be written (dry run)
  claude-sandbox-policy.py --project DIR --write    write it
  claude-sandbox-policy.py ... --profile NAME --yes
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent
sys.path.insert(0, str(KIT))
import sandbox_policy  # noqa: E402

MARKER = Path(".claude") / "ai-config" / "claude-sandbox.json"   # stickiness only, never read for data
SETTINGS = Path(".claude") / "settings.local.json"
RECORDS = Path.home() / ".cache" / "ai-devcontainer" / "claude-sandbox"


def load_generator():
    spec = importlib.util.spec_from_file_location("ai_devcontainer", KIT / "ai-devcontainer.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ai_devcontainer"] = mod
    spec.loader.exec_module(mod)
    return mod


def claude_domains(hosts: list[str]) -> list[str]:
    """Allowlist names in Claude Code's syntax: a leading "*." covers subdomains only, so a
    ".example.org" entry becomes both "*.example.org" and "example.org"."""
    out: list[str] = []
    for h in hosts:
        if h.startswith("."):
            out += [f"*{h}", h[1:]]
        else:
            out.append(h)
    return list(dict.fromkeys(out))


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", type=Path, required=True)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--profile")
    ap.add_argument("--yes", action="store_true", help="add new hosts without asking (they're still listed)")
    a = ap.parse_args()
    project = a.project.resolve()
    if a.profile and not sandbox_policy.NAME_RE.match(a.profile):
        ap.error("--profile: letters, digits, dot, dash or underscore")

    gen = load_generator()
    gen.PROFILE_OVERRIDE = a.profile
    p = gen.detect(project)
    pol = p.policy
    block = pol.block if pol else []
    hosts = []
    for _title, group in gen.allowed_groups(p):
        hosts += [h for h in group if not sandbox_policy.blocked(h, block)]
    allowed = claude_domains(list(dict.fromkeys(hosts)))
    denied = claude_domains(block)

    settings_path = project / SETTINGS
    record_path = RECORDS / f"{p.key}.json"
    prev = read_json(record_path)
    if prev and prev.get("project") != str(project):
        prev = {}
    added = [h for h in allowed if prev and h not in set(prev.get("allowedDomains", []))]

    print(f"Claude Code sandbox ({project})")
    for line in (pol.info if pol else []):
        print(f"  + {line}")
    if pol and pol.integrations:
        print("  + Integrations: " + ", ".join(i.name for i in pol.integrations))
    print(f"  + {len(allowed)} allowed host name(s), {len(denied)} denied")
    for n in p.notes:
        print(f"  ! {n}")
    creds = [i.name for i in (pol.integrations if pol else []) if i.credential]
    if creds:
        print("  ! No token injection in Claude Code's sandbox (" + ", ".join(creds) + "): commands use your "
              "own login. Use the dev container to keep tokens out of reach.")
    if added:
        print("  ! New hosts since the last run:")
        for h in added:
            print(f"      + {h}")
        ok = a.yes or (a.write and sys.stdin.isatty()
                       and input("    Allow them? [y/N] ").strip().lower() in ("y", "yes"))
        if not ok:
            allowed = [h for h in allowed if h not in set(added)]
            print("    Left out: rerun on a terminal to confirm, or with --yes.")
    if not a.write:
        print(f"\nDry run. Would update the \"sandbox\" block of {settings_path}; add --write.")
        return 0

    settings = read_json(settings_path)
    sb = dict(settings.get("sandbox") or {})
    net = dict(sb.get("network") or {})
    # Keep entries the developer added; replace only what this tool wrote last time.
    prev_allow, prev_deny = set(prev.get("allowedDomains", [])), set(prev.get("deniedDomains", []))
    net["allowedDomains"] = list(dict.fromkeys([d for d in net.get("allowedDomains", []) if d not in prev_allow]
                                              + allowed))
    net["deniedDomains"] = list(dict.fromkeys([d for d in net.get("deniedDomains", []) if d not in prev_deny]
                                             + denied))
    sb.update({"enabled": True, "failIfUnavailable": True, "allowUnsandboxedCommands": False, "network": net})
    settings["sandbox"] = sb
    text = json.dumps(settings, indent=2) + "\n"
    try:
        sandbox_policy.safe_write(project, settings_path, text.encode())
        sandbox_policy.safe_write(project, project / MARKER, (json.dumps(
            {"sandbox": "claude", "note": "marker only; the record is outside the project"}, indent=2) + "\n").encode())
        RECORDS.mkdir(parents=True, exist_ok=True)
        record_path.write_text(json.dumps({"written_by": "claude-sandbox-policy", "project": str(project),
                                           "allowedDomains": allowed, "deniedDomains": denied}, indent=2) + "\n")
    except OSError as e:
        print(f"  ✗ Not written: {e}")
        return 1
    print(f"  -> updated {SETTINGS}. Check with /sandbox in Claude Code (Linux needs bubblewrap and socat).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
