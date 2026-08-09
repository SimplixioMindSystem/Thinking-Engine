# SimpliXio Privacy Policy

_Last updated: August 8, 2026_

SimpliXio is local-first and does not require a SimpliXio account or product
server. Captures, ranking, semantic search, Weekly Review, Decision Replay, and
newsletter safety checks run on the Apple device.

## Data SimpliXio Handles

The app may store information that you choose to enter, including:

- notes and captured thoughts
- profile context that helps rank priorities
- decisions, insights, and feedback
- generated priorities and review state

SimpliXio does not use advertising identifiers, analytics SDKs, or tracking
libraries.

## Local Storage

Your device is the source of truth. Captures save locally before any sync work,
so the core app remains usable when iCloud is unavailable or private sync is
disabled.

## Private iCloud Sync

Private iCloud sync is available across the signed SimpliXio apps for iPhone,
Mac, and Apple Watch. Before source state enters iCloud storage, SimpliXio:

1. compresses the payload on-device
2. encrypts it on-device with AES-GCM
3. stores the encryption key as a synchronizable iCloud Keychain item
4. sends only authenticated ciphertext through the user's iCloud account

The encryption key is shared only among SimpliXio apps signed by the same Apple
developer team. SimpliXio does not operate a server that receives or can read
this content. If iCloud or the private key is unavailable, changes remain local
and the app retries without replacing unreadable cloud data.

iCloud storage and iCloud Keychain are Apple services and are also governed by
Apple's terms and privacy policy. You can disable private sync in SimpliXio
Settings; existing local captures remain available on that device.

## Public Output

Newsletter and other public-safe drafts are generated and redacted on-device.
SimpliXio does not publish them automatically. You must review and explicitly
share any exported draft.

## Optional Developer Tooling

The public repository contains an optional Python API and integration examples
for developers. Those tools are not included in the iOS, macOS, or watchOS app
binaries. The shipping Apple apps do not depend on Railway or another product
backend.

## Data Sharing

SimpliXio does not sell user data. It does not send readable captures to
SimpliXio, Railway, advertising networks, analytics providers, or external AI
models.

## Children's Privacy

SimpliXio does not knowingly collect personal information from children under
13.

## Contact

For privacy questions, contact [Pierre-Henry Soria](mailto:pierre@pierrehenry.dev).
