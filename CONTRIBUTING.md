# Contributing

tyler is alpha software maintained by one person in their spare time. Bug reports are very
welcome; for anything bigger than a small fix, open an issue first so we can agree on the approach.

## Reporting a bug

Open an issue with:

- your macOS version and Mac (Apple silicon or Intel)
- your displays and how they are arranged, and where the Dock is
- the output of `tyler status` and `tyler window list`
- the end of `~/.tyler/tyler.log`, and anything from
  `log show --last 5m --predicate 'subsystem == "tyler"'`
- what you did, what you expected, and what happened instead

## Building and testing

You need the Xcode Command Line Tools (Swift 6). Full Xcode isn't needed.

```bash
make build     # debug build in .build/debug
make test      # the unit tests (use this, not plain `swift test`)
make lint      # swift format and SwiftLint
make check     # lint and test, as the pre-commit hook does
```

Run your build with `.build/debug/tyler start` (or `tyler restart` if one is running). The
pre-commit hook (`.pre-commit-config.yaml`, installed with `pre-commit install`) runs `make check`
on every commit that touches Swift files. SwiftLint needs
`TOOLCHAIN_DIR=/Library/Developer/CommandLineTools` without full Xcode; the Makefile sets it.

## How tyler is written

tyler is developed almost entirely with [Claude Code](https://claude.com/claude-code). The
instructions it works by are in [`CLAUDE.md`](CLAUDE.md) and
[`devdocs/coding-guidelines.md`](devdocs/coding-guidelines.md); they apply to human contributions
too. In short:

- Logic lives in libraries and is unit tested with Swift Testing; everything that touches macOS
  sits behind a protocol so tests use fakes. The executables stay thin.
- One small, self-contained change per commit, with tests, and the docs updated in the same commit.
- Every change reaches `main` through a pull request that the maintainer reviews and merges. Its
  description explains the problem (for a fix, the cause and how it was confirmed), where the
  change sits in the design and why, the tests, and what was checked on real windows.
- `devdocs/design.md` explains the design decisions, `devdocs/macos-behaviour.md` what macOS was
  measured to do, and `devdocs/testing.md` the checks against real windows.
