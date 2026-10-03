#!/bin/sh
# Print the RAM tier: <12 GiB = 8gb, <24 GiB = 16gb, otherwise 32gb.
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
