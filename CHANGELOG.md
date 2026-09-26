# Changelog

This project follows [Semantic Versioning](https://semver.org/). The first
Community source release will be tagged only after the candidate and release
evidence are approved.

## [Unreleased]

### Changed

- Licensed the Community source under the MIT License for individual and
  commercial use, modification, and distribution, subject to its terms;
  enterprise deployment and support remain optional services rather than a
  usage-license requirement.
- Established a Mac-only Community source distribution with independent runtime
  identity and fresh release history.
- Replaced broad cloud claims with an explicit model-download network boundary
  and documented that Community builds contain no updater.
- Made Community builds unlimited, with no trial, usage cap, metered billing,
  purchase flow, or activation requirement.
- Added governance, contribution, disclosure, threat-model, CI, dependency,
  secret-scanning, and CodeQL configuration.
- Isolated the Community bundle, storage, Keychain, and model cache from the
  maintained app, and removed the automatic updater dependency.
- Pinned all runtime model repositories and added exact byte-count and SHA-256
  verification before model activation.
- Made dictation History and Recovery session-only by default and prevented
  implicit clipboard export after failed Community insertions.
- Removed model acquisition from the application runtime. Models are now
  explicitly pre-provisioned, verified read-only from a managed or user cache,
  and FluidAudio is forced offline before loading.
- Added zero-dependency npm developer commands for diagnostics, recoverable
  local installation, and explicit pinned-model provisioning with transactional
  repair and interrupted-run recovery. npm installation has no lifecycle scripts.
- Hardened terminology CSV import with quoted-field and CRLF support, file and
  row limits, Unicode control rejection, application-profile scopes, conflict
  rejection for identical term/scope pairs, portable export limits, and verified
  encrypted persistence.

### Fixed

- Reworked ordinary dynamic-editor capture to verify coherent observations of
  the focused text target instead of scanning a changing full-window
  Accessibility tree.
- Added bounded retries for transient renderer remounts while continuing to
  reject secure fields, different windows, different semantic paths, and
  unresolved target churn.
- Decoupled microphone capture from the concrete Accessibility field. Ordinary
  dictation now freezes the destination application when recording ends and
  resolves the current safe text field only at delivery, so routine renderer
  remounts during recording cannot invalidate the dictation.
- Expanded callback-starvation recovery to standard microphone capture as well
  as Voice Focus, with bounded progressive restart attempts that preserve audio
  already captured.
- Made interrupted partial dictations and meetings explicit in completion state
  and saved metadata instead of presenting truncated audio as a complete capture.
- Added non-retaining secure-field probes at recording start and stop while
  keeping the final delivery boundary fail closed.

### Security

- Replaced arbitrary-string logging with a typed, content-free interface. System
  error descriptions, local paths, and destination app identifiers are no longer
  included in application diagnostics.
- Added publication checks for private files, personal context, conversation
  exports, reviewed media hashes, and local documentation links, with a full
  reachable-history mode for publication review.
- Preserved exact-control behavior for protected workflows.
- Kept diagnostics compile-time excluded from release binaries.
- Added a source policy gate that rejects application networking primitives and
  requires the speech dependency's offline mode.
