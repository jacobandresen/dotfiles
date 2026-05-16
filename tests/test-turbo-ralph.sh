#!/bin/bash

# tests for turbo-ralph .  codesession logs are written to ~/.ralph

#clear existing logs
rm -Rf ~/.ralph

rm -Rf /tmp/ralph
mkdir -p /tmp/ralph

# Trivial (2 words, no lib): qwen2.5-coder:7b, thinking off (no thinking support).
RALPH_PLANNER_THINKING=off RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/helloworld" "write helloworld"

# Moderate (external lib SDL2 + Makefile): thinking off (qwen2.5-coder has no thinking).
RALPH_PLANNER_THINKING=off RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/line" "render a line on screen via SDL2. Use sdl2-config in the Makefile to setup SDL2 libs"

# Moderate (dotnet project structure: .csproj + Program.cs): thinking off.
RALPH_PLANNER_THINKING=off RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/fibonacci" "write the fibonacci sequence using c#. Use the dotnet command to compile c#"

# Simple (standard Python sqlite3, single file): thinking off.
RALPH_PLANNER_THINKING=off RALPH_WRITE_THINKING=off \
  turbo-ralph.sh --dir "/tmp/ralph/pythondata" "write a python program that writes a todo entry to a sqlite3 database with table that contains a list of todos. create the todo table in the sqlite3 databasea via python. Show that the inserted entry can be read again"
