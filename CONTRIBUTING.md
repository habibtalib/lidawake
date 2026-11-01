# Contributing

Issues and pull requests are welcome.

## Develop

```bash
swift build
swift test
swift run LidAwakeApp          # run the menu bar app unbundled (fine for UI work)
Scripts/bundle-app.sh          # build a real .app into ./build
```

## Guidelines

- Keep the project dependency-free. It uses only Apple frameworks.
- Logic shared by the CLI, the MCP server, the app and the widget goes in `Sources/LidAwakeCore`, with tests in `Tests/LidAwakeCoreTests`.
- The only command ever run as root is `/usr/bin/pmset -a disablesleep 1|0`. Do not widen the sudoers rule. Any change to `SudoersRule.swift` or `PowerState.swift` must say so in the PR.
- Run `swift build` and `swift test` before opening a PR. CI runs both on macOS 15 (the app supports macOS 14+).
