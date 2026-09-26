---
name: verify-build
description: Compile and run code after writing or editing it, and check real output before reporting a change done. Use after any code change in a language with a build/run step (C, C++, Rust, Go, Python, JS/TS, C#, etc.).
---

# Verify Build

A change is not done until it has been built and run, and the actual output
checked. Reading the code back is not verification.

1. Find how this project builds/tests: `Makefile`, `Cargo.toml`, `go.mod`,
   `package.json` scripts, `pytest`/`*.csproj`, etc. Use that, not a guess.
2. Run it after every edit:
   - Compiled languages: build with warnings/errors visible (`-Wall` for
     C/C++, `cargo build`, `go build`, `dotnet build`).
   - Scripts: run it against real input, or run the existing test suite.
3. On any failure, fix it and re-run. Do not report success until the build
   exits 0 and the output matches what was asked for.
4. Report the command you ran and what it printed — not "this should work."
