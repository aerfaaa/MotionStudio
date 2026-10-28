# MotionStudio build-fix report

## Compiler error identified in the supplied Xcode log

The log reports:

`App/UI/EditorScreen.swift:2:1: error: expressions are not allowed at the top level`

The offending token shown by the compiler is `Menu {`. A SwiftUI `Menu` view cannot sit at file scope; it must be part of a view's `body` or another view builder. The corrected `App/UI/EditorScreen.swift` in this package begins with imports and declares `EditorScreen: View`; it does not place `Menu {` at the top level.

## Checks run on this package

- `swift test --package-path MotionCore`: 235 tests passed on Linux.
- `python3 scripts/check_repository.py`: passed.
- `swiftc -frontend -parse` on Swift files under `App`, `MotionCore/Sources`, and `MotionCore/Tests`: passed.

These checks do not replace an Xcode iOS-device build. The latest GitHub Actions run available during preparation was cancelled before producing a new compiler diagnostic, so no claim is made that a fresh iOS build has passed.
