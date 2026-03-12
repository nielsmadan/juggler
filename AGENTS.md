# Repository Guidelines

## Project Structure & Module Organization

`juggler/` contains the macOS app source. Key folders are `Models/`, `Managers/`, `Services/`, `Views/`, `Animation/`, and `Resources/` for bundled scripts such as hooks and terminal helpers. UI assets live in `juggler/Assets.xcassets/`. Unit tests are in `JugglerTests/`; UI and launch tests are in `JugglerUITests/`. Product, technical, and planning docs live under `docs/`. Build output is written to `build/` and should not be committed.

## Build, Test, and Development Commands

Use `just` targets for routine work:

- `just build` builds the `Juggler` Debug scheme into `build/`.
- `just test` runs the fast unit-test target only.
- `just test-ui` runs UI tests and launches the app under test.
- `just test-all` runs both unit and UI suites.
- `just lint` runs SwiftLint; `just format` runs SwiftFormat.
- `just coverage` runs unit tests with coverage and prints the summary.
- `just setup` installs the repo’s `lefthook` Git hooks.

Prefer `just build` over `just run`; manual app testing is usually done by the user in Xcode or from the built app.

## Coding Style & Naming Conventions

This is a Swift 5.9 codebase with 4-space indentation and a 120-character line target. Formatting is enforced by `.swiftformat`; linting is enforced by `.swiftlint.yml`. Follow existing Swift naming: `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and test files named after the subject, for example `SessionManagerTests.swift`. Use `@Observable` for app state and keep persistence in `@AppStorage` where applicable.

## Testing Guidelines

Add unit tests in `JugglerTests/` for business logic and service behavior; reserve `JugglerUITests/` for end-to-end UI flows. Keep tests narrowly scoped and name methods for the behavior under test. Run `just test` before pushing; run `just test-ui` when changing onboarding, settings, hotkeys, or monitor views.

## Commit & Pull Request Guidelines

Recent history uses short Conventional Commit-style subjects such as `fix: show shortcuts in lowercase` and `chore: improve docs`. Keep commit titles imperative and concise. Before pushing, expect `lefthook` to run formatters, lint, `just build-strict`, `just test`, and `just unused-check`. PRs should include a clear summary, linked issue or plan doc when relevant, and screenshots or recordings for visible UI changes.
