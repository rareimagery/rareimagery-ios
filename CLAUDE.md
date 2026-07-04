# CLAUDE.md — Agent Briefing for `rareimagery-ios`

> Snapshot of what's true on the **Next.js BFF + Drupal backend** as of
> 2026-05-21. Read this before touching anything that calls
> `https://www.rareimagery.net`. Update it whenever a contract here changes.

This iOS app is a **thin client**. All identity, payments, X / TikTok / Apple
OAuth, product writes, vision analysis, and commerce live on the server. The
phone never holds a Drupal credential and never signs a JWT.

---

## 1. System Map

```
┌───────────────────────────┐     mobile JWT (Bearer)      ┌──────────────────────────┐
│  rareimagery-ios (this)   │ ───────────────────────────► │  x-store-next (BFF)      │
│  SwiftUI · @Observable    │                              │  Next.js 15 · App Router │
│  ASWebAuthenticationSess. │ ◄─────── tokens ──────────── │  /api/mobile/*           │
│  Keychain token store     │                              │  /api/products/*         │
└───────────────────────────┘                              └──────────┬───────────────┘
                                                                      │ Basic auth +
                                                                      │ JSON:API / GraphQL
                                                                      ▼
                                                          ┌──────────────────────────┐
                                                          │  x-store-drupal          │
                                                          │  Drupal 10 + Commerce    │
                                                          │  x_profile · commerce_*  │
                                                          └──────────────────────────┘
```

**Repo locations (local dev):**
- BFF: `~/Desktop/x-store-next` (branch: `cursor/fix-health-aggregator-hairpin`)
- Drupal: `~/Desktop/x-store-drupal`
- Web (PWA): same repo as BFF

---

## 2. Mobile Auth — Source of Truth

### 2.1 JWT shape

Minted by `src/lib/api/mobile-jwt.ts` (BFF). Algorithm **HS256**, signed with
`MOBILE_JWT_SECRET` (≥ 32 chars). Issuer is always `rareimagery.net`.

Two audiences — **never interchangeable**:

| Audience          | TTL    | Use                                                     |
| ----------------- | ------ | ------------------------------------------------------- |
| `mobile-access`   | 7 d    | `Authorization: Bearer …` on every `/api/*` request     |
| `mobile-refresh`  | 60 d   | **Only** sent to `POST /api/mobile/auth/refresh`        |

Payload (both audiences carry the same identity):

```jsonc
{
  "sub":      "<x_profile UUID>",   // stable across X-handle changes
  "storeUuid":"<commerce_store UUID>",
  "slug":     "burns",              // storefront subdomain (no @)
  "handle":   "burns",              // current X handle (no @)
  "role":     "CREATOR",            // or "ADMIN"
  "aud":      "mobile-access" | "mobile-refresh",
  "iss":      "rareimagery.net",
  "iat":      …,
  "exp":      …
}
```

Decoded already in Swift: `Models/MobileClaims.swift`. **Do not** add a
signature-verifying decoder on-device. The server is the only verifier;
the client decodes for UX (display name, expiry countdown) only.

### 2.2 Endpoints

| Method | Path                              | Purpose                                       |
| ------ | --------------------------------- | --------------------------------------------- |
| POST   | `/api/mobile/auth/x/callback`     | Exchange PKCE `code` for token pair + creator |
| POST   | `/api/mobile/auth/refresh`        | Swap refresh token → new access+refresh pair  |
| POST   | `/api/mobile/auth/apple/callback` | **Stub** today (returns 501 placeholder)      |

#### `POST /api/mobile/auth/x/callback`

Request:

```json
{
  "code":         "string",
  "codeVerifier": "string",
  "redirectUri":  "rareimagery://auth/callback",
  "state":        "string (optional)"
}
```

Success response:

