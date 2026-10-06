#!/usr/bin/env bash
# Link a dotfile, with an explicit policy for an existing non-symlink target.
set -euo pipefail

if [[ $# -ne 3 ]] || [[ "$1" != --skip && "$1" != --backup ]]; then
	echo "Usage: $(basename "$0") --skip|--backup SOURCE TARGET" >&2
	exit 2
fi

policy="$1"
source="$2"
target="$3"

if [[ -L "$target" ]]; then
	echo "  ✓ $target already symlinked"
	exit 0
fi

if [[ -e "$target" ]]; then
	if [[ "$policy" == --skip ]]; then
		echo "  ⚠ $target exists and is not a symlink — skipping"
		exit 0
	fi
	mv "$target" "$target.bak"
	echo "  ✓ backed up $target -> $target.bak"
fi

mkdir -p "$(dirname "$target")"
ln -s "$source" "$target"
echo "  ✓ $target -> $source"
