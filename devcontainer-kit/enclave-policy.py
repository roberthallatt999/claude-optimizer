#!/usr/bin/env python3
"""
enclave-policy: the sandbox policy (sandbox_policy.py) as an Eclipse Enclave project config.

Enclave keeps a project's settings outside the worktree, so the agent can't change its own
isolation: ~/Library/Application Support/org.eclipse.enclave/config/projects/<hash>/ on macOS.
This writes, there:

  config.json                  allow_domains (the stack's, the integrations', the profile's and
                               the project's hosts, minus blocks), add_readonly_dirs (the
                               guardrail folders), features (+github-cli for the GitHub token)
  patches/claude/settings.json the safety hook and the integrations' deny rules, merged onto
                               Claude's settings in the container (Enclave's patches win conflicts)

Entries you added yourself are kept: what this tool wrote last time is recorded next to
Enclave's config (ai-config-owned.json, outside the worktree, so the agent can't change which
entries a later run removes) and only those entries are replaced. After writing, Enclave
validates the result (`enclave config --json`); an invalid file is rolled back.

Inside Enclave the project is writable (Enclave mounts folders, not single files, read-only), so
ai-config.conf could be edited from inside. A run that would add hosts to the allowlist therefore
lists them and asks first on a terminal; without a terminal it leaves them out unless --yes.
.devcontainer/domains.conf is not read here: it's the dev container's, approved through its relay.

What Enclave can't do, and this reports: a block list (a blocked host is only left off the
allowlist), tokens for services other than GitHub through its gateway, and approving a new domain
from inside (use `enclave network log --verdict deny` on the Mac, then add it under [sandbox]).

Usage:
  enclave-policy.py --project DIR            show what would be written (dry run)
  enclave-policy.py --project DIR --write    write it
  enclave-policy.py ... --profile NAME       another ai-config profile than the active one

Standard library only. Needs the enclave CLI on PATH.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

KIT = Path(__file__).resolve().parent
sys.path.insert(0, str(KIT))
import sandbox_policy  # noqa: E402

TOOL = "enclave-policy"
# In the project: only a marker that makes --sandbox=enclave sticky. Never read for data.
MARKER = Path(".claude") / "ai-config" / "enclave.json"
# Next to Enclave's project config, outside the worktree: what this tool wrote last time.
OWNED_NAME = "ai-config-owned.json"
# Guardrail folders mounted read-only (Enclave mounts folders, not single files, and already
# protects .git/config). Only those that exist.
READONLY_DIRS = (".claude/hooks", ".git/hooks", ".ddev", ".devcontainer")


def load_generator():
    """ai-devcontainer.py, for the stack detection and host groups both sandboxes share."""
    spec = importlib.util.spec_from_file_location("ai_devcontainer", KIT / "ai-devcontainer.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["ai_devcontainer"] = mod
    spec.loader.exec_module(mod)
    return mod


def enclave_info(project: Path) -> dict | None:
    """`enclave config --json` from the project: its hash, config path, validity."""
    exe = shutil.which("enclave")
    if not exe:
        return None
    try:
        out = subprocess.run([exe, "config", "--json"], cwd=project, capture_output=True, text=True,
                             timeout=30, stdin=subprocess.DEVNULL).stdout
        return json.loads(out)
    except Exception:
        return None


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def merge_list(existing, ours: list[str], previous: list[str]) -> list[str]:
    """Keep the user's entries, drop what we wrote last time, add ours. Enclave won't mix plain
    entries with +/- ones in one list: when the user's are plain, ours go in plain too."""
    existing = list(existing or [])
    prev = set(previous) | {"+" + p for p in previous}
    kept = [e for e in existing if e not in prev]
    plain = any(not str(e).startswith(("+", "-")) for e in kept) and kept != []
    mine = [o if plain else "+" + o for o in ours]
    return list(dict.fromkeys(kept + mine))


def plan(project: Path, profile: str | None) -> dict:
    gen = load_generator()
    gen.PROFILE_OVERRIDE = profile
    p = gen.detect(project)
    pol = p.policy
    block = pol.block if pol else []
    hosts = []
    for _title, group in gen.allowed_groups(p):
        for h in group:
            bare = h.lstrip(".")
            if not sandbox_policy.blocked(h, block):
                hosts.append(bare)          # Enclave entries cover the name and its subdomains
    hosts = list(dict.fromkeys(hosts))
    extra_block: list = []
    ro = [str((project / d).resolve()) for d in READONLY_DIRS if (project / d).is_dir()]
    deny = []
    for it in (pol.integrations if pol else []):
        deny += it.deny
    notes = list(p.notes)
    unsupported = [i.name for i in (pol.integrations if pol else []) if i.credential and i.name != "github"]
    if unsupported:
        notes.append("Enclave's gateway only injects the GitHub token here; these integrations' tokens are not "
                     "available inside: " + ", ".join(unsupported) + " (use the dev container for them)")
    if block or extra_block:
        notes.append("Enclave has no block list: blocked hosts are only left off the allowlist ("
                     + ", ".join(dict.fromkeys(block + extra_block)) + "); a global Enclave allow still reaches them")
    if pol and pol.has("playwright"):
        notes.append("playwright: Enclave doesn't build the kit's Playwright image layer; install it with an Enclave "
                     "feature if you need it")
    return {"project": p, "policy": pol, "hosts": hosts, "readonly": ro, "deny": list(dict.fromkeys(deny)),
            "features": ["github-cli"] if pol and pol.has("github") else [], "notes": notes}


