# Validation evidence

This page records what the current LockedIn Flow candidate has actually passed and
keeps source validation separate from installed-product acceptance.

## Cross-platform candidate: 27 September 2026

The repository is public source; the work below is in the review branch, not a
production download. The last fully completed baseline in this record is
`5cad8e42def1dec9333d8cd37b7193ea397502e0`:

| Evidence | Observed result | Scope |
| --- | --- | --- |
| [Mac CI](https://github.com/LockedinLabs-AI/LockedIn-Flow/actions/runs/36321325520) | Passed | Pinned-toolchain builds, source/tooling tests, publication checks, evaluation packaging; not Developer ID signing or physical microphone acceptance |
| [Native desktop CI](https://github.com/LockedinLabs-AI/LockedIn-Flow/actions/runs/36321325362) | Windows and Linux passed | Native builds and tests, synthetic offline recognition, package verification, Windows EXE/MSI and Linux DEB installation/removal checks |
| [Security](https://github.com/LockedinLabs-AI/LockedIn-Flow/actions/runs/36321325378) | Passed | Configured static-analysis and secret-scanning gates, not an independent penetration test |
| [Dependency review](https://github.com/LockedinLabs-AI/LockedIn-Flow/actions/runs/36321325495) | Passed | Dependency changes covered by the configured review, not proof of no unknown vulnerabilities |

Subsequent commits must receive their own relevant checks. The newer Windows
WebView2 prerequisite-signature verification is additional work and is **not**
covered by this baseline. Follow the exact commit's workflow checks in
[the desktop pull request](https://github.com/LockedinLabs-AI/LockedIn-Flow/pull/10).

The native Mac candidate is v0.4.17/build 19. The separate Windows/Linux port is
v0.5.0-alpha.1; its own-window record/review/Copy workflow does not yet provide
the Mac automatic-typing, shortcut, or encrypted-history feature set. A native
installer test does not establish hardware microphone, GUI, screen-reader,
meeting-app coexistence, upgrade/rollback, or enterprise fleet acceptance.

### Remaining release decisions and evidence

| Gate | What remains | Responsible role |
| --- | --- | --- |
| Source approval | Independent review of the exact naming, permission, and desktop changes; merge through the existing protections | Maintainer other than the author |
| Trusted packages | Mac Developer ID signing/notarization, Windows signing, and approved Linux distribution artifacts with exact-artifact provenance and checksums | Release maintainer with controlled signing access |
| Model distribution | Review each bundled model's redistribution terms and notices; verify offline provisioning on a clean endpoint | Model/dependency and release maintainers |
| Real-device acceptance | Complete the [compatibility matrix](compatibility.md), including the affected microphone/focus scenarios and keyboard/screen-reader use | Device testers and release maintainer |
| Privacy and performance | Observe the exact installed artifact with networking denied; measure latency, resource cost, accuracy, and terminology quality on a declared corpus | Security reviewer and pilot owner |
| Enterprise operations | Test managed installation, update, rollback, removal, retention, permissions, and endpoint policy; assign support/security-response ownership | Endpoint administrator and service owner |
| Public availability | Publish only accepted artifacts; test website/README download paths against those exact bytes and synchronize supported-platform claims | Release maintainer |

These are the remaining delivery gates, not reasons to add unrelated features.
A platform can launch once its own requirements pass; it must not inherit
another platform's acceptance. The dated local evidence below remains useful
history, not the latest test count or coverage for every later commit.

## Current review candidate

The v0.4.17/build 19 source candidate completed the local checks below on
26 September 2026. The [CI workflow](../.github/workflows/ci.yml) and
[security workflow](../.github/workflows/security.yml) record hosted results
against each tested revision. A later commit must run the relevant checks again.

| Gate | Result |
| --- | --- |
| Swift tests | 538 passed, 0 failed, including content-free logging regressions |
| npm tooling tests | 46 passed, including provisioning, macOS ACL cases, history privacy, clipboard and logging policies, advisory-service failures, and analysis-result gating |
| Formatting | Strict `swift-format` lint passed |
| Builds | Debug and release builds passed with the pinned toolchain |
| Binary diagnostic | Production-binary diagnostic passed |
| SBOM | 12 generation and validation tests passed, including document identity required by attestation |
| Binary policy | 41 checks passed |
| Runtime network source policy | Passed |
| Dependency advisories | OSV returned no matching advisories for the exact FluidAudio and vendored KeyboardShortcuts revisions on 26 September 2026; see the limited coverage in [Third-party risk](third-party-risk.md) |
| Publication content | Candidate-tree checks pass; full reachable-history review is required on the final publication repository |
| Secret scan | TruffleHog is required with verified, unknown, and unverified results enabled; consult the exact revision's Security check |
| Evaluation packaging | CI builds and verifies an ad-hoc app and unsigned, no-script PKG; consult the exact revision's build check |

CodeQL, dependency review, and public artifact attestation must have recorded
results on the published repository before the first binary release. A skipped
job is not passing evidence. The latest CI run identifies which checks ran for
each candidate.

The pinned source-evaluation toolchain is Xcode 26.6 build 17F113, Apple Swift
6.3.3, and the macOS 26.5 SDK. The package records the source revision,
dependency-lock hash, SBOM hash, and model-manifest hashes in its build
provenance. The approved public tree must be built and accepted as its own
artifact before release.

## Additional first-use and recovery checks

The least-privilege first-dictation candidate completed additional local checks on
27 September 2026:

- All 548 Swift tests passed, including delivery-mode and permission-identity
  regressions plus two added recovery stress tests.
  The new tests exercise 200 route-change cycles and 100 stop/cancel-during-retry
  cycles using the production capture manager with synthetic engine callbacks.
  They do not substitute for physical-device interruption testing.
- All 54 npm tooling tests passed, including first-use permission, model-setup,
  and no-implicit-recording policies.
- Five synthetic speech recordings passed a local-recognizer smoke test with
  process networking denied. Every normalized word matched; punctuation varied.
  This is not an accuracy benchmark, microphone test, or whole-device traffic
  assessment.
- Native checks of the packaged application verified Microphone-only first-use
  guidance, automatic typing off by default, a correctly branded explanation
  before the optional Accessibility request, and cancellation that leaves
  automatic typing disabled without raising an OS permission request.
  No Microphone or Accessibility permission was granted during these checks.
- The packaged application opened and loaded the provisioned Parakeet model.
  Real-microphone capture and cross-application insertion acceptance remain
  outstanding. Prior compact-layout and window-lifecycle checks used synthetic
  application state; they are not microphone evidence.
- Evaluation app packaging, strict bundle-signature verification, SBOM validation,
  and unsigned, no-script installer packaging passed. These are local evaluation
  artifacts, not Developer ID signed or notarized releases.

Public workflow results must cover the exact proposed commit before merge;
earlier CI results do not cover these later changes.

## What this does not prove

The evidence above does not prove that the candidate is ready for general
availability. It has not yet completed:

- Developer ID Application and Installer signing, notarization, and stapling;
- repeated installed record-to-exactly-once acceptance across the published
  target-application matrix;
- affected-hardware microphone route, interruption, and recovery testing;
- managed install, upgrade, rollback, removal, and permission remediation;
- blocked-network packet-capture validation of the exact release artifact;
- representative CPU, memory, battery, thermal, and latency measurement; or
- independent security assessment and model-redistribution approval.

Until those gates pass, describe the project as a source release candidate or
managed-Mac pilot candidate—not an enterprise-ready production release.

## Evidence rules

Release evidence must identify the exact source revision and artifact. A later
commit, rebuilt binary, different model tree, or changed signing identity is a
new candidate and cannot inherit an earlier result. Rejected candidates remain
rejected; their version/build identifiers are never reused for different bytes.

See [Compatibility](compatibility.md), [Enterprise evaluation](enterprise-evaluation.md),
and [Release process](release-process.md) for the remaining matrix and promotion
path.
