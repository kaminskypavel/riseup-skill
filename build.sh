#!/usr/bin/env bash
# Builds dist/riseup-skill.zip for upload to claude.ai (Settings → Capabilities → Skills). Excludes local-notes.md.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/dist"
cd "$here/skills"
rm -f "$here/dist/riseup-skill.zip"
zip -qr "$here/dist/riseup-skill.zip" riseup-skill -x 'riseup-skill/local-notes.md'
echo "Built $here/dist/riseup-skill.zip"
