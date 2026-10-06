#!/usr/bin/env bash
set -euo pipefail

if ! command -v dconf >/dev/null 2>&1; then
    echo "GNOME Terminal profile skipped: dconf is not installed"
    exit 0
fi

profile_id=b1f3c2a4-90d7-4e6a-a3bc-5e2f4f8a9d10
profile_path="/org/gnome/terminal/legacy/profiles:/"

dconf load "$profile_path" < "$(dirname "$0")/../gnome-terminal/retrobox.dconf"
dconf write /org/gnome/terminal/legacy/default-profile "'$profile_id'"
echo "  ✓ GNOME Terminal Retrobox profile installed and set as default"
