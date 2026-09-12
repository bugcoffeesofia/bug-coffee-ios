# 8 — Building the reference app, and verifying a port

---

## 1. Running the iOS reference implementation

Useful while porting: it is the fastest way to see a behavior you are unsure about.

The Xcode project is **generated** from `project.yml` with [XcodeGen] — edit the YAML, not the
`.xcodeproj`:

```bash
brew install xcodegen
xcodegen generate
open BugWallet.xcodeproj
```

Then set your signing **Team** and run. Targets and deployment floors:

| Target | Kind | Floor |
|--------|------|-------|
| `BugWallet` | iOS app (iPhone + iPad) | iOS 16.0 |
| `BugWalletStampWidget` | widget extension | iOS 16 (iOS 17 container background path) |
| `BugWalletMessages` | iMessage app extension | iOS 16.0 |
| `BugWalletWatch` | watchOS app, embedded in the iOS app | watchOS 9.0 |

Schemes:

| Scheme | What it runs |
|--------|--------------|
| `BugWallet` | the app, **without** any pass-creation code |
| `BugWallet-LocalPass` | the app with on-device pass signing enabled (doc 5 §3) |
| `BugWalletMessages` | launches Messages as the host app |
| `BugWalletWatch` | the watch app |

Only two Swift packages, both Apple's, and only for pass signing: `swift-certificates` (X509)
and `swift-crypto` (`_CryptoExtras`). Nothing else is external.

### 1.1 Things that will bite you

