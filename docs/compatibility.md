# Compatibility status

LockedIn Flow currently targets Apple-silicon Macs running macOS 15 or later.
Base dictation uses local Core ML speech recognition. Optional Foundation Models
cleanup, translation, and meeting notes require macOS 26 with Apple Intelligence
available and enabled.

## Current publication status

No application is listed as accepted for the v0.4.17 Community candidate yet.
The source test suite covers capture recovery, delivery-time target resolution,
secure-field refusal, at-most-once insertion policy, local storage, terminology,
cleanup, and model integrity, but source tests are not a substitute for the
installed matrix.

## Required installed matrix

Each release must publish an exact result for representative applications in
these classes:

| Class | Representative targets | Required scenarios | v0.4.17 status |
| --- | --- | --- | --- |
| Native editors | TextEdit, Notes, Mail | Empty field, selection replacement, focus change, undo | Not yet accepted |
| Browsers | Safari, Chrome | Native fields, renderer replacement, tab/window change, secure field | Not yet accepted |
| Renderer-driven AI clients | Codex, Claude Desktop | Immediate start, active renderer churn, field remount, long dictation | Not yet accepted |
| Collaboration | Outlook, Teams | Message composer, route change, interruption, recovery | Not yet accepted |
| Engineering | Xcode and a supported terminal/editor | Code profile, symbols, multiline insertion, cancellation | Not yet accepted |
| Remote or virtual workspace | Approved VDI/remote-desktop configuration | Focus, clipboard policy, latency, disconnect/reconnect | Not yet accepted |

The matrix must name the Mac model, microphone, macOS build, application
version, repetition count, successful insertions, safe refusals, duplicates,
recoverable-text events, and unresolved failures. Unknown outcomes are not
counted as success.

## Known scope

- macOS on Apple silicon is the only current product target.
- Windows and Linux are not supported Community release platforms.
- An external destination application may sync or transmit inserted text under
  its own policy; LockedIn Flow cannot change that application's boundary.
- A local transcript inserted into a cloud AI client remains local only until
  the user submits it to that provider.
- Ordinary dictation inserts into the current safe field in the destination
  application at delivery. Keep the intended editor focused until insertion
  finishes; changing fields within that application changes the destination.

See [Validation evidence](validation.md) for the hosted source-gate status and
the installed-product evidence that remains pending.
