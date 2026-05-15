#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 0 ]]; then
  exec lua "$(cd "$(dirname "$0")" && pwd)/large_files.lua" --help
fi
exec lua "$(cd "$(dirname "$0")" && pwd)/large_files.lua" "$@"
