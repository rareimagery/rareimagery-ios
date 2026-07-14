# iOS Regression Investigation — 2026-07-13

## Summary

The app did **not** revert to old source code in git. The working tree is on `main` at `ca9ad9e`, pushed to `origin/main`. What looks like a “very old version” on device is almost certainly a **configuration + auth-path regression**: missing local xcconfig overrides and new SignIn gating from the Drupal client commits (`bed427d`–`f999ff4`).

**Screenshot symptom (IMG_8235):** TestFlight build shows legacy `Continue with X` and error:

> Configuration error: X OAuth Client ID is not set…

That error is thrown by `AuthService` when `X_CLIENT_ID` is still a placeholder — not because pre-Bud UI code returned.

---

## What was undone (this session)

All **uncommitted** local edits were restored to match `ca9ad9e` (`git restore`):

| File | Reverted changes |
|------|------------------|
| `RareImagery/Tabs/MainTabView.swift` | Tab bar rename (Stores / My Products / Settings), home tab user name, scroll clearance, delete `onDeleted` wiring |
| `RareImagery/Tabs/FriendsTabView.swift` | Nav title "Stores" |
| `RareImagery/Product/ProductEditView.swift` | Delete bundle param, scroll `contentMargins`, error surfacing |
| `RareImagery/Product/ProductDetailView.swift` | Buy button scroll `contentMargins` |
| `Packages/.../ProductRepository.swift` | `delete(uuid:bundle:)` |
| `Packages/.../APIClient.swift` | `buildRequest` → `resolveAccessToken()` |

**BFF** (`x-store-next`): uncommitted DELETE handler changes to `src/app/api/products/[uuid]/route.ts` also restored.

**Still on `main` (not reverted):** three pushed commits below.

---

## Commits still on `main` (pushed 2026-07-13)

| SHA | Message | Impact |
|-----|---------|--------|
| `bed427d` | feat(api): wire direct Drupal OAuth, JSON:API, capture, and voice audio | **Auth UI**, `AppState`/`AuthSession`, `SignInView` Drupal gate, `AuthManager`, large API package additions |
| `f999ff4` | feat(api): add remaining Drupal client sources and tests | **Release.xcconfig** URL change, `OAUTH_CLIENT_ID` placeholder, remaining package files |
| `ca9ad9e` | feat(products): edit delete/add photos and Path C voice confirmation | `ProductEditView`, `SpokenConfirmation`, `appendImages` |

Last known-good merge before this stack: `ab8d6ff` (build 1017 / sales dashboard).

---

## Root cause analysis

### 1. Missing local xcconfig (primary)

Checked on iMac:

```
Configuration/Debug.local.xcconfig   → MISSING
Configuration/Release.local.xcconfig → MISSING
```

Committed defaults:

```xcconfig
// Debug.xcconfig
API_BASE_URL = http://localhost:3000
X_CLIENT_ID = REPLACE_ME_WITH_X_CLIENT_ID
OAUTH_CLIENT_ID = VERIFY-CONSUMER-UUID

// Release.xcconfig
API_BASE_URL = https://rareimagery.net
X_CLIENT_ID = REPLACE_ME_WITH_X_CLIENT_ID
OAUTH_CLIENT_ID = VERIFY-CONSUMER-UUID
```

Previous TestFlight builds likely embedded a **real** `X_CLIENT_ID` from `Release.local.xcconfig` at archive time. Rebuilding without that file bakes placeholders into the binary → sign-in breaks.

### 2. SignInView auth-path change (`bed427d`)

`SignInView` now branches on `configuration.isOAuthClientConfigured`:

- If `OAUTH_CLIENT_ID` is real → primary button is Drupal OAuth (`Sign in`)
- If placeholder → falls back to **legacy X OAuth** (`Continue with X`)

With placeholders for **both** IDs, the UI matches the old X button, but tapping it hits `AuthService`’s `invalidConfiguration` guard → red error in screenshot.

This is **new behavior** since `bed427d`, not a git checkout of old `SignInView.swift`.

### 3. Release URL change (`f999ff4`)

```diff
- API_BASE_URL = https://www.rareimagery.net
+ API_BASE_URL = https://rareimagery.net
```

Intentional per Drupal canon; unlikely to cause the sign-in screen alone, but worth noting for API routing tests.

### 4. Debug builds point at localhost

`Debug.xcconfig` targets `http://localhost:3000`. Device/simulator Debug runs without `Debug.local.xcconfig` cannot reach a local BFF unless tunneled — separate from TestFlight but affects Xcode Run.

