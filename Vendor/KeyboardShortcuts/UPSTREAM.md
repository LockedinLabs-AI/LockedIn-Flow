# KeyboardShortcuts vendoring note

This directory contains the `KeyboardShortcuts` 2.4.0 source from
<https://github.com/sindresorhus/KeyboardShortcuts> under its included MIT
license.

LockedIn Flow packages a macOS `.app` manually rather than through Xcode.
SwiftPM executable resource accessors look for dependency bundles at the app
bundle root, but macOS code signing rejects content outside `Contents/`.
The local patch loads the dependency's localization strings from
`Bundle.main`; `scripts/package-community-app.sh` copies those strings into the standard
`Contents/Resources` location. No runtime behavior is otherwise changed.
