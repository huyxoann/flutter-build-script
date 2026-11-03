#!/bin/bash
set -e

# ==========================================
# Self-check for PowerShell script encoding & syntax safety
# ==========================================
# Windows PowerShell 5.1 reads UTF-8 files without BOM as Windows-1252,
# turning multi-byte UTF-8 sequences (em-dash 0x94, emojis with 0x93/0x94)
# into smart quotes (U+201C / U+201D) that break string literals at parse time.
# Keeping .ps1 files pure 7-bit ASCII guarantees compatibility across PS 5.1 & 7+.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPO_ROOT="$REPO_ROOT" python3 -c '
import os, pathlib

root = pathlib.Path(os.environ["REPO_ROOT"])
ps1_files = ["setup.ps1", "install.ps1", "scripts/build_release.ps1"]

for rel in ps1_files:
    path = root / rel
    data = path.read_bytes()
    bad = [(i + 1, line) for i, line in enumerate(data.splitlines()) if any(b > 127 for b in line)]
    assert not bad, f"{rel} contains non-ASCII bytes on lines: {[ln for ln, _ in bad]}"
    text = data.decode("ascii")
    assert text.count("{") == text.count("}"), f"{rel} has unbalanced braces"
'

echo "✅ All PowerShell scripts are pure 7-bit ASCII with balanced braces: PASS"
