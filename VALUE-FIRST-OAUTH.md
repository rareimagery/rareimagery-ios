# VALUE-FIRST-OAUTH.md — Value-First Pre-Login X OAuth Claim Flow

> Snapshot of the **anonymous valuation → draft claim → X OAuth handoff** implemented in `rareimagery-ios`. Matches the CLAUDE.md architecture rules. Add this to Xcode project docs for the team.

This flow lets anonymous users get a Grok Vision valuation (draft) before signing in, then "claim" it by completing X OAuth PKCE. The `draft_token` bridges the anonymous session to the authenticated one.

---

## 1. Flow Overview

1. **Anonymous session**: User captures photo/video (Capture tab or Funnel video path). `useMocks=false`.
2. **Anonymous valuation**: `POST /api/vision/analyze` (Bearer `mobile-anonymous` JWT) or `POST /api/products/from-images` returns `ProductDraft` + `draftToken` (JWT claim for the draft). The video funnel uses `/api/vision/analyze` with `captureSource: "video"`.
3. **Store in Keychain**: `pendingDraftToken` persisted via `KeychainStore`.
4. **"Claim this draft" button**: Shown in `FunnelResultView` / `CaptureFlowView` result states when `draftToken` present and no active session.
5. **X OAuth PKCE**: `AuthCoordinator` → `ASWebAuthenticationSession` → X login → `rareimagery://auth/callback`.
6. **Token exchange with claim**: `POST /api/mobile/auth/x/callback` includes optional `draftToken`. Backend claims the draft into the new `x_profile`/`commerce_store`.
7. **Full session**: Access/refresh tokens stored; `pendingDraftToken` cleared; user lands in signed-in shell with claimed product.

Backend endpoints involved:
- `POST /api/mobile/auth/anonymous` — mints anonymous device session (rate-limited by `anonymousDeviceId`).
- `POST /api/vision/analyze` (anonymous Bearer) — returns `VisionResult` + `draft_token` for value-first claim.
- `POST /api/products/from-images` (anonymous Bearer) — alternate path; same `draft_token` shape.
- `POST /api/mobile/auth/x/callback` (with optional `draftToken`).
- `POST /api/mobile/drafts/claim` — explicit claim path (used internally by callback when `draftToken` present).

---

## 2. Key Swift Files & Responsibilities

| File | Role |
|------|------|
| `Packages/RareImageryAPI/Sources/RareImageryAPI/Auth/KeychainStore.swift` | Actor storing `pendingDraftToken` (`ri.pending_draft_token`). Also manages anonymous state keys. |
| `Packages/RareImageryAPI/Sources/RareImageryAPI/Auth/AuthService.swift` | Orchestrates sign-in, stores `draftToken` from vision result, passes it through X callback, clears on success. |
| `Packages/RareImageryAPI/Sources/RareImageryAPI/Repositories/AuthRepository.swift` | Network calls: anonymous auth, X callback (with optional `draftToken`), draft claim. |
| `RareImagery/Auth/AuthCoordinator.swift` | `ASWebAuthenticationSession` bridge; triggers callback URL handling in `RareImageryApp.swift`. |
| `Packages/RareImageryAPI/Sources/RareImageryAPI/Models/ProductDraft.swift` / `VisionResult.swift` | `draftToken: String?` field on the vision response model. |
| `RareImagery/Capture/CaptureFlowView.swift` | Shows "Claim this draft" CTA when anonymous valuation succeeds and no session. |
| `RareImagery/OnePageCreator/FunnelView.swift` & `FunnelResultView.swift` | Video funnel path; surfaces claim button on result screen with draft token. |

All new code follows thin-client rules from CLAUDE.md — no direct Drupal calls, JWT decoding only for UX, Keychain only for tokens.

---

## 3. API Endpoints & Request Shapes

### Anonymous valuation (no auth header)
```
POST /api/products/from-images
Content-Type: multipart/form-data
```
- `images[]` (files)
- `hero_index` (optional, 0-based)
- `anonymousDeviceId` (UUID from Keychain)

Response includes `ProductDraft` with `draftToken`.

### X OAuth callback (claim handoff)
```
POST /api/mobile/auth/x/callback
Content-Type: application/json
Authorization: (none — PKCE code exchange)
```

