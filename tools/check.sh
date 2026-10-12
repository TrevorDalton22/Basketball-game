#!/usr/bin/env bash
# Type-check every script against Roblox's API definitions with luau-lsp.
# Usage: LUAU_LSP=/path/to/luau-lsp ROBLOX_TYPES=/path/to/globalTypes.d.luau tools/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tools/build.py sourcemap >/dev/null
"${LUAU_LSP:-luau-lsp}" analyze --platform=roblox --sourcemap=sourcemap.json \
  --definitions="${ROBLOX_TYPES:-globalTypes.d.luau}" src