def settings_patch(existing: dict, project: Path, deny: list[str], prev_deny: list[str]) -> dict:
    out = dict(existing)
    perms = dict(out.get("permissions") or {})
    kept = [d for d in perms.get("deny", []) if d not in set(prev_deny)]
    perms["deny"] = list(dict.fromkeys(kept + deny))
    out["permissions"] = perms
    if (project / ".claude" / "hooks" / "safety-guard.sh").exists():
        hooks = dict(out.get("hooks") or {})
        cmd = "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/safety-guard.sh"
        pre = [h for h in hooks.get("PreToolUse", [])
               if not any(x.get("command") == cmd for x in h.get("hooks", []) if isinstance(x, dict))]
        pre.append({"matcher": "Bash|Read|Edit|MultiEdit|Write|NotebookEdit|Grep|mcp__.*",
                    "hooks": [{"type": "command", "command": cmd, "timeout": 10}]})
        hooks["PreToolUse"] = pre
        out["hooks"] = hooks
    return out


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

    info = enclave_info(project)
    if info is None:
        print("Enclave isn't installed (no `enclave` on PATH), or `enclave config --json` failed; nothing written.")
        return 0
    cfg_path = Path(info["files"]["project"]["path"])
    patch_path = cfg_path.parent / "patches" / "claude" / "settings.json"
    pl = plan(project, a.profile)
    record_path = cfg_path.parent / OWNED_NAME
    prev = read_json(record_path)
    if prev and prev.get("config") != str(cfg_path):
        prev = {}
    # Hosts this run would add since the last one. ai-config.conf is writable inside Enclave, so a
    # widening is shown and confirmed before it's applied.
    added = [h for h in pl["hosts"] if prev and h not in set(prev.get("allow_domains", []))]
    if added:
        print("  ! New hosts since the last run (from the profile or ai-config.conf [sandbox]):")
        for h in added:
            print(f"      + {h}")
        ok = a.yes
        if not ok and sys.stdin.isatty() and a.write:
            ok = input("    Allow them in Enclave? [y/N] ").strip().lower() in ("y", "yes")
        if not ok:
            pl["hosts"] = [h for h in pl["hosts"] if h not in set(added)]
            print("    Left out" + ("" if a.write else " (dry run)") + ": rerun on a terminal to confirm, or with --yes.")

    cfg = read_json(cfg_path)
    new_cfg = dict(cfg)
    new_cfg["allow_domains"] = merge_list(cfg.get("allow_domains"), pl["hosts"], prev.get("allow_domains", []))
    if pl["readonly"] or prev.get("add_readonly_dirs"):
        new_cfg["add_readonly_dirs"] = merge_list(cfg.get("add_readonly_dirs"), pl["readonly"],
                                                  prev.get("add_readonly_dirs", []))
    if pl["features"] or prev.get("features"):
        new_cfg["features"] = merge_list(cfg.get("features"), pl["features"], prev.get("features", []))
    new_patch = settings_patch(read_json(patch_path), project, pl["deny"], prev.get("deny", []))

    pol = pl["policy"]
    print(f"Enclave project {info['project'].get('hash')} ({project})")
    if pol:
        for i in pol.info:
            print(f"  + {i}")
        if pol.integrations:
            print("  + Integrations: " + ", ".join(i.name for i in pol.integrations))
    print(f"  + {len(pl['hosts'])} allowed host(s), {len(pl['readonly'])} read-only guardrail folder(s)")
    for n in pl["notes"]:
        print(f"  ! {n}")
    if not a.write:
        print(f"\nDry run. Would write {cfg_path} and {patch_path}; add --write.")
        return 0

    stamp = time.strftime("%Y%m%d-%H%M%S")
    # Next to Enclave's config, outside the worktree the agent can write.
    backup = cfg_path.parent / "ai-config-backups" / stamp
    saved = {}
    for path in (cfg_path, patch_path):
        if path.exists():
            backup.mkdir(parents=True, exist_ok=True)
            dest = backup / ("config.json" if path == cfg_path else "settings.patch.json")
            shutil.copy2(path, dest)
            saved[path] = dest
    changed = []
    for path, data in ((cfg_path, new_cfg), (patch_path, new_patch)):
        text = json.dumps(data, indent=2) + "\n"
        if path.exists() and path.read_text() == text:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        changed.append(path)
    check = enclave_info(project) or {}
    if not check.get("valid", False):
        for path in changed:
            if path in saved:
                shutil.copy2(saved[path], path)
            else:
                path.unlink(missing_ok=True)
        print(f"  ✗ Enclave rejected the config ({check.get('error') or 'no answer'}); rolled back.")
        return 1
    for w in check.get("warnings") or []:
        print(f"  ! Enclave: {w.get('message', w) if isinstance(w, dict) else w}")
    try:
        sandbox_policy.safe_write(project, project / MARKER, (json.dumps(
            {"sandbox": "enclave", "written_by": TOOL,
             "note": "marker only; the record of what was written is next to Enclave's config"},
            indent=2) + "\n").encode())
    except OSError as e:
        print(f"  ! Not writing the sticky marker ({e}); pass --sandbox=enclave on later runs")
    record_path.write_text(json.dumps({
        "written_by": TOOL, "hash": info["project"].get("hash"), "config": str(cfg_path),
        "allow_domains": pl["hosts"], "add_readonly_dirs": pl["readonly"], "features": pl["features"],
        "deny": pl["deny"]}, indent=2) + "\n")
    print(f"  -> {'updated ' + ', '.join(p.name for p in changed) if changed else 'already current'}; "
          "Enclave validated it. Start with: enclave --tool claude")
    return 0


if __name__ == "__main__":
    sys.exit(main())
