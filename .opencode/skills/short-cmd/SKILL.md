---
name: short-cmd
description: Use when the user uses shorthand commands like "bnr" (build and run standalone .app). "bnr" means build the project then update and launch the standalone .app bundle. For macOS apps, build with swift build, copy the binary into the .app bundle, then open it. For iOS apps, build and run on the simulator.
---

# short-cmd

This skill provides shorthand commands for common development tasks:

## Commands

### `bnr` — Build and Run

**macOS (standalone .app):**
1. Kill any running instance: `pkill -x <ProductName> 2>/dev/null; sleep 0.3`
2. Build: `swift build`
3. Copy the binary to the .app bundle: `cp ".build/arm64-apple-macosx/debug/<ProductName>" "<ProjectName>.app/Contents/MacOS/<ProductName>"`
4. Launch: `open "<ProjectName>.app"`

**iOS (simulator):**
Build and run on the appropriate simulator using `xcodebuild` or `swift run` depending on the project setup.

Use this whenever the user says "bnr" — interpret it as a build-and-run command.
