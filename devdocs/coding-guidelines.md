# Swift Coding Guidelines for Agents

Follow these rules for every change in this repository. If a rule conflicts with existing code, match the surrounding code and point out the conflict in your summary.

## 1. Workflow
1. Read the related code and tests before editing.
2. Keep changes small and focused. Don't refactor or reformat code unless the task asks for it.
3. Before you finish, run all of these and make sure they pass:
   ```bash
   swift build
   swift test
   swift format lint --recursive --strict Sources Tests
   swiftlint --strict
   ```
4. Never commit generated files, secrets or changes to `Package.resolved` unless asked.
5. In your summary, list what changed, why it changed, and anything you couldn't verify.

## 2. Language & Toolchain
- Swift 6 language mode with **strict concurrency** turned on. Don't lower it.
- Use Swift Package Manager only. Don't add CocoaPods or Carthage.
- Ask before adding a dependency. Prefer Apple or swiftlang packages, or the standard library.

## 3. Types & Design
- Default to `struct` and `enum`. Use `class` only when you need identity or shared mutable state, and mark it `final`.
- Default to `let`. Use `var` only when the value must change.
- Use enums with associated values to model state. Impossible states should be impossible to write.
- Use the narrowest access level that works (`private` → `internal` → `package`). Nothing in tyler is a published API, so a declaration other targets use is `package`, never `public` (SwiftLint rejects `public`).
- Introduce a protocol only when there are two real implementations or it's needed as a test seam.
- Keep each type focused. Put protocol conformances in separate `extension`s.
- One type per file, named after it; a feature's extension goes in `Type+Feature.swift`. A private helper type is nested in the type that uses it, not left at the top of its file. SwiftLint checks both.

## 4. Optionals & Errors
- Don't force-unwrap (`!`) or force-try (`try!`) outside of tests.
- Use `guard let` for early exits.
- Throw errors from domain-specific `Error` enums. Use typed throws (`throws(MyError)`) when the error domain is closed.
- Never silently swallow errors (`try?` without handling). Log the error or pass it up.

## 5. Concurrency
- Use `async`/`await` and structured concurrency (`async let`, `TaskGroup`). Don't use new GCD or completion-handler APIs.
- Protect shared mutable state with `actor`. Mark UI code `@MainActor`.
- New types crossing concurrency boundaries must be `Sendable`.
- `@unchecked Sendable` and `nonisolated(unsafe)` are only allowed with a comment that explains why they're safe.
- Avoid detached or unstructured `Task {}`. If you must use one, keep a reference to it and handle cancellation.
- **Deliberate GCD exception.** GCD is allowed in exactly three places: `IPCServer` (an accept thread and a worker queue doing blocking POSIX socket I/O, which doesn't belong on the cooperative pool), `tylerd/main.swift` (signal sources) and `AppWriteQueue` (a serial queue per app for window moves: an Accessibility call blocks until the app answers, so it doesn't belong on the cooperative pool either, and on the main thread one slow app holds up every other window and the input taps). `IPCServer` bridges into async code once, in `runBlocking`. All window state lives on the `@MainActor` `WindowManager`. Don't use GCD anywhere else without asking.

## 6. Memory
- Use `[weak self]` in escaping closures that self stores. Don't add it to non-escaping closures.
- Don't create retain cycles between delegates. Delegate properties are `weak`.

## 7. Naming & Style
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Names should read clearly at the call site: types are `UpperCamelCase`, everything else is `lowerCamelCase`.
- Booleans read as assertions: `isEnabled`, `hasContent`.
- No abbreviations except widely known ones (`URL`, `ID`).
- `swift format` has the final say on layout. Don't hand-format against it.
- **Comments earn their place.** Write one only for what the code can't show: a reason, a
  measured macOS behaviour, a constraint or an edge case that isn't visible. Before writing one,
  look for a name (of a variable, function or type) that makes it redundant, and rename instead.
  No comments that restate the code or the signature. That includes `///` on `package`
  declarations: `package` means visible to the package's other targets, not a published API.
- Much of the existing code has explanatory comments. Don't match that density: when you change
  code, remove the comments on it that the code already says.

## 8. Testing
- New tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`). Use XCTest only for UI and performance tests.
- Every bug fix includes a regression test. Every new feature includes tests for success and failure paths.
- Use parameterized tests (`@Test(arguments:)`) instead of copied test cases.
- Use hand-written fakes that conform to protocols. Don't add mocking frameworks.
- A test file mirrors the type it tests: `Tests/<Target>Tests/<path>/<Type>Tests.swift` or `<Type>Tests+<Aspect>.swift`, with its suite named after the file (`TallLayoutResizeTests`). `devtools/check-test-paths` checks it.
- Tests must be deterministic: no real network, no sleeps, and inject clocks and dates.

## 9. Logging
- Log through `TylerLog(category:)` (`ax`, `manager`, `pointer`, `ipc`, `indicator`), never `print`, `NSLog` or `Logger` directly. Lines at or above `log.level` reach `~/.tyler/tyler.log`, so they are read by people and agents with `tail` and `grep`.
- Write each line loosely as **`<entity> <action> [started|stopped|failed|skipped] - <subject> - <details>`**: `window focusing - #7349 (Firefox)`, `window dragging started - #8000 (Ghostty) - on display 1`, `app observing failed - Obsidian (pid 22548) - attempt 2: …`. The entity first (`window`, `app`, `notification`, `modifier press`, `pointer rest`, `config`), lower case, then what happened to it. Leave out parts that say nothing.
- Name a window with `named(_:)` (`WindowInfo.logName`): `#<id> (<app>)`. It reads what tylerd already holds, so it costs a dictionary lookup.
- Never log a window's title or other content of the user's: a title holds the page, document or chat in it. The window number and app name say which window it was; `tyler window list` maps a number to its title while the window is open.
- Pick the level for who needs the line: `error` something failed; `warning` a user should know (a refused tap, an app given up on, a dropped minimize); `info` each decision (a focus, a grab, a press passed on); `debug` each step (a pointer rest, an AX call). Lines repeated many times a second go to `debug`.
- Log a failure where it is swallowed: a `guard … else { return }` that drops an event or an update gets a line, so the log explains what tylerd ignored.
- A message is an `@autoclosure`, built only when written: put the work in the message, not before the call.

## 10. Don'ts
- Don't disable lint rules or concurrency checks to get the build to pass.
- Don't use `print` in production code. Use `Logger` (OSLog) or swift-log.
- Don't leave `TODO`s without context. Don't leave commented-out code.
- Don't change the signatures other targets use unless the task asks for it.

