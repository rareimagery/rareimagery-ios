# Send to Circle — Build Handoff

You're continuing Phase 1 of Rare Circle v2. Most of the heavy lifting is done — code is written and committed-ready. **Your job: build, fix any compile errors, manually verify, then finish 3 small UI edits.**

## TL;DR for the build loop

1. Open `/Users/RareImagery/Desktop/rareimagery-ios/RareImagery.xcodeproj` in Xcode (or `xcodebuild` from CLI).
2. Branch is already `feat/circle-share-sheet` — don't switch.
3. Build (⌘B). Fix any errors that surface — likely candidates listed under **Known compile risks** below.
4. Run on iPhone 15 Pro simulator (⌘R).
5. Walk through the happy path → confirm sheet shows in light mode.
6. Apply the 3 remaining edits (F4/F5/F6) listed under **Still to do** below.
7. Smoke-test all 6 failure states from the F-list.

---

## What's already built

### Next.js BFF (separate repo at `/Users/RareImagery/Desktop/x-store-next`, branch `feat/circle-share-bff`)

| File | Purpose |
|---|---|
| `src/app/api/v1/circle/share/route.ts` | POST endpoint, mobile-first, matches existing v1 conventions |
| `src/lib/api/circle-share.ts` | Fanout helper (stubbed for v1, stable interface for v2 swap) |

**Verified:** zero new TypeScript errors (pre-existing errors in `[creator]/page.tsx`, `x-api/types.ts` are unrelated). Runtime smoke tests pass: 401 on no auth, 405 on GET, correct error envelope shape.

### iOS Package (`Packages/RareImageryAPI/`)

| File | Purpose |
|---|---|
| `Sources/RareImageryAPI/Models/CircleShare.swift` | `CircleShareRequest`, `CircleShareResponse`, `RecipientResult`, `ShareIntent` |
| `Sources/RareImageryAPI/Repositories/CircleShareRepository.swift` | `actor CircleShareRepository.send(_:)` |

### iOS App (`RareImagery/`)

| File | Purpose |
|---|---|
| `Components/ErrorBanner.swift` (new) | Dismissable error banner — used for F4 |
| `Components/AtCapWarningCard.swift` (new) | At-cap warning card — used for F6 |
| `Circle/Send/SendToCircleSheet.swift` (new) | The big one. Light-mode sheet with all 5 phases (composing/sending/succeeded/failed/partial) + F1 empty state |
| `State/AppState.swift` (edited) | Added `circleShareRepository` to the composition root |
| `Onboarding/FirstProduct/FirstProductCompleteView.swift` (edited) | Inserted "Send to Circle" purple pill button between Share-on-X and Continue-to-Rare; added `.sheet` modifier |

---

## Still to do

### F4/F5/F6 — Done

All three failure-state upgrades have been applied:

- **F4** ✅ [RareImagery/Tabs/CircleTabView.swift](../RareImagery/Tabs/CircleTabView.swift) — orange `Text` swapped for `ErrorBanner` with Retry (calls `syncCircleToServer()`) + Dismiss (clears `errorMessage`).
- **F5** ✅ [RareImagery/Circle/DiscoverView.swift](../RareImagery/Circle/DiscoverView.swift) — new `searchFailedView(message:)` shown when `service.errorMessage` is set and `service.searchResults.isEmpty` during an active search. Retry button calls `service.searchUsers(query: searchText)`. Copy names the rate-limit possibility so users don't blame themselves for an X-side issue.
- **F6** ✅ [RareImagery/Circle/MyCircleView.swift](../RareImagery/Circle/MyCircleView.swift) — `AtCapWarningCard` inserted at the top of the populated `ScrollView` when `members.count >= CircleService.maxCircleSize`.

### Build verification

```bash
cd /Users/RareImagery/Desktop/rareimagery-ios
xcodebuild -scheme RareImagery -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build 2>&1 | tail -40
```

### Manual smoke (Simulator)

1. **Happy path**: complete first-product flow → tap "Send to Circle" → sheet opens in **light mode** (rest of app stays dark) → select 2–3 members → tap Send → succeeded view → auto-dismisses.
2. **F1 (empty Circle)**: sign in with a brand-new account → complete first-product flow → tap "Send to Circle" → see "Your Circle is empty" CTA.
3. **F2 (send failed)**: kill Next.js dev server before tapping Send → see failure toast, selection preserved.
4. **F3 (partial)**: when real fanout lands, force one recipient to fail → see per-recipient summary with "Retry the 1 that failed".
5. **F4 (sync error)**: in Circle tab, go offline, add a member → ErrorBanner appears with Retry.
6. **F5 (search failed)**: search a garbage handle while rate-limited → explicit error state with Retry.
7. **F6 (at-cap)**: fill Circle to 24 → at-cap card appears above grid.

