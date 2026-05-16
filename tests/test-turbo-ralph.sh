#!/bin/bash

# tests for turbo-ralph .  codesession logs are written to ~/.ralph

#clear existing logs
rm -Rf ~/.ralph

rm -Rf /tmp/ralph
mkdir -p /tmp/ralph

# Trivial (2 words, no lib): combined plan+write, medium planner, off writer.
# qwen3:8b requires medium thinking to reliably call the Write tool in planning.
RALPH_PLANNER_THINKING=medium RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/helloworld" "write helloworld"

# Moderate (external lib SDL2 + Makefile): medium planner, low writer.
# SDL2 API calls (init/window/renderer/event loop) benefit from some write-phase reasoning.
RALPH_PLANNER_THINKING=medium RALPH_WRITE_THINKING=low \
  turbo-ralph.sh --dir "/tmp/ralph/line" "render a line on screen via SDL2. Use sdl2-config in the Makefile to setup SDL2 libs"

# Moderate (dotnet project structure: .csproj + Program.cs): medium planner, low writer.
RALPH_PLANNER_THINKING=medium RALPH_WRITE_THINKING=low \
  turbo-ralph.sh --dir "/tmp/ralph/fibonacci" "write the fibonacci sequence using c#. Use the dotnet command to compile c#"

# Simple (standard Python sqlite3, single file): medium planner, off writer.
# sqlite3 API is well-known enough that off-thinking writes it correctly.
RALPH_PLANNER_THINKING=medium RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/pythondata" "write a python program that writes a todo entry to a sqlite3 database with table that contains a list of todos. create the todo table in the sqlite3 databasea via python. Show that the inserted entry can be read again"