- **On-device signing assets.** `BugWallet-LocalPass` needs `passcert.pem`, `passkey.pem`
  (unencrypted PKCS#8) and `wwdr.pem` in `BugWallet/Resources/Signing/`. They are gitignored.
  Without them the pass buttons surface a "Missing signing asset" error.
- **The camera scanner needs a real device** — the Simulator has none and shows a message
  instead.
- **Watch platform pinning.** The embedded watch target explicitly sets
  `SUPPORTED_PLATFORMS = watchos watchsimulator`, because the iOS build was otherwise
  "specializing" it to the iOS Simulator SDK and failing on watch-only API.
- **The watch target compiles only watch-safe shared files** (listed explicitly in
  `project.yml`), because some shared SwiftUI uses controls that don't exist on watchOS.
- **Entitlements are generated** from `project.yml` — declare capabilities there, not in the
  `.entitlements` files.

[XcodeGen]: https://github.com/yonyz/XcodeGen

---

## 2. Platform capabilities a port must request

| Capability | Why | iOS | Android |
|------------|-----|-----|---------|
| Network | sign-in | (default) | `INTERNET` |
| Health write (caffeine) | "Log a coffee" | `NSHealthUpdateUsageDescription` + share string, HealthKit entitlement | Health Connect caffeine **write** permission |
| Shared storage between app / widget / watch | stamp count, favorites, diary | App Group | shared module DataStore, or a ContentProvider |
| Camera | **optional** — scan-and-share pass only | `NSCameraUsageDescription` | `CAMERA` |
| Custom URL scheme | bean deep links | `CFBundleURLTypes` (`bugcoffee`) | intent filter |

The app requests **no** location, contacts, notification or tracking permission. The wallet
pass's `locations` entry is handled by the wallet app, not by us — we never ask for location.

---

## 3. Acceptance tests for a port

Run these against the port and, where behavior is ambiguous, against the reference app. Grouped
by the milestones in the [index](README.md#porting-order).

### M1 — core

1. Wrong password ⇒ "Wrong email or password."; the button re-enables; nothing is persisted.
2. Airplane mode ⇒ a network error message, not a crash and not a blank screen.
3. Correct credentials ⇒ Card tab, email in the header, UID in the footer.
4. The QR **decodes to exactly the UID string** — scan it with a generic QR reader and compare
   character for character. No prefix, no URL, no whitespace.
5. Kill and relaunch **in airplane mode** ⇒ straight to the card, no login, no spinner.
6. Sign out ⇒ login screen; relaunch ⇒ still login screen.
7. Sign out then back in ⇒ stamps, favorites and diary are **still there**.
8. Long-press/select the UID footer ⇒ it can be copied.

### M2 — stamps

9. **+** nine times ⇒ `9 / 9`, nine filled slots; a tenth tap does nothing.
10. **−** below zero does nothing.
11. Set 4 stamps, force-quit, relaunch ⇒ still 4.
12. Set stamps, then check the widget **without** opening the app ⇒ same number.
13. Compare the filled-stamp pattern in app, widget and watch at the same count ⇒ **pixel-wise
    identical jitter** (doc 7 §4.1).
14. If you implemented a live count: when it arrives it **overrides** the manual value, and a
    backend drop 9 → 0 is accepted silently (doc 2 §4).

### M3 — products

15. Every price matches doc 3 §1 in **both** currencies (spot-check `lat` ⇒ `3.30 € / 6.45 лв.`).
16. Star a drink ⇒ it jumps to the top of its section; relaunch ⇒ still starred and still on top.
17. A starred item shows starred in the group-order menu too, and vice versa.
18. Bean row taps open the bean page; **drink rows do not**.
19. Add a cup with 4 stars ⇒ the bean row shows `★ 4.0`; add a second at 3 ⇒ `★ 3.5`, and the
    page reads "2 cups".
20. Add a cup with no stars ⇒ the count reads "3 cups · 2 rated" and the average is unchanged.
21. Open the editor, change nothing, Save ⇒ **Save was disabled**; nothing is added.
22. Tap the current star rating ⇒ it clears to unrated.
23. Delete a cup ⇒ it disappears and the average recomputes on the row immediately.
24. Quiz: Black + Regular + "Chocolate & nuts" ⇒ three chocolatey non-decaf beans, best first.
    Switch to Decaf ⇒ only `bbe` is eligible.
25. Rate a bean 5 ⇒ it rises in an otherwise-unchanged quiz result.

### M4 — companions

26. Widget small and medium both render; medium shows "Free drink earned! 🎉" at 9 and
    "<n> to a free drink" below it.
27. With the watch app never opened, sign in on the phone, then open the watch ⇒ card and stamps
    are there (the queued payload arrives on activation).
28. Turn the phone off / out of range ⇒ the watch still shows the card from its own storage.
29. Change stamps on the phone ⇒ the watch count follows; the watch **cannot** change it.
30. `bugcoffee://bean/kul` from another app ⇒ Products tab, Kultura's page open.
31. `bugcoffee://bean/zzz` and `bugcoffee://something/kul` ⇒ **ignored**, no navigation, no error.

### M5 — integrations

32. First "Log a coffee" ⇒ permission prompt; after granting, the confirmation text appears and
    the sample is visible in the system health app with the right mg and food name.
33. Deny the permission ⇒ the "access is off" message, no crash, no silent failure.
34. Log from the watch ⇒ the sample appears and syncs to the phone.
35. Wallet pass (if built): the pass's barcode scans to the same UID; adding it twice does not
    create a duplicate (same serial/object id).

### M6 — group order

36. Build an order, encode it, decode it in a **fresh install** ⇒ identical lines, totals and
    participant labels.
37. Decode a **v2** link (5 fields per `o=`) ⇒ it loads, with every line on the house blend.
38. Decode a link containing one malformed `o=` ⇒ the other lines still load.
39. Two people, each adding drinks in turn ⇒ each person's lines survive the other's submit; no
    duplicates for the person who edits twice.
40. Add the same plain drink twice ⇒ one line, qty 2. Add one with oat milk ⇒ a separate line.
41. `lat` + oat milk × 2 ⇒ `(330 + 60) × 2 = 780` ⇒ `7.80 € / 15.26 лв.`.
42. Nine is the quantity ceiling per line.

### Cross-cutting

43. Largest accessibility text size: no screen clips; the login form and card scroll.
44. Smallest supported window/viewport: every control still reachable.
45. Rotate / fold / resize while a modal is open ⇒ the modal stays up.
46. Screen reader pass over the card and a bean page: stars, the average and the favorite toggle
    all announce meaningfully (doc 7 §3).

---

## 4. Parity checklist (one line per capability)

| Capability | Doc | Required? |
|------------|-----|-----------|
| Email/password sign-in, mapped errors | 2 §2 | **Yes** |
| Offline session restore, sign-out | 2 §2.4 | **Yes** |
| Loyalty QR = UID, level H | 2 §3 | **Yes** |
| Copyable UID | 1 §3 | Yes |
| Manual 9-slot stamp card with deterministic jitter | 1 §4, 7 §4 | **Yes** |
| Shared storage feeding widget/watch | 3 §3 | Yes (if you ship those) |
| Static menu with dual pricing | 3 §1 | Yes |
| Favorites, shared across surfaces | 3 §3 | Yes |
| Bean pages + tasting diary | 1 §5.1, 3 §4 | Yes |
| Blend quiz with identical scoring | 3 §2.3 | Yes |
| Caffeine logging to the system health store | 1 §6.1 | Recommended |
| Home-screen widget | 1 §7 | Recommended |
| Watch companion | 1 §8, 4 §4 | Optional |
| Deep links to a bean | 1 §9 | Recommended |
| Group order via link | 6 | Optional |
| Platform wallet pass | 5 | Optional |
| Live stamp count | 2 §5 | Optional — read the caveats first |
| Scan-and-share a pass | 5 §4 | Optional (debug-only on iOS) |
