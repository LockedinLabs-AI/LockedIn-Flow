# Supplemental upstream notices

`supplemental.json` retains authentic notice bytes from immutable upstream revisions
for four checksum-pinned Cargo packages whose published archives omit these files.
Each selected package's original manifest and all inspected Rust source files match
the recorded upstream revision exactly. The generator checks the registry, package
version, declared license and Cargo.lock checksum before associating notice text.
The material file and individual UTF-8 notice texts have pinned SHA-256 digests.
No build-time network retrieval is performed by this addition.

The `dasp_sample` Apache file is a short notice/reference, not the full Apache
license. Its MIT text is retained separately. Neither a notice association nor an
SBOM entry establishes runtime linkage or completes redistribution review.

No supplemental notices are assigned to `dlopen2`, `dlopen2_derive`, `audio-core`,
`selectors` or `realfft`: byte-level source differences, dirty-source provenance,
or missing full notice text remain unresolved. They must not inherit another
package's license text. Updating the fixed material requires reviewing immutable
upstream provenance, carrier and text identities, then updating the material digest
in `scripts/supplemental-notices.mjs` and running its focused tests.
