#!/bin/sh
# Detects total system RAM and prints an Ollama override profile name
# ("16gb" or "32gb") for scripts/Makefiles to consume. Machines with
# less than ~24GB get the conservative 16gb profile; everything else
# gets the 32gb profile.

set -eu

if [ "$(uname -s)" = "Darwin" ]; then
	total_kb=$(( $(sysctl -n hw.memsize) / 1024 ))
else
	total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
fi

total_gb=$(( total_kb / 1024 / 1024 ))

if [ "$total_gb" -ge 24 ]; then
	echo "32gb"
else
	echo "16gb"
fi
