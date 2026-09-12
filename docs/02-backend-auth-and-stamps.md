# 2 — Backend, authentication and the stamp count

There is **no Bug Coffee server of our own**. The backend is the shop's existing **Google
Firebase** project, the same one the shop's web app uses. Everything else the app knows is
either derived from the signed-in identity or stored on the device.

Reference: `BugWallet/Sources/FirebaseAuth.swift`, `BugWalletApp.swift`,
`StampWebSync.swift`; and `../Analysis/docs/BugCoffee-Reverse-Engineering.md` for how the
backend was mapped.

---

## 1. Firebase project (public client config)

These values are **client config, not secrets** — they ship inside the shop's own web bundle.
Firebase security comes from Security Rules plus App Check, not from hiding them.

```json
{
  "apiKey":            "AIzaSyDjY4FROGGt9h4Q-V_3InC8Nv2sEeA-FxI",
  "authDomain":        "bug-coffee.firebaseapp.com",
  "projectId":         "bug-coffee",
  "storageBucket":     "bug-coffee.appspot.com",
  "messagingSenderId": "420013287658",
  "appId":             "1:420013287658:web:569c74a5a0165c03fa4f93"
}
```

The `appId` is the **web** app's. A native platform that wants to use the Firebase SDKs
properly needs **its own app registered in the `bug-coffee` project** — which requires access
to that project's console (see §5.2).

The web app is served from `https://app.bugcoffee.com` (the shop site is `bugcoffee.com`).

---

## 2. Sign-in

Email/password against **Google Identity Toolkit** — one HTTPS call, no SDK required:

```http
POST https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=<API_KEY>
Content-Type: application/json

{ "email": "<email>", "password": "<password>", "returnSecureToken": true }
```

**Authentication is not App Check-gated**, so this works from any native client with only the
public API key above. Using the platform's Firebase Auth SDK against the same project is
equivalent and generally the better choice — it gives you token refresh for free.

### 2.1 Response fields used

| Field | Use |
|-------|-----|
| `localId` | **The UID.** Required — this *is* the loyalty identity (§3). |
| `email` | Displayed on the card; falls back to the typed address if absent. |
| `idToken` | ~1 h bearer token. Only needed if you read Firestore (§5). |
| `refreshToken` | Long-lived. Only needed if you read Firestore (§5). |

Missing `localId` or `idToken` ⇒ treat as a malformed response.

### 2.2 Request/response failure handling

- Non-2xx: take `error.message`; Identity Toolkit sometimes appends detail after a space
  (`"INVALID_PASSWORD : ..."`), so **split on whitespace and keep the first token** before
  mapping.
- Transport failure ⇒ show the platform's network error description.
- Unparseable body or missing required fields ⇒ **"Unexpected response from the server."**

### 2.3 Error-code map

| Code | Message shown |
|------|---------------|
| `EMAIL_NOT_FOUND`, `INVALID_PASSWORD`, `INVALID_LOGIN_CREDENTIALS` | "Wrong email or password." |
| `USER_DISABLED` | "This account has been disabled." |
| `TOO_MANY_ATTEMPTS_TRY_LATER` | "Too many attempts. Please try again later." |
| anything else | the raw code |

### 2.4 Session persistence and restore

- On success, persist **uid**, **email** and **refreshToken** to ordinary (non-shared) app
  storage.
- On launch, if a stored uid exists, **restore the session straight away** — no re-login, no
  token refresh, no network call. The card needs only uid + email, so the app is fully usable
  offline after the first login.
- Consequences to keep: a restored session has **no valid ID token**, so anything that needs
  one (§5) must obtain a fresh one from the refresh token.
- **Sign out** removes those three keys (and stops the stamp sync). Local data — stamps,
  favorites, tasting diary — is intentionally kept.

> If you use a Firebase Auth SDK instead of the raw call, the SDK's own persistence replaces
> this; still keep "restore without a network call" as the behavior.

---

## 3. The loyalty identity

**The QR the barista scans is the Firebase UID string, verbatim.** No JSON, no URL, no prefix.
Example payload: `Mcks9Tpp1POFKcT1CotP7SF5Mwi1`.

- Error-correction level **H**.
- The shop's scanner reads the raw text and uses it directly as a Firestore document id, so
  **any** standard QR encoding of that string scans. Black-on-white is fine; the web app's
  rounded dots and centered bug logo are cosmetic (level H is what makes the logo overlay
  possible).
- Everything visual in this product — card QR, watch QR, wallet-pass barcode — is derived from
  this one string. Get it right and the core feature works.

---

## 4. Firestore data model

Two collections; the document id is always the UID.

### `users/{uid}`
```ts
{ isAdmin: boolean, timestamp: Timestamp }
```
Only used by the shop's own app to route staff to the scanner. **A customer app can ignore it.**

### `user-stamps/{uid}` — the loyalty card
```ts
{
  fingerprint: string,   // always === uid (legacy field name)
  stamps_count: number,  // 0..9; 9 means "free drink earned"
  timestamp: Timestamp   // updated on every change
}
```

Rules observed in the shop's web app:

- `maxStamps = 9`; reaching it is the reward state.
- Staff "add stamp" math wraps: `updated = (added + current) % 10` — so 9 → 0 starts the next
  card. A client must therefore **accept a count dropping back to 0** as normal, not as an error.
- Customer reads are realtime (`onSnapshot`), cache-first.
- The web app creates the document on first visit if missing:
  `{ fingerprint: uid, stamps_count: 0, timestamp }` merged in.
- **Naming trap:** despite the field name, do **not** implement device fingerprinting. The
  value is always the UID.

---

## 5. The stamp count: the one hard problem

