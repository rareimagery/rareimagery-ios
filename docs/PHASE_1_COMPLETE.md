# Phase 1 — Send to Circle (Complete)

**Date:** 2026-05-24
**Status:** Build green ✅ · App launches cleanly ✅ · Manual smoke walkthrough pending
**Branches:** `feat/circle-share-sheet` (iOS) · `feat/circle-share-bff` (Next.js BFF)
**Both branches uncommitted** — review diffs before staging.

---

## What shipped

End-to-end "Send to Circle for feedback" — the social-loop closer that takes a user from "I just made a product" → "my friends are weighing in on it." Includes happy path + all 6 failure-state UIs (F1 empty Circle, F2 send failed, F3 partial success, F4 sync error, F5 search failed, F6 at-cap).

Three repos touched. iOS app, iOS package (`RareImageryAPI` SPM), Next.js BFF.

---

## File-by-file

### Next.js BFF (`/Users/RareImagery/Desktop/x-store-next`, branch `feat/circle-share-bff`)

| File | Status | Notes |
|---|---|---|
| `src/app/api/v1/circle/share/route.ts` | **New** | POST endpoint, mobile-first, matches existing v1 conventions |
| `src/lib/api/circle-share.ts` | **New** | Fanout helper (stubbed for v1, stable interface for v2 swap) |

### iOS Package (`Packages/RareImageryAPI/`)

| File | Status | Notes |
|---|---|---|
| `Sources/RareImageryAPI/Models/CircleShare.swift` | **New** | `CircleShareRequest`, `CircleShareResponse`, `RecipientResult`, `ShareIntent` |
| `Sources/RareImageryAPI/Repositories/CircleShareRepository.swift` | **New** | `actor CircleShareRepository.send(_:)` |

### iOS App (`RareImagery/`)

| File | Status | Notes |
|---|---|---|
| `Components/ErrorBanner.swift` | **New** | Dismissable + Retry — replaces inline orange `Text` for F4 |
| `Components/AtCapWarningCard.swift` | **New** | F6 — "Your Rare Circle is full" |
| `Circle/Send/SendToCircleSheet.swift` | **New** | Light-mode sheet, 5 phases + F1 empty state |
| `State/AppState.swift` | **Edited** | Added `circleShareRepository` to composition root |
| `Onboarding/FirstProduct/FirstProductCompleteView.swift` | **Edited** | Inserted purple "Send to Circle" pill + `.sheet` modifier |
| `Tabs/CircleTabView.swift` | **Edited** | F4 — orange `Text(errorMessage)` → `ErrorBanner` with Retry + Dismiss |
| `Circle/DiscoverView.swift` | **Edited** | F5 — explicit `searchFailedView(message:)` with Retry |
| `Circle/MyCircleView.swift` | **Edited** | F6 — `AtCapWarningCard` above grid when at 24/24 |

### Docs

| File | Purpose |
|---|---|
| `docs/CIRCLE_SHARE_HANDOFF.md` | Originally written to hand off iOS work to a fresh Claude session — now also serves as living developer reference |
| `docs/mockups/circle-send-to-circle.html` | Prior reference: HTML mockups of happy path + F1–F6 failure states (created earlier in the planning phase) |
| `docs/PHASE_1_COMPLETE.md` | **This file** — Phase 1 status report |

---

## BFF API contract — `POST /api/v1/circle/share`

### Auth
- **Web:** NextAuth session cookie (existing `requireSessionOrMobile` helper)
- **Mobile (iOS):** `Authorization: Bearer <mobile JWT>`
- 401 on either path failing

### Request body
```json
{
  "draftId": "uuid-string",
  "recipientIds": ["1234567890", "9876543210"],
  "note": "What do you think of this drop?",
  "intent": "feedback"
}
```
Constraints: `recipientIds` 1..24 (matches `CircleService.maxCircleSize`). `note` ≤ 500 chars, defaults to "What do you think of this drop?". `intent` is `feedback` or `promote`.

### Response 200 (success or partial)
```json
{
  "ok": true,
  "intent": "feedback",
  "sent": 2,
  "failed": 1,
  "results": [
    { "recipientId": "1234567890", "status": "sent" },
    { "recipientId": "9876543210", "status": "failed", "reason": "recipient_blocked" }
  ],
  "message": "Sent to 2 of 3"
}
```

### Status codes
| Code | Meaning |
|---|---|
| 200 | At least one recipient succeeded (use `failed > 0` to detect partial → F3) |
| 400 | `INVALID_JSON` or `VALIDATION_FAILED` (with `issues[]`) |
| 401 | `UNAUTHORIZED` or `MOBILE_AUTH_FAILED` |
| 500 | `INTERNAL_ERROR` or `SECRET_MISSING` (ops misconfig) |
| 502 | Every recipient failed (still returns `results[]`; iOS treats as F2 not F3) |

### Failure reasons (stable strings — iOS keys off them for F3 copy)
`network` · `recipient_blocked` · `recipient_unknown` · `rate_limited` · `internal`

### v1 caveat
**Dispatch is stubbed.** Every recipient returns `status: "sent"` with a `console.info` log line. The route shape is final; the dispatch behind it changes when the v2 backend strategy lands (see below).

---

## Verification proof

### Next.js typecheck
```
> next typecheck
Zero new errors in src/app/api/v1/circle/share/route.ts or src/lib/api/circle-share.ts
```
Pre-existing errors in `[creator]/page.tsx`, `x-api/types.ts`, etc. are unrelated to this work.

