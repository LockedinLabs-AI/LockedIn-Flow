# Model and dependency license inventory

This inventory records the reviewed source boundary; it is not a legal opinion.

## Runtime models

| Component | Purpose | Source | License |
| --- | --- | --- | --- |
| Parakeet TDT 0.6B v3 Core ML | default speech recognition | `FluidInference/parakeet-tdt-0.6b-v3-coreml` | CC-BY-4.0 |
| Parakeet Unified EN 0.6B Core ML | optional English recognition | `FluidInference/parakeet-unified-en-0.6b-coreml` | CC-BY-4.0 |
| Silero VAD Core ML | speech-edge detection | `FluidInference/silero-vad-coreml` | MIT |
| Apple Foundation Models | optional contextual cleanup | supplied by macOS | Apple platform terms |

Model files are not redistributed in this repository. The separate explicit
provisioning utility can retrieve them for local evaluation; the application
itself performs no acquisition. The reviewed catalog pins Parakeet TDT to
`7dd20fe6b1797d35f5e3307e8b1732d9a178edfe`, Parakeet Unified to
`4252711f6f060f9a2f91e5f081a806d7f45eebd8`, and Silero VAD to
`b419383c55c110e2c9271fa6ee0ea83d03c70d96`. The compiled manifest fixes all 39
files, byte counts, and SHA-256 hashes. Managed deployments may pre-stage those
exact artifacts, retain required attribution, and block application egress.

At the pinned Parakeet TDT revision, the repository metadata declares
CC-BY-4.0 while narrative model-card text refers to Apache-2.0. This inventory
uses the more restrictive CC-BY-4.0 designation pending clarification from the
upstream publisher. Deployers must preserve the included attribution and should
repeat license review before redistribution.

## Swift dependencies

| Package | Purpose | License |
| --- | --- | --- |
| FluidInference/FluidAudio | ASR runtime, VAD, and Apple Neural Engine integration | Apache-2.0 |
| KeyboardShortcuts | global shortcut UI and handling | MIT |

FluidAudio includes additional third-party notices in its distribution. The
packaging and SBOM scripts preserve those notices. Vendored KeyboardShortcuts
and Silero notices are tracked in this repository.
