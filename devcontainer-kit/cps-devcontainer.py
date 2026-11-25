#!/usr/bin/env python3
"""cps-devcontainer was renamed ai-devcontainer in kit 2.0.0. This wrapper stays for one
release so old commands and notes keep working: it says so, then runs ai-devcontainer.py
with the same arguments. Use `ai-config --devcontainer --project=<dir>` instead."""
import os
import sys
from pathlib import Path

new = Path(__file__).resolve().parent / "ai-devcontainer.py"
print("cps-devcontainer.py is now ai-devcontainer.py (and `ai-config --devcontainer`); running it.",
      file=sys.stderr)
os.execv(sys.executable, [sys.executable, str(new), *sys.argv[1:]])