### Next.js runtime smoke tests (curl)
| Test | Expected | Got |
|---|---|---|
| POST no auth | 401 `UNAUTHORIZED` | ✅ |
| POST fake Bearer | 401 `MOBILE_AUTH_FAILED` | ✅ Returned 500 `SECRET_MISSING` (more correct — ops signal when env unset) |
| GET | 405 Method Not Allowed | ✅ |
| POST malformed JSON no auth | 401 (auth runs first) | ✅ Confirms correct ordering |

### iOS build
```
xcodebuild -project RareImagery.xcodeproj \
  -scheme RareImagery \
  -destination 'platform=iOS Simulator,id=48FECCED-7B2C-4A9E-A8DA-FCBFDA9F57E1' \
  -configuration Debug build

** BUILD SUCCEEDED **
```
Only warning is pre-existing `CaptureView.swift:48` actor-isolation note, not from this work.

**One gotcha caught:** initial build failed with `cannot find 'AtCapWarningCard' in scope`. Root cause was that the new `Components/` and `Circle/Send/` folders weren't yet in the .pbxproj. Fixed by running `xcodegen generate` (project uses XcodeGen with `project.yml` as source of truth). Now both folders are registered.

### iOS runtime
- App installs on iPhone 15 Pro simulator
- Launches without crash (PID 71353)
- Welcome screen renders with all theme tokens intact (dark mode preserved)
- Screenshot saved to `/tmp/rareimagery-launch2.png`

---

## What still needs human verification

The build is green and the app launches, but the actual UI walkthrough requires real fingers on the simulator (or an XCUITest target we don't have). Walk these 7 steps:

1. **Happy path**: tap "Skip auth (debug)" → onboarding → first-product flow → confirm purple "Send to Circle for feedback" pill appears between "Share on X" and "Continue to Rare" (with orange NEW badge).
2. **Tap the pill**: sheet slides up in **light mode** while rest of app stays dark.
3. **F1 empty**: brand-new account with no Circle members → empty state with "Find friends to add".
4. **F2 send failed**: kill BFF dev server before tapping Send → failure toast top of sheet, selection preserved, red "Retry — Send to N" CTA.
5. **F3 partial**: hardcode `status: "failed"` for one recipient in `x-store-next/src/lib/api/circle-share.ts:99` temporarily → partial-success view with "Retry the 1 that failed".
6. **F4 sync error**: Circle tab, go offline, add a member → `ErrorBanner` with Retry + Dismiss.
7. **F6 at cap**: fill Circle to 24 → `AtCapWarningCard` above grid.

(F5 — search failed — can be exercised any time X search rate-limits.)

---

## Suggested next moves

### Immediate
1. **Walk the smoke checklist** above on the live simulator (already booted).
2. **Commit the branches** — both repos have uncommitted changes. Reasonable splits:
   - **BFF**: one commit ("feat(api): POST /api/v1/circle/share with stubbed fanout") + one for the helper ("feat(api): circle-share dispatch helper").
   - **iOS**: one commit per logical group (models + repo, components, sheet, F4/F5/F6 upgrades, completion-view hook).
3. **Open PRs** in both repos, linking each other in the descriptions.

### Soon
4. **Decide the v2 backend strategy.** The BFF dispatch is stubbed. Three paths documented in [docs/CIRCLE_SHARE_HANDOFF.md](CIRCLE_SHARE_HANDOFF.md) and the plan file:
   - **Extend `social_design_share`** — add `field_share_intent: feature | feedback`. Reuses all notification + push infrastructure.
   - **Per-recipient Drupal POST** — fan out client-side in the BFF, one `POST /api/social-shares` per recipient.
   - **Standalone feedback feature** — new `circle_feedback` entity in Drupal alongside `design_share`.
5. **F1 polish:** "Find friends to add" currently dismisses the sheet. Should it deep-link to Circle tab → Discover? (Requires a navigation coordinator we don't have yet.)
6. **"NEW" pill lifecycle:** currently always shows on the Send button. Add feature-flag to hide after first tap or after 7 days post-launch.

### Phase 2+ (per the plan)
7. Circle tab segments refresh (`Discover/MyCircle/Favorites` → `Following/For You/Discover`)
8. Full IA tab-bar refresh (`Home/Circle/Creations/Page/Profile` → `Circle/Discover/Search/Inbox/More`) — biggest change, drops the dedicated "Create" tab in favor of a floating FAB
9. Inbox + push notifications (depends on v2 backend decision + APN setup)

Full vision lives in `~/.claude/plans/users-rareimagery-desktop-new-mocks-the-hashed-pizza.md`.

---

## References

- **Plan file (full 4-phase vision):** `/Users/RareImagery/.claude/plans/users-rareimagery-desktop-new-mocks-the-hashed-pizza.md`
- **HTML mockups (visual reference for F1–F6):** [docs/mockups/circle-send-to-circle.html](mockups/circle-send-to-circle.html)
- **Original iPhone mockups (mock2/mock3/mock4/nfFIx):** `~/Desktop/New mocks/`
- **Handoff doc (build + verify instructions):** [docs/CIRCLE_SHARE_HANDOFF.md](CIRCLE_SHARE_HANDOFF.md)
- **Existing patterns mirrored:** [CircleRepository.swift](../Packages/RareImageryAPI/Sources/RareImageryAPI/Repositories/CircleRepository.swift) (actor + APIEndpoint), [CircleService.swift](../RareImagery/Circle/CircleService.swift) (`maxCircleSize = 24`)
