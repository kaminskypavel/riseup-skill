#!/usr/bin/env bash
# Installs the riseup-skill skill as a personal Claude Code skill (~/.claude/skills/riseup-skill).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
dest="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/riseup-skill"
mkdir -p "$(dirname "$dest")"
rm -rf "$dest"
cp -R "$here/skills/riseup-skill" "$dest"
echo "Installed to $dest"
