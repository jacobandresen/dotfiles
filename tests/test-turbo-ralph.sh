#!/bin/bash

# tests for turbo-ralph .  codesession logs are written to ~/.ralph

#clear existing logs
rm -Rf ~/.ralph

rm -Rf /tmp/ralph
mkdir -p /tmp/ralph
echo "--- test1 :"
turbo-ralph.sh --dir "/tmp/ralph/helloworld" "write helloworld"
echo "--- test2 :"
turbo-ralph.sh --dir "/tmp/ralph/fibonacci" "write the fibonacci sequence using c#"
echo "--- test3 :"
turbo-ralph.sh --dir "/tmp/ralph/line" "render a line on screen via SDL2. Use sdl2-config"
