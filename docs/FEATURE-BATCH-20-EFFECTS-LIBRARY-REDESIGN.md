# Feature Batch 20 — Effects Library Redesign

## UI changes
- Replaced the text-only effect picker with a searchable card library.
- Each effect card shows an SF Symbols icon, effect name, short description, category and availability state.
- Added horizontal category filters and a Ready filter.
- All registered effects remain discoverable; effects without a connected processor are disabled and labelled **Coming soon** rather than being presented as usable.
- Search matches effect names and their descriptions.
- Added counts for ready and upcoming effects.

## Metadata
`App/UI/EffectLibraryMetadata.swift` provides a symbol and concise description for every registered effect. Specific descriptions are supplied for common effects; a category-aware description is used as a fallback for any catalogue entry without a dedicated explanation. Icons use effect-specific SF Symbols where possible, then semantic or category symbols.

## Verification
- Swift parser check passed for the modified SwiftUI files.
- MotionCore test suite passed: 256 tests, 0 failures.
- A full iOS/Xcode build and device runtime check still need to be run by the GitHub Actions macOS workflow.