**Firebase App Check is enforced on Firestore for this project, and its only configured
provider is reCAPTCHA v3 — a web-origin provider.** A raw Firestore read with a perfectly
valid ID token for your own document returns:

```json
{ "error": { "code": 403, "message": "Missing or insufficient permissions.",
             "status": "PERMISSION_DENIED" } }
```

The rules evidently also require `request.app != null`, which the web SDK satisfies and a plain
request does not. Sign-in is unaffected.

So: **login + QR is fully buildable on any platform today; the live stamp count is not, without
one of the following.**

### 5.1 Option A — manual count (what ships by default)

The user taps **+** each time the barista stamps them; the count lives only on the device
(doc 3 §3). Zero dependencies, works offline, and the QR (which is what the shop actually
scans) is unaffected. **Every port must implement this path**, because it is also the fallback
for the others.

### 5.2 Option B — native App Check (the correct fix, needs project access)

Whoever owns the `bug-coffee` Firebase project registers your app and enables the platform's
native attestation provider — **App Attest/DeviceCheck** on Apple platforms, **Play Integrity**
on Android — plus debug tokens for development. Then the ordinary Firebase SDK reads
`user-stamps/{uid}` normally, in realtime, and none of the rest of this section is needed.

Worth checking first: App Check can be in **monitor** rather than **enforce** mode. If it is,
native SDK reads may already succeed.

This is the path to recommend for any port intended for distribution.

### 5.3 Option C — WebView token vendor (what the iOS reference app does)

Implemented in `StampWebSync.swift` and labelled there as "variant 3". It does **not** forge or
bypass attestation: it runs the **real web app** in an off-screen WebView, lets that page
perform its own legitimate reCAPTCHA attestation, and reuses the resulting token for one native
read of **the signed-in user's own document**.

Flow:

1. Requires a stored **refresh token**; without one it does nothing and the status reads
   `"no token — manual count only"`.
2. Create an off-screen WebView (1×1, ~1% opacity, **attached to the window** — a fully
   detached or hidden web view gets its timers throttled and the attestation stalls).
   Use a **persistent** data store so the seeded session survives launches.
3. At document start, inject a script that:
   - **seeds the web app's own auth persistence** with the account already signed in natively
     (Firebase JS keeps the signed-in user in IndexedDB `firebaseLocalStorageDb`, store
     `firebaseLocalStorage`, key `firebase:authUser:<apiKey>:[DEFAULT]`), with the access token
     marked already expired so the SDK refreshes it from the refresh token on boot. The write
     is idempotent; the page posts `seeded` when the transaction commits.
   - **hooks `fetch` and `XMLHttpRequest`** to observe the page's *own* outgoing Firestore
     requests and read two headers off them: `X-Firebase-AppCheck` and
     `Authorization: Bearer <idToken>`. (Firestore's WebChannel uses XHR, so the XHR hook is
     the reliable capture point.)
   - also scans Firestore **response** bodies for `stamps_count` as a fallback.
4. Load `https://app.bugcoffee.com/app`. On the first `seeded` message, **reload once** — the
   IndexedDB write and the SDK's async read of it race, so the first load can still come up
   logged out. After the reload the page boots authenticated and its stamp listener fires.
5. With both headers captured, make a plain native read:

```http
GET https://firestore.googleapis.com/v1/projects/bug-coffee/databases/(default)/documents/user-stamps/<uid>
Authorization: Bearer <idToken>
X-Firebase-AppCheck: <token>
```

6. Parse `fields.stamps_count.integerValue` (a **string** in Firestore REST; accept number and
   `doubleValue` too), clamp to 0…9, and apply it (doc 1 §4).
7. If the native read fails for any reason, the count scraped from the page's own response is
   used instead, so the card still updates.

Lifetimes: reCAPTCHA-derived App Check tokens last on the order of ~30 minutes, ID tokens ~1 h.
Treat both as short-lived and re-run the flow rather than caching them.

**Caveats — read before porting this.** It depends on the shop's web app internals (routes,
Firebase JS persistence layout, transport choice); any of those changing breaks it silently.
It requires an embeddable browser engine with script injection and a persistent cookie/IndexedDB
store, which not every target platform offers on the same terms. It also carries the user's
refresh token into a web context. It is a **personal-build workaround**, appropriate for an app
whose user reads only their own loyalty count with their own credentials — not something to
ship broadly, and not a substitute for Option B. Note also that the project's own
reverse-engineering notes advise against *defeating* App Check; this approach deliberately
works *with* it (a real attestation, performed by the real web app, for the real user) rather
than around it, but the honest framing is "borrowed credential, narrow use".

A far simpler variant of the same idea, if you only want the feature and not the native read:
**show the web app's own card screen in a WebView** (Option D). Everything works unchanged
because it *is* the web app. Least native, zero backend dependency.

### 5.4 Status strings (reference implementation)

The card shows this diagnostics line verbatim; useful to mirror while developing.

`"idle"` · `"no token — manual count only"` · `"loading web app…"` · `"seeded — opening card…"`
· `"captured App Check token"` · `"native: 3/9"` · `"web: 3/9"` ·
`"native read <code> — using web fallback"` · `"native read failed — using web fallback"` ·
`"native read: no stamps_count field"` · `"web load failed: <error>"`

---

## 6. Network summary

| Call | When | Auth | Gated? |
|------|------|------|--------|
| `identitytoolkit…:signInWithPassword` | User taps Sign In | API key | No |
| `app.bugcoffee.com/app` (WebView) | Login / launch with a session, Option C only | seeded session | reCAPTCHA App Check (the page's own) |
| `firestore…/user-stamps/{uid}` | After a token is captured, Option C only | ID token + App Check token | Yes |

Nothing else leaves the device. No analytics, no crash reporting, no push registration.
