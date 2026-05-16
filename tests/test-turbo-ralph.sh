#!/bin/bash

# tests for turbo-ralph .  codesession logs are written to ~/.ralph

#clear existing logs
rm -Rf ~/.ralph

rm -Rf /tmp/ralph
mkdir -p /tmp/ralph
turbo-ralph.sh --dir "/tmp/ralph/helloworld" "write helloworld"
turbo-ralph.sh --dir "/tmp/ralph/line" "render a line on screen via SDL2. Use sdl2-config in the Makefile to setup SDL2 libs"
turbo-ralph.sh --dir "/tmp/ralph/fibonacci" "write the fibonacci sequence using c#. Use the dotnet command to compile c#"
turbo-ralph.sh --dir "/tmp/ralph/pythondata" "write a python program that a todo  entry to a sqlite3 database with list of todos. create the todo table in the sqlite3 databasea via python. Show that the inserted entry can be read again"
