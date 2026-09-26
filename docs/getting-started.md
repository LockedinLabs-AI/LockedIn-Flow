# Get started

LockedIn Flow turns speech into editable text on your Mac. It is free under the
MIT License, including commercial and enterprise use.

## Choose an installation

| Use | Installation | Availability |
| --- | --- | --- |
| Everyday dictation | Signed, notarized Mac download | In preparation; see [release status](https://lockedinflow.com/download.html) |
| Developer evaluation | Build and install from this repository | Commands below |
| Managed enterprise evaluation | Pre-stage models and deploy through your Mac management system | [Managed deployment guide](managed-deployment.md) |

The installed app needs an Apple silicon Mac, macOS 15 or later, and Microphone
and Accessibility permission. Speech models take approximately 484 MB. Optional
generative cleanup requires macOS 26 and an available Apple on-device model;
core dictation does not require an external LLM.

## Install from source

Use Node.js 20 or later and the supported build tools: Xcode 26.6 build 17F113,
Apple Swift 6.3.3, and the macOS 26.5 SDK. Xcode is needed to build from source;
Node is not used by the installed application.

```bash
git clone https://github.com/LockedinLabs-AI/lockedin-flow.git
cd lockedin-flow
npm ci --ignore-scripts --no-audit --no-fund
npm run doctor
npm run setup:local -- --launch
```

The final command explicitly builds and installs the LockedIn Flow app in your user
Applications folder, provisions the verified models, and opens the app. Setup
uses the internet to obtain source dependencies and models. Once provisioned,
core dictation works locally. Enterprise administrators can distribute the
reviewed models through an approved internal channel.

There is no npm-registry package yet. `npm ci` initializes the tooling in this
clone; it does not silently install an application or download models. The local
evaluation app is ad-hoc signed and has a separate identity from other LockedIn
Flow installations.

## Your first dictation

1. Open LockedIn Flow. Allow microphone access and follow the
   Accessibility permission instructions in System Settings.
2. Confirm the provisioned speech model is ready.
3. Open Notes or another supported editor and click an ordinary text field.
4. Press **Control-Shift-Space**, speak, then press it again to finish. Keep the
   intended field focused until the text appears.
5. Review the text. Use Vocabulary for names and terms you want written
   consistently; the [CSV example](../examples/terminology-template.csv) contains
   synthetic entries only.

Choose a shortcut that other dictation apps do not share, and record with one
dictation app at a time. A second installed app is not by itself a conflict.
Voice Focus is optional; standard microphone capture is the default.

## If something needs attention

| Symptom | Next action |
| --- | --- |
| Model unavailable | Run `npm run provision:models`. To replace a failed verification, explicitly add `-- --repair`. |
| Microphone has no signal | Check the input in macOS Sound settings and microphone permission. Test with other recording apps stopped. |
| Text could not be inserted | Click the intended field and use local recovery when offered. Password fields and security-unverifiable destinations are deliberately refused. |
| Existing LockedIn Flow app | Quit it, then use `npm run setup:local -- --replace`. The previous bundle is kept as a timestamped backup. |
| Another app receives the shortcut | Assign a distinct shortcut in Settings. |

History and recovery are session-only by default. Optional persistent history is
encrypted locally. Sensitive or security-unverifiable insertion outcomes are
discarded and are not retained for recovery.

For a report, provide the app version, macOS version, hardware, target app, and
a reproduction with synthetic text. Do not attach real dictations, recordings,
private screenshots, or unreviewed system logs. See [Support](../SUPPORT.md).

## Evaluate offline behavior

After model setup, disconnect the network and repeat a short synthetic dictation.
For enterprise approval, enforce application egress controls and capture network
evidence against the exact signed artifact. Follow the
[enterprise evaluation guide](enterprise-evaluation.md) for compatibility,
recovery, performance, and deployment checks.
