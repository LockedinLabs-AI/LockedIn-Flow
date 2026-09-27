# Desktop security and deployment boundary

Report vulnerabilities through the project's [security policy](../SECURITY.md),
without attaching recordings, patient data, names from a real directory, or
device logs containing private paths. Tests use synthetic speech and terminology.

## Data handling

The app processes speech with a bundled local model. It has no runtime model
downloader, external inference client, telemetry adapter, updater, account, or
inbound listener. Source checks enforce this boundary; deployed-device traffic
tests remain part of release acceptance. Operating-system services, WebView2 or
WebKit, crash reporting, clipboard managers, and the destination app are separate
components and must be covered by enterprise endpoint policy.

Recordings, transcripts, and session vocabulary are not intentionally persisted
by the application. Owned sensitive buffers are cleared on drop where supported.
This is not a guarantee of forensic erasure: the native inference library,
renderer, OS swap, process dumps, and clipboard may hold copies. Use full-disk
encryption, appropriate dump policies, screen-lock controls, and an approved
clipboard/destination configuration. Clearing the transcript does not erase a
previously copied clipboard item. The app never reads existing clipboard data.

The review-before-copy workflow is intentional. No focused-field detection is
needed to start a recording, so the Mac product's historical target-field error
cannot block this path. The app does not inspect passwords in other windows or
send keystrokes to them. Copy only into an approved destination; a cloud coding
agent can transmit pasted text even though recognition was local.

## Threats and controls

| Threat | Implemented control | Remaining boundary |
| --- | --- | --- |
| Substituted speech model | Pinned digest and size; verify exact decoder input | Endpoint administrator or compromised executable can replace controls |
| Renderer compromise | Local-only resources, strict content policy, three narrow commands | Framework and OS webview require ongoing patching |
| Unbounded capture or transcript | Five-minute audio cap, validated formats, transcript and vocabulary limits | CPU/memory vary by device; no hard real-time guarantee |
| Lost or duplicated result after retry | Single owner, generation checks, original audio retained on conversion or recognition failure | Process crash or OS shutdown can still lose in-memory audio |
| Data in diagnostics | Fixed application errors; no transcript logging; inference print hooks disabled | Third-party/native crash handling must be validated on the endpoint |
| Unauthorized device control | Microphone plus explicit clipboard write only | OS microphone access is still required and must be explained |
| Supply-chain compromise | Locked dependencies, source comparison, model digest, advisories, notices and SBOM | Signing and artifact provenance are required before public binary release |

This design supports evaluation in controlled healthcare workflows; it does not
establish HIPAA compliance, a certification, or a guarantee of no vulnerabilities.
No PHI is needed for build tests or acceptance. Broader organizational controls
and the chosen destination remain part of an enterprise deployment decision.

## Dependency findings

The GTK3 stack currently selects GLib's Rust 0.18 API. The source includes the
exact upstream two-line fix for **RUSTSEC-2024-0429**, with a checksum-pinned
source comparison and optimized Linux regression. See the
[backport provenance](vendor/glib/LOCKEDIN-PATCH.md). A path dependency may not
be assessed by a version-only advisory scanner, so both checks are mandatory;
an empty scanner report alone does not validate the backport.

**RUSTSEC-2024-0370:** `proc-macro-error` 1.0.4 is unmaintained and enters through
the GTK3 build-time macro stack. It is not a speech network service, but this
maintenance finding remains open. Reassess before each release and remove the
dependency when the framework supports a maintained replacement. It is not
silenced in the advisory command. Unknown unsoundness and vulnerability findings
fail the build.

The generated CycloneDX inventory describes Cargo's target/build graph, model
digest, source revision/state, lockfile hashes, and Rust version. It is not a
complete inventory of the host OS. License notices include published dependency
license files, with separate model and native speech-backend attribution.
Release review must close missing notices and inventory native/system libraries
and the bundled WebView2 installer separately.

## Coexistence and support

This port opens the default input device only during a requested recording.
It does not install an audio driver or intercept global keys. That reduces
conflict opportunities; it does not prove compatibility with every driver,
exclusive-mode client, conferencing app, or desktop session. Do not advertise
Windows 10, ARM devices, arbitrary Linux distributions, or Intel Macs as tested
without platform-specific evidence.
