# Bug Coffee — Wallet Pass (iOS)

A small SwiftUI app that logs into a Bug Coffee account and turns it into an
**Apple Wallet loyalty card**. Built from the analysis in
`../Analysis/docs/BugCoffee-Reverse-Engineering.md`.

The loyalty QR is simply the account's **Firebase UID** at error-correction level
`H` — that's the exact string shop staff scan (doc §6). Firebase Auth is not
App Check-gated, so login works natively with only the public API key (doc §4.1).
The live stamp count *is* behind App Check and is intentionally out of scope for
this simple app (doc §7).

## What it does

1. **Login** — email/password against Google Identity Toolkit (same credentials as
   the web app). No Firebase SDK dependency; a single REST call.
2. **Loyalty card** — renders the UID as a QR with the brand colors.
3. **Add to Apple Wallet** — builds a `storeCard` pass for the logged-in account
   and **signs it on-device** (Apple `swift-certificates` CMS), then hands the
   `.pkpass` to Wallet. Works for whoever logs in — the QR is that account's UID.
   Next to it, a **scan-and-share** button opens the camera, reads another
   loyalty QR, signs a pass for *that* UID, and offers it via the share sheet.

   Both of these are **local pass creation** and are gated behind a feature flag —
   see below.

## Local pass creation (feature flag)

Everything that builds and CMS-signs a `.pkpass` on the device — the "Add to
Apple Wallet" button, the scan-and-share button, `PassSigner`, and
`PassBuilder.buildSignedPass` — is compiled only when the `LOCAL_PASS_CREATION`
Swift flag is set. This is deliberate: such a build embeds the Pass Type ID
private key (see the security note below), so the default build leaves it out.

The flag lives in [`Config/LocalPassCreation.xcconfig`](Config/LocalPassCreation.xcconfig)
and is wired up via `project.yml`:

- **Configuration** `Debug-LocalPass` (BugWallet target) uses that `.xcconfig`,
  which appends `LOCAL_PASS_CREATION` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.
- **Scheme** `BugWallet-LocalPass` runs that configuration.

So the scheme controls the feature: run/build **`BugWallet`** and none of the
pass-creation code is in the binary; run/build **`BugWallet-LocalPass`** and it
all lights up. The everyday `Debug`/`Release` configs never define the flag.

The camera scanner needs `NSCameraUsageDescription` (already in `Info.plist`) and
a real device — the Simulator has no camera, so the scanner shows a "no camera"
message there.

### Signing assets (required)

On-device signing needs your Apple **Pass Type ID** certificate + key, placed in
`BugWallet/Resources/Signing/` as `passcert.pem`, `passkey.pem` (unencrypted
PKCS#8), and `wwdr.pem` (Apple WWDR G4). These are gitignored.

> **Security:** this embeds your pass-signing private key in the app bundle. Fine
> for a personal build; do **not** distribute it — anyone could extract the key
> and sign passes under your Pass Type ID. For public distribution, sign on a
> server instead.

`Scripts/make_pkpass.sh` remains for signing a pass on a Mac (e.g. to pre-bundle
one) but is no longer required for the in-app button.

## Open / build

The Xcode project is generated with [XcodeGen](https://github.com/yonyz/XcodeGen)
from `project.yml`:

```sh
brew install xcodegen        # if needed
xcodegen generate            # writes BugWallet.xcodeproj
open BugWallet.xcodeproj
```

Then set your signing **Team** in Xcode (Signing & Capabilities) and run on a
device or simulator. It builds clean with no external Swift packages.

## Making the signed pass

Signing needs an Apple Developer account. You cannot avoid this — Wallet rejects
unsigned passes, and on-device signing isn't in the iOS SDK.

**One-time setup**

1. In the Apple Developer portal → **Identifiers → Pass Type IDs**, create a Pass
   Type ID, e.g. `pass.com.yourname.bugcoffee`.
2. Create/download its certificate, import into Keychain, then export as a `.p12`.
3. Note your 10-character **Team ID**.
4. Put those values into `PassConfig` (`BugWallet/Sources/PassBuilder.swift`) and
   the `CONFIG` block of `Scripts/make_pkpass.sh` so they match the certificate.
5. Produce the PEMs the script expects (defaults under `Scripts/certs/`):

```sh
cd Scripts && mkdir -p certs
openssl pkcs12 -in Certificates.p12 -clcerts -nokeys -out certs/passcert.pem -legacy
openssl pkcs12 -in Certificates.p12 -nocerts  -nodes -out certs/passkey.pem  -legacy
# Apple WWDR intermediate (download AppleWWDRCAG3.cer from Apple):
openssl x509 -inform DER -in AppleWWDRCAG3.cer -out certs/wwdr.pem
```

**Sign a pass**

```sh
# straight from a UID (uses PassTemplate/ images):
./Scripts/make_pkpass.sh --uid <FIREBASE_UID> --email you@example.com

# or from the bundle the app exported (unzip the shared file first):
./Scripts/make_pkpass.sh --bundle ./BugCoffee.pass
```

This writes `BugCoffee.pkpass`. AirDrop or email it to your iPhone and tap to add
it to Wallet. To wire the in-app **Add to Apple Wallet** button, copy that file to
`BugWallet/Resources/BugCoffee.pkpass` and rebuild.

> Don't know your UID? Sign in inside the app — it's shown at the bottom of the
> card and is copy-selectable.

## Project layout

```
project.yml                     XcodeGen spec
BugWallet/Sources/
  BugWalletApp.swift            app entry + Session
  FirebaseAuth.swift            REST email/password sign-in → UID
  QRGenerator.swift             Core Image QR (level H)
  PassBuilder.swift             pass.json + unsigned bundle; PassConfig
  Zip.swift                     folder → zip (system file coordinator)
  LoginView.swift / CardView.swift   UI
BugWallet/Resources/            Info.plist, Assets.xcassets
MessagesExtension/Sources/      iMessage app (group coffee orders)
  MessagesViewController.swift  MSMessagesAppViewController + SwiftUI host
  GroupOrder.swift              menu + order model, encoded in the message URL
  OrderStore.swift / OrderViews.swift   view state + UI
  OrderCardRenderer.swift       the picture inside the message bubble
PassTemplate/                   pass images (icon/logo) — bundled + used by the script
Scripts/make_pkpass.sh          signs a .pkpass with openssl
```

## iMessage app — group orders

The `BugWalletMessages` extension adds Bug Coffee to the iMessage app drawer.
One person starts a **coffee run**, picks their drinks, and sends it to the
chat; everyone else taps the bubble, adds their drinks, and sends the update
back. The whole order travels inside the message itself (`MSSession` + URL
query items) — no server, and the same bubble updates in place instead of
spamming the chat. The menu is hard-coded in `GroupOrder.swift` (the real
backend has no menu API; the loyalty system only counts stamps). Participants
appear as "You" / "Friend N" because iMessage extensions never see contact
names.

The pass images in `PassTemplate/` are brand-colored placeholders; swap in real
artwork (keep the same filenames and `@2x/@3x` sizes) before shipping.
