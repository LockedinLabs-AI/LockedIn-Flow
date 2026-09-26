# Engineering and publication standards

LockedIn Flow is developed for reviewable, on-device voice input. This page
connects the project's practices to established open-source and software supply
chain guidance. It is an implementation map, not a certification or a badge.

See the [AI-assisted development lifecycle](secure-development.md) and
[third-party risk register](third-party-risk.md) for operational ownership,
adversarial-review scope, and evidence boundaries.

## Reference practices

| Reference | Application in this project | Evidence |
| --- | --- | --- |
| [OpenSSF Best Practices](https://www.bestpractices.dev/en/criteria/0) | Clear licensing, build instructions, contribution and vulnerability-reporting paths, versioned releases, tests, and static analysis | [MIT License](../LICENSE), [getting started](getting-started.md), [contributing](../CONTRIBUTING.md), [security policy](../SECURITY.md), [CI](../.github/workflows/ci.yml) |
| [NIST Secure Software Development Framework 1.1](https://csrc.nist.gov/pubs/sp/800/218/final) | Document boundaries, review sensitive code, protect release integrity, minimize defaults, and address defects with regression tests | [Threat model](threat-model.md), [CODEOWNERS](../.github/CODEOWNERS), [release process](release-process.md), [tests](../Tests) |
| [SLSA supply chain guidance](https://slsa.dev/spec/v1.1/levels) | Record source and dependency identity, generate an SBOM, and attest the exact produced artifact | [Build workflow](../.github/workflows/ci.yml), [SBOM validation](../scripts/validate-sbom.sh), [validation status](validation.md) |
| [GitHub repository publication guidance](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility) | Review the complete publication surface, including history, author metadata, issues, pull requests, workflow logs, and artifacts | Publication process below |

The project does not claim an OpenSSF badge, SLSA level, regulatory
certification, or completed enterprise acceptance. Platform-specific dependencies
and outstanding validation are recorded in [model licenses](model-licenses.md)
and [validation evidence](validation.md).

## Public material

Only product source, synthetic tests, reviewed visuals, build tooling, and
public documentation belong in the repository. Do not add chat exports,
recordings, transcript logs, internal handoffs, personal files, customer data,
credentials, or generated build output.

Run `npm run check:public` before a pull request. The check rejects common private
file types, personal contact patterns, machine-specific paths, conversation
exports, unreviewed binary assets, and broken local documentation links. Its
output contains rule names and hashed file identifiers, never matching content
or unreviewed file paths. An entry identifier is the first 12 characters of the
SHA-256 of the repository-relative path; resolve it locally when investigating.

Run `npm run check:public -- --history` against the complete proposed publication
history before first publication. Use a full clone: a shallow clone cannot prove
what earlier revisions contain. TruffleHog independently checks credential
patterns. Neither automated check can determine whether every natural-language
paragraph is private; a maintainer must review text, fixtures, visuals, and
metadata as well.

Visuals must come from the product with synthetic examples, or be explicitly
labeled as illustrations. Raster assets have an explicit reviewed hash inventory.
Any change requires a new visual and metadata review before updating that hash.
Copyright attribution in third-party notices is retained.

The developer preview renderer produces the product views using synthetic
fixtures. `node scripts/sanitize-public-media.mjs` removes ancillary PNG metadata
from the reviewed asset paths without changing compressed pixel data. Review
the output and update `security/public-media.json` explicitly; the sanitizer
does not approve its own output.

## Initial publication

1. Review the exact candidate tree and intended public documentation.
2. Export only that tree into a new, unrelated repository when the source history
   contains material outside the public product. Do not copy Git internals,
   workflow logs, discussions, issues, or pull requests from a private project.
3. Scan every reachable revision and review commit metadata. Maintainers use an
   approved public identity and corporate or GitHub private email address.
4. Configure least-privilege Actions, required review and checks, CODEOWNERS,
   branch protection, secret scanning, and private vulnerability reporting.
5. Obtain owner approval of the actual sanitized candidate before changing
   visibility. Record source, tree, and artifact identities in the release record.
6. Publish a signed application only after the separate artifact and installed
   acceptance gates pass. Source availability does not imply a binary release.

Repository access settings and branch protections are hosting configuration;
their presence must be checked on GitHub, not inferred from a workflow file.

## Operational privacy

Application diagnostics use fixed event messages and numeric or boolean
metadata. The logging API does not accept interpolated strings; error logging
retains only a numeric code, excluding descriptions, domains, user information,
file paths, app identities, and dictated content. Developer-only transcription
diagnostics are excluded from production binaries and require synthetic inputs.

Model provisioning is a separate, explicit setup step. Application runtime has
no updater, telemetry client, inbound listener, or hosted inference adapter.
Enterprise deployments pre-stage models and enforce their own network policy.
The receiving application follows its own data policy after insertion.
