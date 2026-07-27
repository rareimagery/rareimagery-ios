# TestFlight — Ship RareImagery iOS

Native SwiftUI app (`com.rareimagery.studio`). **Not Expo** — distribution is via Xcode + App Store Connect TestFlight.

| Property | Value |
|----------|-------|
| Bundle ID | `com.rareimagery.studio` |
| Team ID | `7ZGZLG2SRQ` |
| ASC App ID | `6771493728` |
| CI scheme | `RareImageryStudio` |
| Export plist | [`ExportOptions.plist`](../ExportOptions.plist) |

---

## Path A: Xcode Cloud (recommended)

### One-time setup (App Store Connect)

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → RareImagery.
2. **Xcode Cloud** (or Xcode → Product → Xcode Cloud → Manage Workflows).
3. Create or verify a workflow:
   - **Repository:** `rareimagery/rareimagery-ios`
   - **Branch:** `main` (merge PR first)
   - **Scheme:** `RareImageryStudio`
   - **Environment variables** (Xcode Cloud → Workflow → Environment):

     | Variable | Required | Source |
     |----------|----------|--------|
     | `X_CLIENT_ID` | Yes | [X developer portal](https://developer.x.com/en/portal/dashboard) OAuth 2.0 Client ID — **must match** BFF `X_CLIENT_ID` |
     | `OAUTH_CLIENT_ID` | Yes | Drupal Admin → Simple OAuth → RareImagery iOS consumer UUID — **must be in** BFF `DRUPAL_OAUTH_CLIENT_IDS` |
     | `GOOGLE_IOS_CLIENT_ID` | Yes (App Store 4.8) | Google Cloud → Credentials → iOS client for `com.rareimagery.studio` |
     | `GOOGLE_REVERSED_CLIENT_ID` | Yes | Google Cloud → iOS client → **URL scheme** (reversed ID, e.g. `com.googleusercontent.apps.1234567890-abcdef`). **No underscores** — RFC1738 rejects them. |

   - **Apple Developer:** App ID `com.rareimagery.studio` → enable **Sign in with Apple** capability (matches committed `RareImagery.entitlements`).

   - **Archive** post-action: **TestFlight Internal Testing**

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs `xcodegen generate` and writes `Configuration/Release.local.xcconfig` from the env vars above.

### Trigger a build

- Push to the workflow branch, or
- Xcode → Product → Xcode Cloud → **Start Build**

Builds appear under **TestFlight → Builds** after the Archive post-action completes.

---

## Path B: Manual Archive (fallback)

### Prerequisites

- Xcode signed in with Apple ID on team `7ZGZLG2SRQ`
- `Configuration/Release.local.xcconfig` with real auth IDs (gitignored; copy from [`Debug.local.xcconfig.example`](../Configuration/Debug.local.xcconfig.example)): `X_CLIENT_ID`, `OAUTH_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_REVERSED_CLIENT_ID`
- X app callback URL: `rareimagery://auth/callback`

### Steps

1. Open `RareImagery.xcodeproj` in Xcode.
2. Scheme **RareImagery**, destination **Any iOS Device (arm64)**.
3. **Product → Archive** (Release).
4. Organizer → **Distribute App** → **App Store Connect** → **Upload**.
5. Automatic signing, team `7ZGZLG2SRQ`.

### Install on device

1. App Store Connect → **TestFlight** → Internal Testing → add testers.
2. Install **TestFlight** on iPhone → accept invite → install RareImagery.

---

## Verify before shipping

```bash
swift test --package-path Packages/RareImageryAPI
xcodegen generate
xcodebuild -project RareImagery.xcodeproj -scheme RareImagery \
  -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

Manual QA on TestFlight build:

### Sign-in (multi-provider — Phase C/D)

- [ ] **Apple (new user):** Continue with Apple → slug picker → signed in → storefront slug saved
- [ ] **Apple (returning):** Sign out → Apple again → no slug picker, direct sign-in
- [ ] **Google (new user):** Continue with Google → slug picker → signed in
- [ ] **Google (returning):** Sign out → Google again → no slug picker
- [ ] **X regression:** Continue with X → broker path completes (Drupal session, not legacy JWT when `OAUTH_CLIENT_ID` set)
- [ ] **Session persist:** Kill app → reopen → still signed in
- [ ] **Refresh:** Wait near token expiry or force refresh → silent `/oauth/token` refresh

### General

- [ ] OnePageCreator or funnel happy path reaches BFF

---

## Multi-provider auth — server + BFF env (production)

Verify before TestFlight QA:

```bash
# BFF health (broker + legacy)
curl -sS https://rareimagery.net/api/health/mobile-auth | jq .

# Broker routes live (expect 400 validation JSON, not 502/404)
curl -sS -X POST https://rareimagery.net/api/auth/apple/exchange \
  -H 'Content-Type: application/json' \
  -d '{"client_id":"test","drupal_code_challenge":"'$(python3 -c 'print("A"*43)')'"}'

curl -sS -X POST https://rareimagery.net/api/auth/google/exchange \
  -H 'Content-Type: application/json' -d '{}'
```

**BFF production env (Vercel / VPS `.env.production`):**

| Variable | Value |
|----------|-------|
| `DRUPAL_OAUTH_CLIENT_IDS` | Comma-separated; includes iOS `OAUTH_CLIENT_ID` |
| `X_BFF_SHARED_SECRET` | ≥ 32 chars; matches Drupal mint-code gate |
| `APPLE_IOS_BUNDLE_ID` | `com.rareimagery.studio` |
| `GOOGLE_IOS_CLIENT_ID` | Same as iOS / Google Cloud iOS client |
| `X_CLIENT_ID` / `X_CLIENT_SECRET` | X OAuth app (X button + link-X) |

**Google Cloud Console checklist:**

1. OAuth consent screen configured
2. iOS client: bundle ID `com.rareimagery.studio`
3. Copy **Client ID** → `GOOGLE_IOS_CLIENT_ID`
4. Copy **iOS URL scheme** (reversed client ID) → `GOOGLE_REVERSED_CLIENT_ID` in Xcode Cloud

**Apple Developer checklist:**

1. App ID `com.rareimagery.studio` → Sign in with Apple enabled
2. Provisioning profile / Xcode Cloud signing picks up entitlement automatically after merge

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| X sign-in fails on TestFlight | Set `X_CLIENT_ID` in Release.local.xcconfig or Xcode Cloud env. **Must match** production BFF `X_CLIENT_ID`. |
| "Sign-in temporarily unavailable" / `SERVER_MISCONFIGURED` | BFF missing secrets or misconfigured broker. Check `GET https://rareimagery.net/api/health/mobile-auth`. |
| `X_TOKEN_EXCHANGE_FAILED` | Register `rareimagery://auth/callback` in X developer portal for the same OAuth 2.0 app as `X_CLIENT_ID`. |
| `DRUPAL_PROVISION_FAILED` | Drupal unreachable from BFF or creator provision error — check BFF logs for `/api/creator/provision`. |
| Xcode Cloud: scheme not found | Use `RareImageryStudio`; shared scheme must be committed |
| OAuth redirect error | Register **`rareimagery://auth/callback`** exactly (no trailing slash) in [X developer portal](https://developer.x.com/en/portal/dashboard). Scopes: `tweet.read`, `users.read`, `offline.access`. |
| Build uses placeholder client ID | CI log should show `wrote Configuration/Release.local.xcconfig`. Compare `X_CLIENT_ID` / `OAUTH_CLIENT_ID` in Xcode Cloud vs BFF production env. |
| Sign-in error on TestFlight | Error card shows build, auth mode, client prefix, and BFF code. Tap **Copy details for support**. Console.app filter: `AuthCoordinator`, `AppState`, `AuthService`. |
| `UNKNOWN_CLIENT` | iOS `OAUTH_CLIENT_ID` not listed in BFF `DRUPAL_OAUTH_CLIENT_IDS`. |
| Apple sign-in fails immediately | App ID missing Sign in with Apple capability; or BFF `APPLE_IOS_BUNDLE_ID` ≠ `com.rareimagery.studio`. |
| Google upload rejected: invalid URL scheme | `GOOGLE_REVERSED_CLIENT_ID` was placeholder (`REPLACE_ME` has underscores) or unset. Set real reversed client ID in Xcode Cloud — must match `[a-zA-Z0-9.+.-]+` only. |
| Slug picker loops / ticket expired | Identity ticket TTL is 10 min — restart Apple/Google sign-in if idle on slug screen. |
| `NEEDS_SLUG` then `SLUG_TAKEN` | Pick another slug; server validates reserved/blocked names at provision time. |
| Legacy JWT when broker expected | `OAUTH_CLIENT_ID` still placeholder in Release build — check CI log for `Release.local.xcconfig`. |

### Server smoke tests (legacy + broker)

```bash
curl -sS https://rareimagery.net/api/health/mobile-auth | jq .

curl -sS -X POST https://rareimagery.net/api/mobile/auth/x/callback \
  -H 'Content-Type: application/json' -d '{}'
# expect 400 JSON, not 404 HTML
```
