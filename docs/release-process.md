# Release process

Official releases are produced from a protected, clean, synchronized default
branch. A source commit, a passing CI run, and an installed application are
separate pieces of evidence.

## Source gate

- all Swift tests pass;
- release configuration builds with resolved dependencies;
- release binary diagnostic gate passes;
- application source does not invoke model acquisition, the dependency model hub
  is forced offline, and offline-only model tests pass;
- npm developer tooling has no dependencies or lifecycle hooks and its tests pass;
- public-content and local documentation-link checks pass with `npm run check:public`;
- SBOM generation and validation pass;
- CodeQL, dependency review, and secret scanning pass;
- CodeQL produces a populated SARIF analysis with zero findings; successful
  scanner execution or upload alone does not satisfy the gate;
- dependency and model-license changes are reviewed; and
- release notes identify limitations and migration impact.

## Artifact gate

- build on macOS 26 with Xcode 26.6 (build 17F113), Apple Swift 6.3.3,
  and the macOS 26.5 SDK; CI selects the exact Xcode installation, fails before
  dependency resolution if any version differs, and records the hosted-runner
  image version;
- use the controlled Developer ID identity and hardened runtime;
- include third-party notices and the generated CycloneDX SBOM;
- verify the app and embedded frameworks with `codesign`;
- notarize the app and disk image, staple tickets, and verify Gatekeeper;
- record exact source revision, artifact size, SHA-256, signing identity, and
  notarization evidence;
- retain the recorded `Package.resolved` SHA-256, embedded build-provenance
  record, CycloneDX SBOM, and provenance/SBOM attestations for the exact
  distributed artifact; and
- confirm the public download is byte-identical to the approved artifact.

If a release redistributes models, treat each model package as a separate
release artifact: complete the license review, include the required attribution
and model inventory in its SBOM, verify the exact tree before packaging, and
attest the final signed package. The source provisioning utility is not itself a
redistribution license.

Production signing and notarization credentials are not part of this public
repository. `scripts/package-community-app.sh` creates an ad-hoc signed local
bundle for evaluation; it is not an official release artifact.
`scripts/package-evaluation-pkg.sh` wraps that bundle in an unsigned, no-script
component package so the eventual MDM installation shape can be tested. It is
also not an official release artifact.

The repository's public CI attests its unsigned evaluation ZIP, unsigned
evaluation PKG, and packaged SBOM. A later Developer ID signed or notarized
artifact needs its own provenance record or attestation; the evaluation
attestations must not be presented as covering a separately produced release
artifact.

Every generated SBOM has a fresh RFC 4122 UUID serial number, as recommended by
CycloneDX 1.6 and required by the pinned GitHub attestation action. The local
validator rejects missing or malformed identities before artifact upload. For
byte-identical reproduction of an existing SBOM, pass its recorded identity to
`scripts/generate-sbom.sh --serial-number <urn:uuid:...>` together with the same
source and inventory inputs; new builds should use the default fresh identity.

## Installed acceptance gate

Before promoting a dictation release, test repeated record-to-exactly-once
delivery in representative native and renderer-driven editors. Exercise target
remounts, focus changes, secure-field refusal, clipboard ownership changes,
microphone recovery, app restart, update installation, and rollback/recovery
copy. A source-level pass does not waive installed acceptance.

## Repository publication gate

Before changing repository visibility, the owner reviews the exact sanitized
candidate and its complete reachable Git history. Secret scanning, CI, license
review, local-link validation, and the source, artifact, and installed gates
must have recorded results appropriate to the material being published.

Use `npm run check:public -- --history` in a full clone of the publication
candidate. This complements credential scanning with checks for personal paths,
contact details, conversation exports, private files, and unreviewed media.
Review commit identities, visuals, workflow logs, issues, and pull requests as
described in [Engineering and publication standards](project-standards.md).

Protect the default branch with required CI and security checks, pull-request
review, and CODEOWNERS review before accepting external changes. If the hosting
plan cannot apply those controls while the repository is private, enable them
as part of the visibility transition and do not accept subsequent changes until
the rules are active. Repository publication does not authorize publishing an
unsigned application or model artifact.

## Versioning

The project uses semantic versions and an incrementing macOS build number. Every
official release tag is immutable and cryptographically signed. A changelog
entry and GitHub release describe user-visible changes and known limitations.