---

## BFF API contract — POST /api/v1/circle/share

Live at the dev URL (default `http://localhost:3000` when running `next dev` in `x-store-next`).

**Request:**
```json
{
  "draftId": "uuid-string",
  "recipientIds": ["1234567890", "9876543210"],
  "note": "What do you think of this drop?",
  "intent": "feedback"
}
```

Constraints: `recipientIds` is 1..24 items (strings, max 64 chars each). `note` max 500. `intent` is `feedback` or `promote` (default `feedback`).

**Response (200, success or partial):**
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

**Errors:**
- `401 { error: { code: "UNAUTHORIZED" | "MOBILE_AUTH_FAILED", message } }`
- `400 { error: { code: "INVALID_JSON" | "VALIDATION_FAILED", message, issues?[] } }`
- `502 { ok: false, ... }` — every recipient failed (still has the results array, treated as F2 not F3)
- `500 { error: { code: "INTERNAL_ERROR" | "SECRET_MISSING", message } }`

Failure reasons (stable strings, used for F3 copy): `network`, `recipient_blocked`, `recipient_unknown`, `rate_limited`, `internal`.

**v1 caveat:** the BFF dispatch is **stubbed** — every recipient returns `status: "sent"` with a `console.info` log line. Partial-success (F3) won't actually trigger until real Drupal/notification dispatch lands. You can still test the F3 UI by hardcoding a failure into `src/lib/api/circle-share.ts` for the duration of testing.

---

## Known compile risks

These are the most likely places to need a fix-up:

1. **CircleShareRepository visibility** — the `actor` is `public`, but verify the new Models file is being picked up by SPM. If the package doesn't reload, in Xcode: File → Packages → Reset Package Caches.
2. **`@Query` in SendToCircleSheet** — requires the SwiftData container to be in scope when the sheet is presented. `FirstProductCompleteView` runs inside `FirstProductFlowView` which lives inside the main app's `.modelContainer`, so it should work — but if the sheet crashes on present with "no model container", check that `FirstProductFlowView` (or its parent) has `.modelContainer(for: [CircleMember.self, FavoriteItem.self])`.
3. **`Color(.systemBackground)` etc.** — these are UIKit-style system color initializers. They work in SwiftUI but require iOS 15+. If you hit "missing argument label", swap for `Color(uiColor: .systemBackground)`.
4. **`describe(_ error:)` in the sheet** — uses `NSError.localizedDescription`. If `APIError` has a richer error description method (look in `Packages/RareImageryAPI/Sources/RareImageryAPI/Client/APIError.swift`), prefer that.
5. **The "NEW" badge ZStack** — the `Capsule()` overlay might clip oddly on older device sizes. If so, wrap in `.fixedSize()` or move the badge to a separate `HStack` above the button.

---

## Where to find context if you need more

- **Plan file (full vision, all 4 phases)**: `/Users/RareImagery/.claude/plans/users-rareimagery-desktop-new-mocks-the-hashed-pizza.md`
- **HTML mockups (happy + F1-F6)**: [docs/mockups/circle-send-to-circle.html](mockups/circle-send-to-circle.html)
- **Reference iPhone mockups**: `~/Desktop/New mocks/` (mock2, mock3, mock4, nfFIx)
- **Existing patterns to mirror**:
  - [CircleRepository.swift](../Packages/RareImageryAPI/Sources/RareImageryAPI/Repositories/CircleRepository.swift) — the actor + APIEndpoint pattern
  - [CircleService.swift](../RareImagery/Circle/CircleService.swift) — `maxCircleSize = 24`, the error-message flow that F4 replaces

---

## When you're done

Mark these tasks complete (they live in the prior session's TaskList):

- [ ] **I5** — F4/F5/F6 upgrades to existing Circle views
- [ ] **I6** — iOS branch + xcodebuild + manual verification

Then either ship the branch as a PR or stage for review.

**Open questions to flag in the PR description:**
- Should the "NEW" pill on the Send button have a feature-flag for hide-after-first-tap?
- F1 "Find friends to add" currently just dismisses the sheet — should it deep-link to the Circle tab → Discover segment? (Requires a navigation coordinator we don't have yet.)
- The v1 BFF dispatch is stubbed — when do we decide between extend-Drupal-social_design_share / per-recipient-Drupal / standalone-feedback-feature? (See plan file for trade-offs.)
