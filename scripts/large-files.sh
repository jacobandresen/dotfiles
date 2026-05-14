#!/usr/bin/env bash
set -euo pipefail
exec lua "$(cd "$(dirname "$0")" && pwd)/large_files.lua" "$@"
