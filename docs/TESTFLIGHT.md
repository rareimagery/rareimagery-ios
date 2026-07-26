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
   - **Environment variable:** `X_CLIENT_ID` = your X OAuth 2.0 Client ID (public, from [X developer portal](https://developer.x.com/en/portal/dashboard))
   - **Archive** post-action: **TestFlight Internal Testing**

[`ci_scripts/ci_post_clone.sh`](../ci_scripts/ci_post_clone.sh) runs `xcodegen generate` and writes `Configuration/Release.local.xcconfig` from `X_CLIENT_ID` when set.

### Trigger a build

- Push to the workflow branch, or
- Xcode → Product → Xcode Cloud → **Start Build**

Builds appear under **TestFlight → Builds** after the Archive post-action completes.

---

## Path B: Manual Archive (fallback)

### Prerequisites

- Xcode signed in with Apple ID on team `7ZGZLG2SRQ`
- `Configuration/Release.local.xcconfig` with real `X_CLIENT_ID` (gitignored; copy from [`Debug.local.xcconfig.example`](../Configuration/Debug.local.xcconfig.example))
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
xcodebuild -project RareImagery.xcodeproj -scheme RareImagery \
  -destination 'platform=iOS Simulator,name=iPhone 16' -configuration Debug build
```

Manual QA on TestFlight build:

- [ ] Sign in → kill app → reopen (stays signed in, not anonymous funnel)
- [ ] X OAuth completes on device
- [ ] OnePageCreator or funnel happy path reaches BFF

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| X sign-in fails on TestFlight | Set `X_CLIENT_ID` in Release.local.xcconfig or Xcode Cloud env. **Must match** production BFF `X_CLIENT_ID`. |
| "Sign-in temporarily unavailable" / `SERVER_MISCONFIGURED` | BFF missing `MOBILE_JWT_SECRET` or `X_CLIENT_SECRET`. Check `GET https://rareimagery.net/api/health/mobile-auth`. |
| `X_TOKEN_EXCHANGE_FAILED` | Register `rareimagery://auth/callback` in X developer portal for the same OAuth 2.0 app as `X_CLIENT_ID`. |
| `DRUPAL_PROVISION_FAILED` | Drupal unreachable from BFF or creator provision error — check BFF logs for `/api/creator/provision`. |
| Xcode Cloud: scheme not found | Use `RareImageryStudio`; shared scheme must be committed |
| OAuth redirect error | Register **`rareimagery://auth/callback`** exactly (no trailing slash) in [X developer portal](https://developer.x.com/en/portal/dashboard) on the same OAuth 2.0 app as BFF `X_CLIENT_ID`. Scopes: `tweet.read`, `users.read`, `offline.access`. |
| Build uses placeholder client ID | CI log should show `wrote Configuration/Release.local.xcconfig`. Compare first 8 chars of `X_CLIENT_ID` in Xcode Cloud vs BFF production env — must match character-for-character. |
| Sign-in error on TestFlight | Error card shows build, auth mode, client prefix, and BFF code. Tap **Copy details for support**. Console.app filter: `AuthCoordinator`, `AppState`, `AuthService`. |
| ADR-023 broker (future) | Also set `OAUTH_CLIENT_ID` in Xcode Cloud + BFF `DRUPAL_OAUTH_CLIENT_IDS`, `X_BFF_SHARED_SECRET`, nginx `/oauth/token` → Drupal. See `x-store-drupal/ai-memory/runbooks/ios-oauth-signin.md`. |

### Server smoke tests (before shipping TestFlight)

```bash
# BFF mobile auth config (legacy path must be healthy)
curl -sS https://rareimagery.net/api/health/mobile-auth | jq .

# Callback route exists (expect 400 BAD_REQUEST, not 404 HTML)
curl -sS -X POST https://rareimagery.net/api/mobile/auth/x/callback \
  -H 'Content-Type: application/json' -d '{}'
```