Request body (extended for claim):
```json
{
  "code": "string",
  "codeVerifier": "string",
  "redirectUri": "rareimagery://auth/callback",
  "state": "string (optional)",
  "draft_token": "eyJ... (optional, from pendingDraftToken — NOTE: snake_case, unlike the rest of this body; the route parses body.draft_token)"
}
```

Success: standard token pair + creator; backend claims draft server-side.

### Draft claim (internal, called by callback handler)
```
POST /api/mobile/drafts/claim
Authorization: Bearer <new access_token>
```
Body: `{ "draft_token": "..." }` (snake_case — matches the route's Zod schema)

---

## 4. Keychain Keys (KeychainStore.Key)

- `accessToken` = `"ri.access_token"`
- `refreshToken` = `"ri.refresh_token"`
- `accessTokenExpiry` = `"ri.access_token_expiry"`
- `anonymousDeviceId` = `"ri.anonymous_device_id"`
- `anonymousFreeUsesUsed` = `"ri.anonymous_free_uses_used"`
- `pendingDraftToken` = `"ri.pending_draft_token"` ← **new for this flow**

`pendingDraftToken` survives app restarts, cleared only on successful X sign-in + claim.

---

## 5. Testing in Xcode / Simulator / Device

**Prerequisites:**
- `useMocks = false` in `APIConfiguration` or debug settings.
- Valid `X_CLIENT_ID` in `Debug.xcconfig` / `Release.xcconfig`.
- `rareimagery://auth/callback` registered as redirect URI in X developer portal.

**Test steps:**
1. Fresh install or clear Keychain (simulator: delete app or use Keychain debugger).
2. Go to Capture tab → take photo (or Funnel video path).
3. Complete anonymous vision analysis → see valuation result + "Claim this draft" button.
4. Tap claim → X OAuth web sheet appears.
5. Complete X login → redirect back → tokens exchanged with `draftToken`.
6. Verify: session active, draft appears in user's products, `pendingDraftToken` removed from Keychain.

**Simulator tip:** `xcrun simctl keychain booted list` or use Xcode debug gauges to inspect Keychain items.

---

## 6. Error Codes to Expect

From `MobileErrorResponse` and backend contract (see CLAUDE.md §2.2):

- `TOKEN_EXPIRED`, `TOKEN_INVALID`, `WRONG_AUDIENCE` (401) — during claim after X callback.
- `DRAFT_TOKEN_EXPIRED` or `DRAFT_NOT_FOUND` (422/404) — claim attempted with stale/unknown `draftToken`.
- `X_TOKEN_EXCHANGE_FAILED` (401) — PKCE code invalid or X rate limit.
- `SLUG_TAKEN`, `RESERVED_SLUG` (422) — new creator handle collides (rare for X usernames).
- `DRUPAL_PROVISION_FAILED` (502) — backend provisioning error after X auth.

On claim failure, flow falls back to normal sign-in (draft remains claimable via support or re-valuation).

---

## 7. Owner / Deploy Prerequisites

- **BFF deploy**: Ensure `/api/mobile/auth/x/callback` accepts optional `draftToken` and `/api/mobile/drafts/claim` exists (see x-store-next recent commits).
- **Drupal**: `drush cr` after any schema or permission changes to `x_profile` / draft entities.
- **X developer portal**: Confirm redirect URI exactly `rareimagery://auth/callback` (case-sensitive, no trailing slash).
- **MOBILE_JWT_SECRET** rotation: invalidates all sessions — test claim flow after any secret change.

---

## 8. Troubleshooting

- **PKCE mismatch / "invalid_grant"**: Ensure `codeVerifier` stored before redirect and sent exactly once. `PKCE` helper in `RareImageryAPI/Auth/PKCE.swift` is the source.
- **Redirect URI not firing**: Check `Info.plist` (generated from `project.yml`) has `CFBundleURLTypes` with scheme `rareimagery`. Re-run `xcodegen generate`.
- **Expired draft_token**: Keychain item older than backend TTL (typically 24h). UI should hide "Claim" button or show "Valuation expired — capture again".
- **Anonymous counter not resetting**: `clearAnonymousState()` called only on successful X sign-in, not on sign-out.
- **Simulator Keychain persistence**: Sometimes flakes across Xcode restarts; delete app + clean build.
- **No "Claim this draft" button**: Check `AuthSession.status == .unauthenticated` and `draftToken != nil` in the result view model.

Update this file whenever the claim flow or backend contract changes. Cross-reference CLAUDE.md for overall mobile auth rules.