```jsonc
{
  "access_token":  "eyJ…",
  "refresh_token": "eyJ…",
  "expires_in":    604800,
  "token_type":    "Bearer",
  "creator": {
    "profileUuid":  "…",
    "storeUuid":    "…",
    "slug":         "burns",
    "handle":       "burns",
    "displayName":  "Burns",
    "avatarUrl":    "https://…",
    "role":         "CREATOR"
  }
}
```

Error envelope (used by **every** `/api/mobile/*` and `/api/products/*` route):

```json
{ "error": { "code": "STRING_CODE", "message": "Human readable." } }
```

Mobile-specific error codes:

- `BAD_REQUEST` (400)
- `X_TOKEN_EXCHANGE_FAILED` (401)
- `X_USER_FETCH_FAILED` (401)
- `DRUPAL_PROVISION_FAILED` (502)
- `SLUG_TAKEN` (422) — see §4 about the new blocked-names list
- `RESERVED_SLUG` (422)
- `SERVER_MISCONFIGURED` (500)
- `INTERNAL` (500)
- `TOKEN_MISSING` / `TOKEN_EXPIRED` / `TOKEN_INVALID` / `WRONG_AUDIENCE` (401)

### 2.3 Refresh strategy

`TokenRefresher` should:

1. Subtract 60 s from `exp` to refresh proactively.
2. On 401 with `TOKEN_EXPIRED`, do one refresh attempt, then retry the original
   request **once**. If the retry also 401s with `TOKEN_EXPIRED`/`WRONG_AUDIENCE`,
   drop the session and show `SignInView`.
3. Refresh tokens are stateless (no server-side revocation). If a device is lost,
   the only mitigation is rotating `MOBILE_JWT_SECRET` (logs every device out).
   A per-device revocation table is planned for Phase 2 — don't build a
   client-side revocation hint today.

---

## 3. Products API — Shared Web/Mobile Surface

Authentication is normalized by `src/lib/api/session-or-mobile-auth.ts` on the
BFF — the same handlers accept either a NextAuth web session cookie *or* a
mobile Bearer JWT. As a mobile caller, always send `Authorization: Bearer …`.

| Method | Path                                   | Purpose                                          |
| ------ | -------------------------------------- | ------------------------------------------------ |
| GET    | `/api/products/[uuid]`                 | Fetch one product (mobile `ProductDetail` shape) |
| PATCH  | `/api/products/[uuid]`                 | Update title / desc / price                      |
| DELETE | `/api/products/[uuid]`                 | Remove product                                   |
| POST   | `/api/products/[uuid]/publish`         | Flip to published (no-op today, stable handle)   |
| POST   | `/api/products/from-images`            | Multipart upload → Grok Vision → `ProductDraft`  |

**Auth model in Drupal:** `ProfileWriter::authorize()` matches the JWT's
`handle` claim against `field_x_handle` on the linked `x_profile`. There is **no
trust** that the BFF passed the right user — Drupal re-checks. If you see 403s
that look spurious, mismatched `slug` vs `handle` is the usual cause.

**Bundles probed for any product UUID:** `printful`, `physical`, `digital`.
You do not need to know the bundle on the client.

---

## 4. New: Subdomain Claim Rules (matters for both onboarding paths)

The web onboarding has a new claim flow. The mobile X-callback piggybacks on
the same Drupal `/api/creator/provision` endpoint, so the same rules apply.

### 4.1 $5 brand fee (web only, today)

