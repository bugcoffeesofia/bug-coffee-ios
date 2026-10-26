# 5 — The loyalty pass in the platform wallet

The capability: **the loyalty card lives in the phone's wallet app**, so the user can show it
without opening our app, and it surfaces on the lock screen near the shop.

The in-app QR (doc 1 §3) already covers "show a card to the barista" completely. **The wallet
pass is a convenience, not the core** — ship it when the core works.

Reference: `BugCoffee/Sources/PassBuilder.swift`, `PassSigner.swift`, `PkPassZip.swift`,
`Scripts/make_pkpass.sh`, `PassTemplate/`.

---

## 1. Pass content

This is the part to reproduce on any platform. On Apple this is a `storeCard`; on Google Wallet
it is a **loyalty object** (with its loyalty *class* holding the brand-level fields).

| Concept | Value | Google Wallet field |
|---------|-------|---------------------|
| Pass kind | store / loyalty card | `LoyaltyObject` + `LoyaltyClass` |
| Serial / object id | **the account UID** — stable, so re-issuing updates the same pass | `id` (namespaced) |
| Organization | "Bug Coffee" | `issuerName` / `programName` |
| Description | "Bug Coffee Loyalty Card" | class `localizedIssuerName` etc. |
| Header field | label "BUG COFFEE", value "Loyalty" | `programName` / header |
| Primary field | label "ПЕЧАТИ" (Bulgarian: *stamps*), value **"0 / 9"** | `loyaltyPoints` (label "ПЕЧАТИ") |
| Secondary field | label "ЧЛЕН" (*member*), value = account email, or a **typed name** for a pass built for a scanned UID | `accountName` |
| **Barcode** | **QR**, message = **the account UID**, encoding `iso-8859-1` | `barcode` `{ type: QR_CODE, value: <uid> }` |
| **Location** | 42.69323 N, 23.34402 E, top-level `maxDistance` **15 m** (not inside the location entry — Wallet ignores it there; it can only shrink Wallet's default radius), relevant text "Bug Coffee е наблизо" ("Bug Coffee is nearby") | `locations` on the object |
| Background | `#1F0409` | class `hexBackgroundColor` |
| Foreground | `#FFFFFF` | (platform-derived) |
| Label color | `#CC1E41` | (platform-derived) |
| Images | `icon.png` (+`@2x`, `@3x`) and `logo.png` (+`@2x`) | `programLogo` / `heroImage` |

Notes:

- **The primary "0 / 9" is static.** The pass is built once and the live count is not pushed
  into it (that would need a pass-update web service on Apple, or an object patch on Google, plus
  a reliable count — doc 2 §5). Don't imply freshness in the UI. If you *do* wire updates,
  patching the Google Wallet object's `loyaltyPoints` is the cheaper of the two.
- `icon.png` is **mandatory** on Apple — a pass without it is rejected. The reference builder
  loads the bundled artwork by exact filename and, if it is missing, **renders a fallback icon**
  so a generated pass can never be icon-less.
- The bundled `PassTemplate/` artwork is brand-colored placeholder; swap in real artwork (same
  filenames and @2x/@3x sizes) before shipping.
- Keep the serial = UID rule. It is what makes "add to wallet" idempotent.

---

## 2. Signing models (the part that does not port)

**Apple.** A `.pkpass` is a ZIP containing `pass.json`, the images, `manifest.json`
(SHA-1 of every file, keyed by filename) and `signature` — a **detached CMS/PKCS#7** signature
over the manifest, made with your **Pass Type ID certificate** and chained through Apple's
**WWDR** intermediate. Two hard-won details from the reference implementation:

- The CMS signature **must carry a signing time**; without signed attributes PassKit rejects the
  pass with "Signature must contain a signing date".
- Every entry must be at the **archive root**. The system folder-zipper nests entries under a
  directory, so the reference app writes the ZIP itself (STORE, no compression) with a valid DOS
  timestamp and Unix file mode.

**Google.** You do not sign a bundle: you create the loyalty class/object through the Wallet
API (or embed it in a **JWT signed by a service account**) and hand the user a "Save to Google
Wallet" link/button. The private key lives on your server or in your build pipeline, never in
the app.

So this subsystem is **replaced, not ported**. Only §1 (pass content) carries over.

---

## 3. Why it is behind a feature flag on iOS

On-device signing means the **Pass Type ID private key is embedded in the app bundle**. Anyone
with the binary could extract it and sign passes under that identity. The reference app
therefore compiles every pass-building path — the add-to-wallet button, the scan-and-share
flow, the signer — only into a dedicated build:

- `Config/LocalPassCreation.xcconfig` appends `LOCAL_PASS_CREATION` to the Swift compilation
  conditions.
- Only the `Debug-LocalPass` configuration uses that file; `Debug` and `Release` never define
  the flag.
- The `BugCoffee-LocalPass` scheme runs that configuration.

Result: default builds do not contain the code *or* the key; the feature is a scheme away for
personal use.

**The lesson for any platform:** never ship pass-signing keys in a client. Sign on a server (or
use Google's JWT flow, which is designed for exactly this). If you keep a local-signing
developer build, gate it the same way and never distribute it.

---

## 4. The optional scan-and-share flow

Debug-only power-user tool: scan **someone else's** loyalty QR, type a name for the pass, build
and sign a pass for that UID, write it to a temporary `.pkpass` and offer it via the share
sheet. Useful for making a pass for a family member who doesn't have the app.

Treat as **optional** in a port. It needs camera permission and a signing path, and it is the
only reason the reference app asks for the camera at all.

---

## 5. Manual signing on a Mac (reference workflow)

`Scripts/make_pkpass.sh` signs a pass with nothing but `openssl` and `zip`. It accepts either a
UID (`--uid <UID> --email you@example.com --name "…"`) or an unsigned bundle exported from the
app (`--bundle ./BugCoffee.pass`), and writes `BugCoffee.pkpass`.

One-time setup: create a Pass Type ID in the Apple Developer portal, download and import its
certificate, export a `.p12`, then produce the PEMs it expects:

```bash
openssl pkcs12 -in Certificates.p12 -clcerts -nokeys -out certs/passcert.pem -legacy
openssl pkcs12 -in Certificates.p12 -nocerts  -nodes -out certs/passkey.pem  -legacy
openssl x509 -inform DER -in AppleWWDRCAG4.cer -out certs/wwdr.pem
```

The same values must appear in `PassConfig` (pass type id, team id) — they are baked into every
distributed pass and are **not** secrets. The private key is.
