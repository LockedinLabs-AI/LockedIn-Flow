# Security policy

## Supported versions

Before the first public release, security fixes are applied to the default
branch. After that release, fixes are applied to the latest supported release
and the default branch. Older releases may not receive patches.

| Version | Supported |
| --- | --- |
| First public release candidate | Not yet released |
| `main` | Yes |
| Older releases | No |

## Report privately

Use GitHub's **Report a vulnerability** feature for this repository. If it is
unavailable, use the [LockedIn Labs contact form](https://lockedinlabs.ai/contact/)
to request a secure reporting channel. Include the repository name and a safe
way to reach you, but do not put exploit details, credentials, personal data,
customer data, or protected health information in a public issue or the initial
contact form.

Once a secure channel is arranged, provide the affected version, impact, and a
minimal reproduction. We will coordinate validation, remediation, and disclosure
with the reporter. No response-time or certification commitment is implied by
this community policy.

## Scope

High-value areas include secure-field refusal, delivery-time target validation,
at-most-once text delivery, encrypted local storage, release-artifact integrity,
model provenance, diagnostic exclusion from release binaries, and accidental
content exposure through logs or clipboard fallbacks. Social engineering,
denial of service against third-party hosts, and reports requiring real customer
or patient data are out of scope.
