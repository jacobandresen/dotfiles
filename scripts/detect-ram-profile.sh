#!/bin/sh
# Detects total system RAM and prints an override profile name
# ("8gb", "16gb" or "32gb") for scripts/Makefiles to consume.
#
#   < 12GB  -> 8gb   (very tight: base OS already eats 3-4GB)
#   < 24GB  -> 16gb
#   >= 24GB -> 32gb

set -eu

if [ "$(uname -s)" = "Darwin" ]; then
	total_kb=$(( $(sysctl -n hw.memsize) / 1024 ))
else
	total_kb=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
fi

total_gb=$(( total_kb / 1024 / 1024 ))

if [ "$total_gb" -ge 24 ]; then
	echo "32gb"
elif [ "$total_gb" -ge 12 ]; then
	echo "16gb"
else
	echo "8gb"
fi