Web onboarding now shows a **$5 one-time fee** to claim a subdomain ("Build
your brand for $5"). The Stripe integration is **not wired yet** — provisioning
runs immediately. The mobile X callback also provisions immediately without
charging. When Stripe lands, expect:

- A new `/api/mobile/onboarding/claim-intent` step that returns a Stripe
  PaymentIntent client secret.
- The X-callback response will start returning `pendingPaymentIntent` instead
  of full creator data; mobile will need a paywall card before the signed-in
  shell.

Don't pre-build a paywall UI yet; the API contract is not stable.

### 4.2 Three-layer slug validation (already live)

A slug must pass **all three** layers before Drupal accepts it:

1. **Reserved subdomains** — infra/platform names (e.g. `api`, `admin`, `www`,
   `console`, `onboarding`). List: `src/lib/reserved-subdomains.ts`.
2. **Blocked names** — ~200 famous people, brands, trademarks, platform
   confusion terms (e.g. `elonmusk`, `taylorswift`, `nike`, `chatgpt`,
   `official`, `verified`). List: `src/lib/blocked-names.ts`.
3. **Drupal uniqueness** — already-taken by another creator.

For mobile, the X username auto-claim path can hit (1) or (2) for X handles
that happen to collide with celebrities or brands. Mobile must handle:

- `422 RESERVED_SLUG` — show "@username is a reserved subdomain. Pick a different handle on X or contact support."
- `422 SLUG_TAKEN` — show "@username is already in use or restricted. Contact support if this is your verified handle."

Don't try to auto-mutate the slug client-side. Bounce to support.

### 4.3 If you need to check a slug before claim

`GET /api/stores/check-slug?slug=value` — requires an authenticated **web**
session today. **Not exposed to mobile.** If mobile ever needs pre-flight
validation (e.g. for an in-app rename screen), ask the BFF team to add a
mobile-auth variant under `/api/mobile/stores/check-slug` first.

---

## 5. Vision & Capture Pipeline

**Server-owned. Do not re-implement on-device.**

`POST /api/products/from-images` (multipart) is the only entry point. It:

1. Uploads images to Drupal media entities.
2. Calls Grok Vision (xAI) with a hero-image-first prompt (Phase G modular
   pipeline, Claude fallback). See commits `1aeb9a9`, `4f8f02a`,
   `f1aaed9` on the BFF for the prompt + taxonomy.
3. Returns a `ProductDraft` (Swift model already in
   `Models/ProductDraft.swift`).

**Hero-image rule:** the mobile filmstrip lets the user pick a hero shot. Send
that shot's index in the multipart form as `hero_index` (0-based). The server
only analyzes the hero — the rest are stored as gallery images. Do not send
the same image twice to "force" a re-analysis.

**Anti-pattern:** Don't try to call xAI / OpenAI / Claude directly from Swift.
The single-vendor xAI policy (`687da5a`) lives on the server precisely so we
can swap providers without an app update.

---

## 6. Features the Server Has That iOS Does NOT Wire Yet

These exist on the BFF but the iOS client doesn't consume them. Some may be
mobile-relevant later — flagged accordingly.

### 6.1 Rare Circle (social) — `eb0df2c`, `447be56`

- `GET  /api/social/circle/suggestions?limit=50&include_recent=true`
  Returns followed-on-X creators with mutual-follow + on-Rare flags.
- `GET  /api/social/circle` — list current pins for the logged-in creator.
- `PUT  /api/social/circle` — body `{ pins: ["handle1", "handle2"] }`. Server
  rejects non-mutual handles with `409` + `{ nonMutual: [...] }`.

**Mobile relevance: medium.** A "Pin your circle" screen would slot into
onboarding. Auth uses the web session today; we'll need to add mobile-JWT
support before iOS can call these.

### 6.2 Social Design Share — `dfda73d`, `6916453`

Creator-to-creator AI merch share + approval flow. Spec:
`x-store-next/docs/architecture/social-design-share.md`.

- `POST /api/social-shares` — create share to circle members.
- `POST /api/social-shares/[uuid]/responses` — recipient approve/decline.
- Notification fan-out via OneSignal (web push) + Drupal queue worker.

**Mobile relevance: high (eventually).** Push delivery to iOS will need an
APNs path (not OneSignal — Apple's certs and topic must route to the same
notification model). Don't start until product confirms the iOS push model.

### 6.3 Notifications & Push — `src/lib/notifications/`

- `POST /api/me/push-subscription` — currently web push (`endpoint`, `keys`).
- `GET  /api/notifications` — paginated feed.
- `POST /api/notifications/mark-all-read`
- `POST /api/notifications/[uuid]` — mark single read.

**Mobile path:** iOS will register an APNs device token; the BFF endpoint
needs a `platform: "ios"` field added. Not built yet — ping BFF team.

### 6.4 PWA Shell — `src/app/(pwa)/`

Mobile-web equivalent of the iOS app. Don't confuse the routes — the PWA
lives under `/circle`, `/create`, `/shares/[uuid]` and is a separate code
path. Native iOS calls the same `/api/*` endpoints, not these page routes.

### 6.5 Design Studio Publish — `src/app/api/design-studio/publish/route.ts`

Web-only publish path with in-memory rate limits (known tech debt — see
spec §10). **Mobile must not call this.** Use `/api/products/from-images`
+ `/api/products/[uuid]/publish` instead.

---

## 7. Identity & Drupal Contracts You'll Hit

These come up in error messages and Drupal-side rejections. Know them so you
can debug without grepping Drupal:

- **`x_profile`** — Drupal authoritative bundle for creator identity. Carries
  `field_x_handle`, `field_x_user_id`, `field_circle_pins`,
  `field_circle_pins_updated`, etc. The JWT `sub` is the **UUID** of this
  entity.
- **`commerce_store`** — One per creator, linked to the `x_profile` via
  `field_owner_profile`. The JWT `storeUuid` is this entity's UUID.
- **`x_user_profile`** — **STALE / KNOWN-BUG bundle** referenced in ~10 Next.js
  files. Returns 404 in production. Don't add new code that targets this name
  — always use `x_profile`. (Tracked in Appendix A of the social-shares spec.)
- **`field_circle_pins`** — JSON array of X usernames the creator has pinned.
  Lives on `x_profile`, **not** on the Drupal user entity.
- **`CRON_SECRET`** — Shared HMAC for any Drupal → Next.js callback. Mobile
  never sees this; don't try to mint or forward it.

---

## 8. Environment Configuration the Server Expects

Stuff the iOS dev needs to know exists, even if it's server-side:

| Env var                 | Where  | Purpose                                              |
| ----------------------- | ------ | ---------------------------------------------------- |
| `MOBILE_JWT_SECRET`     | Vercel | HMAC secret for mobile JWT (≥ 32 chars). Rotating logs out every device. |
| `X_CLIENT_ID` / `X_CLIENT_SECRET` | Vercel | X OAuth app credentials. **App also needs `X_CLIENT_ID`** in `Debug.xcconfig` / `Release.xcconfig` (must match). |
| `DRUPAL_API_URL`        | Vercel | BFF → Drupal base URL.                               |
| `NEXT_PUBLIC_BASE_DOMAIN` | Vercel | `rareimagery.net`. Used for `<slug>.<domain>` previews. |
| `STRIPE_*`              | Vercel | Not wired for mobile yet (see §4.1).                 |
| `ONESIGNAL_*`           | Vercel | Web push only today — mobile uses APNs (TBD).        |

X OAuth redirect URI on the X developer portal **must** be
`rareimagery://auth/callback` for the mobile flow to round-trip.

---

## 9. Anti-Patterns (Will Get Rolled Back in Code Review)

- ❌ Calling `https://api.twitter.com/*` directly from Swift.
- ❌ Writing to Drupal JSON:API / GraphQL directly from Swift.
- ❌ Verifying mobile JWT signatures on-device. Decoding for display ✓, verifying ✗.
- ❌ Re-implementing Grok Vision, Claude, or any LLM call client-side.
- ❌ Persisting refresh tokens anywhere except the iOS Keychain (`KeychainStore`).
- ❌ Calling `/api/design-studio/publish` from mobile (web-only, in-memory rate limited).
- ❌ Targeting the `x_user_profile` bundle name. Always `x_profile`.
- ❌ Storing the user's X access token on-device. The server keeps it; mobile
  has no X-on-behalf-of surface in v1.
- ❌ Hardcoding `rareimagery.net` URLs. Use `APIConfiguration.baseURL`.
- ❌ Combine. We're async/await only.
- ❌ Third-party reactive libs (TCA, Redux, RxSwift). We're `@Observable`.

---

## 10. Recent BFF Commits That Mobile Should Track

(Branch: `cursor/fix-health-aggregator-hairpin`, last updated 2026-05-21.)

| SHA       | Subject                                                           | Mobile Impact |
| --------- | ----------------------------------------------------------------- | ------------- |
| `6d27ac8` | fix(types): `Set<string>` annotation on `ALL_BLOCKED`             | None (build fix). |
| `d636efd` | feat(onboarding): floating followed-users bar, $5 brand fee, blocked names | §4 — slug claim rules tightened. |
| `1102f56` | fix(types): restore X API v2 types                                | None. |
| `6916453` | docs(architecture): expand `design_share` field schema            | Reference for future Social Design Share work. |
| `447be56` | feat(onboarding): Rare Circle picker flow                         | §6.1. |
| `eb0df2c` | feat(social): circle suggestions + pin management APIs            | §6.1. |
| `dfda73d` | docs: corrected Social Design Share architecture spec             | §6.2. |
| `e266e24` | fix(health): invoke sub-route handlers in-process                 | None. |
| `b3cbd30` | feat(mobile-auth): `/api/products/[uuid]` CRUD                    | §3 — already wired in `ProductRepository`. |
| `1544279` | feat(mobile-auth): refresh endpoint                               | §2.2 — wired. |
| `f1d6108` | feat(mobile-auth): X OAuth PKCE callback                          | §2.2 — wired. |
| `e9fabc6` | feat(mobile-auth): JWT helper + Bearer middleware                 | Foundation for §2 and §3. |
| `08586f7` | feat(api): stub Apple Sign-In mobile callback                     | §2.2 — endpoint exists, returns 501. Wire when product wants Apple ID flow. |

---

## 11. Where to Add New Surface

When the iOS app needs a new endpoint, the convention is:

- **Mobile-only** → `src/app/api/mobile/<area>/route.ts` using
  `verifyMobileToken(token, "mobile-access")` directly.
- **Shared web+mobile** → `src/app/api/<area>/route.ts` using
  `requireSessionOrMobile(req)` from `src/lib/api/session-or-mobile-auth.ts`.
  Returns a normalized `{ profileUuid, storeUuid, handle, slug, role }`
  envelope so the handler doesn't branch.

Always:

- Return errors in `{ error: { code, message } }` (see §2.2).
- Send `Cache-Control: no-store` on auth-bearing reads.
- Let Drupal re-authorize. Never trust the JWT as the sole permission check.

---

## 12. Quick Reference: Files to Re-Read When a Contract Drifts

BFF:

- `src/lib/api/mobile-jwt.ts` — JWT shape, audiences, errors.
- `src/lib/api/session-or-mobile-auth.ts` — shared auth normalizer.
- `src/app/api/mobile/**/*.ts` — mobile-only endpoints.
- `src/app/api/products/**/*.ts` — shared product CRUD.
- `src/lib/reserved-subdomains.ts` + `src/lib/blocked-names.ts` — slug rules.
- `docs/architecture/social-design-share.md` — future creator-to-creator
  share spec.

Drupal:

- `web/modules/custom/rareimagery_graphql/src/Service/CommerceWriter.php`
- `web/modules/custom/x_creator_sync/src/Controller/XImportController.php`
- `x-store-drupal/docs/architecture/creator-platform-model.md` — target
  layered model (`creator` + `platform_account`) the backend is migrating
  toward. Don't bake assumptions about current entity names; check this doc
  first.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
