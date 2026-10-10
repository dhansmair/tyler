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
- Use the narrowest access level that works (`private` → `internal` → `package` → `public`).
- Introduce a protocol only when there are two real implementations or it's needed as a test seam.
- Keep each type focused. Put protocol conformances in separate `extension`s.

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
- **Deliberate GCD exception (decided in M2).** GCD is allowed in exactly two places: `IPCServer` (an accept thread and a worker queue doing blocking POSIX socket I/O, which doesn't belong on the cooperative pool) and `tylerd/main.swift` (signal sources). `IPCServer` bridges into async code once, in `runBlocking`. All window state lives on the `@MainActor` `WindowManager`. Don't use GCD anywhere else without asking.

## 6. Memory
- Use `[weak self]` in escaping closures that self stores. Don't add it to non-escaping closures.
- Don't create retain cycles between delegates. Delegate properties are `weak`.

## 7. Naming & Style
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Names should read clearly at the call site: types are `UpperCamelCase`, everything else is `lowerCamelCase`.
- Booleans read as assertions: `isEnabled`, `hasContent`.
- No abbreviations except widely known ones (`URL`, `ID`).
- `swift format` and SwiftLint have the final say on formatting. Don't hand-format against them.
- Public APIs get `///` doc comments. Other comments explain *why*, not *what*.

## 8. Testing
- New tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`). Use XCTest only for UI and performance tests.
- Every bug fix includes a regression test. Every new feature includes tests for success and failure paths.
- Use parameterized tests (`@Test(arguments:)`) instead of copied test cases.
- Use hand-written fakes that conform to protocols. Don't add mocking frameworks.
- Tests must be deterministic: no real network, no sleeps, and inject clocks and dates.

## 9. Don'ts
- Don't disable lint rules or concurrency checks to get the build to pass.
- Don't use `print` in production code. Use `Logger` (OSLog) or swift-log.
- Don't leave `TODO`s without context. Don't leave commented-out code.
- Don't change public API signatures unless the task asks for it.

