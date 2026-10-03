#!/usr/bin/env bash
# Merge the RAM profile into Docker Desktop settings and restart if running.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PROFILE="$("$SCRIPT_DIR/detect-ram-profile.sh")"
SRC="$REPO_DIR/docker/desktop/$PROFILE.json"

if [ ! -f "$SRC" ]; then
	echo "  no macOS Docker profile at $SRC" >&2
	exit 1
fi

if [ ! -d /Applications/Docker.app ]; then
	echo "  Docker Desktop not found — skipping (make deps-docker-macos)"
	exit 0
fi

GROUP_DIR="$HOME/Library/Group Containers/group.com.docker"
# Docker Desktop >= 4.34 uses settings-store.json; older builds use settings.json.
SETTINGS=""
for candidate in "$GROUP_DIR/settings-store.json" "$GROUP_DIR/settings.json"; do
	[ -f "$candidate" ] && { SETTINGS="$candidate"; break; }
done
if [ -z "$SETTINGS" ]; then
	SETTINGS="$GROUP_DIR/settings-store.json"
	mkdir -p "$GROUP_DIR"
	echo '{}' > "$SETTINGS"
	echo "  created $SETTINGS (first run)"
fi

echo "  RAM profile: $PROFILE (from $SRC)"

WAS_RUNNING=false
if pgrep -x Docker >/dev/null 2>&1 || pgrep -f "Docker Desktop" >/dev/null 2>&1; then
	WAS_RUNNING=true
	echo "  quitting Docker Desktop before rewriting its settings..."
	osascript -e 'quit app "Docker"' >/dev/null 2>&1 || true
	for _ in $(seq 1 30); do
		pgrep -f "Docker Desktop" >/dev/null 2>&1 || break
		sleep 1
	done
fi

cp "$SETTINGS" "$SETTINGS.bak"

python3 - "$SETTINGS" "$SRC" <<'PYEOF'
import json, sys

settings_path, profile_path = sys.argv[1], sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)
with open(profile_path) as f:
    profile = json.load(f)

changed = []
for key, value in profile.items():
    if key.startswith("_"):
        continue
    if settings.get(key) != value:
        changed.append(f"     {key}: {settings.get(key)!r} -> {value!r}")
    settings[key] = value

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print("\n".join(changed) if changed else "     (already matched the profile)")
PYEOF

echo "  $SETTINGS updated (backup at $SETTINGS.bak)"

if $WAS_RUNNING; then
	open -a Docker
	echo "  Docker Desktop restarted with the $PROFILE profile"
else
	echo "  settings applied — they take effect next time Docker Desktop starts"
fi
