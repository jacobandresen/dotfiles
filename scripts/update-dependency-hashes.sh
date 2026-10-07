#!/usr/bin/env bash
set -euo pipefail

file=${1:-scripts/dotfiles.py}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
declare -a report=()
log() { printf '[deps] %s\n' "$*"; }

case "$(uname -s)" in
  Darwin) host_platform="macOS" ;;
  Linux) host_platform="Linux (Arch/Debian/Ubuntu)" ;;
  *) printf '%s\n' "unsupported platform: $(uname -s); Makefile supports macOS, Arch, Debian, and Ubuntu" >&2; exit 1 ;;
esac
log "host platform: $host_platform"

for command in curl jq perl sed; do
  command -v "$command" >/dev/null 2>&1 || {
    printf '%s\n' "$command is required" >&2
    exit 1
  }
done

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    printf '%s\n' "sha256sum or shasum is required" >&2
    return 1
  fi
}

run_summary() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 30 "$@"
  else
    "$@" &
    local pid=$! watchdog status
    (sleep 30; kill "$pid" 2>/dev/null) &
    watchdog=$!
    wait "$pid" 2>/dev/null
    status=$?
    kill "$watchdog" 2>/dev/null || true
    wait "$watchdog" 2>/dev/null || true
    return "$status"
  fi
}

latest() {
  log "checking latest release: $1"
  RELEASE_TAG=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/$1/releases/latest" | jq -er '.tag_name')
}
hash_asset() {
  local repo=$1 tag=$2 name=$3
  log "fetching hash for $repo/$tag/$name"
  local digest
  digest=$(curl -fsSL --connect-timeout 10 --max-time 30 \
    "https://api.github.com/repos/$repo/releases/tags/$tag" |
    jq -er --arg name "$name" '.assets[] | select(.name == $name) | .digest // empty' |
    sed 's/^sha256://') || true
  if [[ "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    log "using upstream digest for $name: $digest"
    HASH_RESULT=$digest
    return
  fi
  log "no upstream digest; downloading and hashing $name"
  curl -fsSL --connect-timeout 10 --max-time 180 \
    "https://github.com/$repo/releases/download/$tag/$name" -o "$tmp/$name"
  digest=$(sha256 "$tmp/$name")
  log "verified $name ($(du -h "$tmp/$name" | cut -f1)): $digest"
  HASH_RESULT=$digest
}
replace() {
  local key=$1 value=$2
  log "updating $key"
  perl -0pi -e "s/^$key\\s*=\\s*[^\\n]+/$key = $value/m" "$file"
}

log "updating $file"
latest earendil-works/pi; tag=$RELEASE_TAG; version=${tag#v}
hash_asset earendil-works/pi "$tag" pi-linux-x64.tar.gz; pi_x64=$HASH_RESULT
hash_asset earendil-works/pi "$tag" pi-linux-arm64.tar.gz; pi_arm=$HASH_RESULT
hash_asset earendil-works/pi "$tag" pi-darwin-x64.tar.gz; pi_mac_x64=$HASH_RESULT
hash_asset earendil-works/pi "$tag" pi-darwin-arm64.tar.gz; pi_mac_arm=$HASH_RESULT
replace PI_VERSION "\"$version\""
perl -0pi -e "s{(PI_SHA256\\s*=\\s*\\{.*?\\}\\s*OLLAMA_VERSION)}{\$_ = \$1; s/(Linux.*?\\\"x86_64\\\":\\s*\\\")[0-9a-f]+/\${1}$pi_x64/s; s/(Linux.*?\\\"arm64\\\":\\s*\\\")[0-9a-f]+/\${1}$pi_arm/s; s/(Darwin.*?\\\"x86_64\\\":\\s*\\\")[0-9a-f]+/\${1}$pi_mac_x64/s; s/(Darwin.*?\\\"arm64\\\":\\s*\\\")[0-9a-f]+/\${1}$pi_mac_arm/s; \$_ . \"OLLAMA_VERSION\"}se" "$file"
report+=("pi=$tag linux-x64=$pi_x64 linux-arm64=$pi_arm darwin-x64=$pi_mac_x64 darwin-arm64=$pi_mac_arm")

latest ollama/ollama; tag=$RELEASE_TAG
hash_asset ollama/ollama "$tag" ollama-linux-amd64.tar.zst; ollama_x64=$HASH_RESULT
hash_asset ollama/ollama "$tag" ollama-linux-arm64.tar.zst; ollama_arm=$HASH_RESULT
replace OLLAMA_VERSION "\"$tag\""
perl -0pi -e "s{(OLLAMA_SHA256\\s*=\\s*\\{.*?\\})}{\$_ = \$1; s/(\\\"x86_64\\\":\\s*\\\")[0-9a-f]+/\${1}$ollama_x64/; s/(\\\"arm64\\\":\\s*\\\")[0-9a-f]+/\${1}$ollama_arm/; \$_}se" "$file"
report+=("ollama=$tag amd64=$ollama_x64 arm64=$ollama_arm")

latest docker/compose; tag=$RELEASE_TAG
hash_asset docker/compose "$tag" docker-compose-linux-x86_64; compose_x64=$HASH_RESULT
hash_asset docker/compose "$tag" docker-compose-linux-aarch64; compose_arm=$HASH_RESULT
replace COMPOSE_VERSION "\"$tag\""
perl -0pi -e "s{(COMPOSE_SHA256\\s*=\\s*\\{.*?\\})}{\$_ = \$1; s/(\\\"x86_64\\\":\\s*\\\")[0-9a-f]+/\${1}$compose_x64/; s/(\\\"aarch64\\\":\\s*\\\")[0-9a-f]+/\${1}$compose_arm/; \$_}se" "$file"
report+=("compose=$tag x86_64=$compose_x64 aarch64=$compose_arm")

printf '%s\n' "${report[@]}" | tee "$tmp/report"
if command -v ollama >/dev/null 2>&1; then
  log "asking Ollama for a summary"
  run_summary ollama run "${OLLAMA_MODEL:-qwen3:4b}" \
    "Summarize these verified dependency updates in one concise sentence. Do not alter values:
$(cat "$tmp/report")" || printf '%s\n' "Ollama summary skipped or timed out."
else
  log "Ollama not installed; skipping summary"
fi
log "dependency update complete"