### 5. What did **not** cause this

- Uncommitted tab-bar / scroll / delete fixes (reverted; never committed)
- `safeAreaInset` experiments on product screens (were only in uncommitted work)
- Git reset or branch switch — `main` is clean at `ca9ad9e`, synced with `origin/main`

---

## File-level change inventory (`ab8d6ff` → `ca9ad9e`)

42 files, +3068 / −55 lines. High-signal groups:

### Configuration
- `Configuration/Debug.xcconfig` — added `OAUTH_CLIENT_ID` placeholder
- `Configuration/Release.xcconfig` — `www` dropped, `OAUTH_CLIENT_ID` added
- `Configuration/Debug.local.xcconfig.example` — Drupal OAuth instructions

### Auth / session
- `RareImagery/Auth/SignInView.swift` — Drupal vs X primary button
- `RareImagery/Auth/AuthCoordinator.swift` — `signInWithDrupal`
- `RareImagery/State/AppState.swift` — `AuthManager` wiring, token provider
- `RareImagery/State/AuthSession.swift` — OAuth token application
- `Packages/.../Auth/AuthManager.swift` (new)
- `Packages/.../Auth/JWTDecoder.swift` — Drupal payload decode

### API package (new Drupal path)
- `APIClient.swift`, `APIConfiguration.swift`, `APIEnvironment.swift`
- `CaptureRepository`, `MediaUploadRepository`, JSON:API models
- `VoiceTokenClient`, `VideoPosterExtractor`
- 39+ new tests

### App features (committed)
- `ProductEditView.swift` — photos, delete, save/publish
- `SpokenConfirmation.swift` + `FunnelView.swift` call site
- `VoiceAudioEngine.swift`, `JSONAPIProductsDebugView.swift`

---

## Recovery options

### Fast fix (keep commits, restore sign-in)

1. Copy `Configuration/Debug.local.xcconfig.example` → `Debug.local.xcconfig`
2. Create `Configuration/Release.local.xcconfig` with production values:

```xcconfig
X_CLIENT_ID = <real X OAuth client id>
OAUTH_CLIENT_ID = <drupal consumer uuid when ready>
API_BASE_URL = https://rareimagery.net
```

3. Clean build folder, re-archive for TestFlight
4. Until Drupal consumer exists, **must** have real `X_CLIENT_ID` for legacy path

### Full rollback (discard Drupal client stack)

```bash
cd ~/dev/rareimagery-ios
git revert ca9ad9e f999ff4 bed427d   # or reset to ab8d6ff if unpushed policy allows
```

Then restore `Release.local.xcconfig` and rebuild. Only if product decision is to pause i1–i5 until Drupal Tasks 2–5 land.

### Middle path

Revert only `SignInView` / auth gating to always use X when `OAUTH_CLIENT_ID` unset **without** removing package work — requires a small targeted commit.

---

## Verification checklist

- [ ] `Release.local.xcconfig` exists on archive machine with real `X_CLIENT_ID`
- [ ] TestFlight build shows Bud home tab + modern nav (not just sign-in fix)
- [ ] Sign-in completes against `https://rareimagery.net`
- [ ] Products tab loads after auth
- [ ] Compare `CFBundleVersion` in build vs expected (1017+ )

---

## Session log (uncommitted work now discarded)

| Time (approx) | Change | Status |
|---------------|--------|--------|
| Tab bar | Friends→Stores, Products→My Products, Profile→Settings, Shop capitalized, user name on home tab | Reverted |
| Scroll | `contentMargins` on ProductEdit/Detail; removed `safeAreaInset` action bars | Reverted |
| Delete | `delete(uuid:bundle:)`, BFF JSON:API delete path, CommerceWriter variation cleanup on VPS | iOS/BFF local reverted; VPS patch remains |
| APIClient | `buildRequest` uses `resolveAccessToken()` | Reverted |

---

## Open questions

1. Was TestFlight 1017 built from `ab8d6ff` with `Release.local.xcconfig` present, and today’s build from `ca9ad9e` without it?
2. Is the device running a **new** local Xcode build (Debug → localhost) vs an old TF binary?
3. Should Release builds fail at compile time when `X_CLIENT_ID` is still `REPLACE_ME` (guard in `project.yml` / build phase)?

---

*Generated 2026-07-13 after restoring uncommitted session changes. Repo state: `main` @ `ca9ad9e`, clean working tree.*
