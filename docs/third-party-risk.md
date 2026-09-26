# Third-party and deployment risk

## Inventory and ownership

Maintainers own source and model-manifest changes. Release maintainers own
artifact verification. The deploying organization owns endpoint policy, target
application approval, data classification, and acceptance of its intended use.

| Component or service | Trust boundary | Control | Remaining review |
| --- | --- | --- | --- |
| FluidAudio 0.15.5 | Speech runtime executing in the application process | Exact resolved commit, Apache-2.0 notices, forced offline model hub, SBOM, source and advisory checks | Embedded fastcluster and VBx lack separate upstream version identities; their provenance is bounded by the FluidAudio commit, not independent vulnerability coverage |
| KeyboardShortcuts 2.4.0 | Global keyboard handling | Vendored source, MIT notice, pinned upstream revision, reviewed localization-only patch, advisory checks | Repeat review if source or patch changes |
| Parakeet and Silero models | Model files consumed by Core ML | Immutable revisions, 39 exact file hashes and byte counts, explicit provisioning, included attribution | Model weights are not vulnerability-scanned software; packaging/redistribution requires separate license and artifact review |
| Apple frameworks and models | Operating-system services | Supported macOS requirements and device-local APIs | Organization must maintain macOS security updates and approve Apple Intelligence policy |
| GitHub and Actions | Source and build supply chain | Least-privilege jobs, immutable Action SHAs, locked dependencies, secret scanning, protected branch, artifact provenance | Hosted builds are not air-gapped; build identity is distinct from runtime data handling |
| Hugging Face | Explicit setup source only | Fixed HTTPS hosts and immutable model paths, size/hash verification, atomic activation | Availability during provisioning; enterprises can pre-stage the reviewed files offline |
| OSV | Build-time advisory database | Only public dependency commit hashes are submitted; failures block the scan | Database coverage is incomplete; no result is not proof of no vulnerability |
| Clipboard and destination apps | Text leaves this process for an approved local application | Device-local clipboard preparation, ownership verification and restoration, secure-field refusal, no automatic copy after failure | Clipboard readers can inspect local contents; destination apps can sync, upload, or retain text under their own policy |

See [model licenses](model-licenses.md), [threat model](threat-model.md), and the
[machine-readable component inventory](../security/sbom-components.json).

## Vulnerability monitoring

`npm run check:dependencies` queries OSV for the exact pinned Swift and vendored
upstream commits. CI runs this on source changes and weekly. Results identify
the time, revisions, and matching advisory IDs. Service errors, malformed
responses, incomplete pagination, and unreviewed dependencies fail closed.
This is a development/release check, never an application runtime request.

The advisory check covers the two identifiable upstream code revisions, not
model weights, OS components, unknown vulnerabilities, or independent versions
of embedded code. CodeQL, tests, manual review, and dependency change review
complement it. A discovered advisory must be assessed and resolved or documented
with a justified, scoped disposition before distributing an affected binary.

## Healthcare and other sensitive deployments

Begin a pilot with synthetic data. Before processing protected health
information (PHI) or personally identifiable information (PII), the deploying
organization must approve the workflow and complete its risk assessment. Apply
device encryption, managed user access and screen locks, supported OS patches,
controlled backups, retention policy, and an approved destination application.
Disable clipboard sync and unapproved clipboard managers through endpoint policy;
application-level device-local clipboard handling is not a substitute for that
policy. Restrict or disable optional persistent history and meeting notes when
the workflow does not require them.

HHS requires an organization-specific assessment of electronic PHI risks;
offline inference alone does not establish HIPAA compliance. This project
provides inspectable technical controls and deployment evidence, not a
certification. See [HHS risk-analysis guidance](https://www.hhs.gov/hipaa/for-professionals/security/guidance/guidance-risk-analysis/index.html).

## Coexistence and resource acceptance

Installation alone does not reserve the microphone or a hotkey. Choose a shortcut
that is not assigned to another application. Test the actual headset, docking
station, Bluetooth route, Teams/meeting setup, and target editor. Concurrent
capture can change audio routing or voice processing; do not claim universal
compatibility from a unit test. Measure transcription latency, CPU, peak memory,
power usage, interruption recovery, and exactly-once insertion on representative
managed devices using the [compatibility matrix](compatibility.md).
