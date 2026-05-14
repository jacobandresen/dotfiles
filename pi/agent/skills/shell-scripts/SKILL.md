---
name: shell-scripts
description: Write, test, and debug shell scripts (bash/zsh). Use when creating automation scripts, writing utility tools, or debugging failing scripts. Covers argument handling, error checking, portability, and testing patterns.
---

# Shell Scripts

## Starting a Script

Always begin with a shebang and set safe defaults:

```bash
#!/usr/bin/env bash
set -euo pipefail
```

- `set -e`: exit on error
- `set -u`: error on undefined variables
- `set -o pipefail`: catch failures in pipes

For zsh scripts (`.zsh` or when zsh features are needed), use `#!/usr/bin/env zsh`.

## Argument Handling

```bash
usage() {
  echo "Usage: $(basename "$0") [options] <input>"
  echo "  -o <file>   Output file (default: stdout)"
  echo "  -v          Verbose"
  exit 1
}

verbose=0
output=""

while getopts "o:vh" opt; do
  case $opt in
    o) output="$OPTARG" ;;
    v) verbose=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ $# -lt 1 ]] && { echo "Error: missing input" >&2; usage; }
input="$1"
```

## Error Messages and Exit Codes

```bash
die() { echo "Error: $*" >&2; exit 1; }

[[ -f "$input" ]] || die "file not found: $input"
```

## Common Patterns

**Temp files** (cleaned up on exit):
```bash
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT
```

**Check for required commands**:
```bash
require() { command -v "$1" &>/dev/null || die "required: $1"; }
require jq
require rg
```

**Capture command output safely**:
```bash
output=$(some_command 2>&1) || die "some_command failed: $output"
```

**Process files line by line**:
```bash
while IFS= read -r line; do
  echo "processing: $line"
done < "$input"
```

## Testing a Script

Syntax check (no execution):
```bash
bash -n script.sh
```

Trace execution:
```bash
bash -x script.sh args...
```

Test with controlled input:
```bash
echo "test input" | ./script.sh -
```

Verify exit codes:
```bash
./script.sh && echo "ok" || echo "failed: $?"
```

## Portability Notes

- Prefer `#!/usr/bin/env bash` over `#!/bin/bash` (macOS has bash 3.2 at `/bin/bash`)
- On macOS, `date`, `sed`, `grep` differ from GNU versions — use `gdate`, `gsed`, `ggrep` from Homebrew when GNU behavior is needed
- `fd` and `rg` are available via `~/.pi/agent/bin/` when running inside pi
