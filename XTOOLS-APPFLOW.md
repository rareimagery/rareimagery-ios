# XTOOLS Build Spec — RareImagery App Flow (4 Acts, End-to-End)

Self-contained build/handoff spec for the **full App Flow** (`RareImagery App Flow.html` mockup, 2026-07-02). Companion to `XTOOLS-BUILD.md` (video funnel internals) and `VALUE-FIRST-OAUTH.md` (claim handoff) — read those for their subsystems; this doc is the map of the whole flow. Verified against branch `claude/nice-khayyam-034f5a` (PR #5 → `feat/circle-share-sheet`) as of 2026-07-02.

---

## 0. How to use this

You are building/continuing the **4-act app flow** in `~/Desktop/rareimagery-ios`. The flow is implemented end-to-end and clean-build verified (§3). Pick the next task from §5, follow the conventions in `XTOOLS-BUILD.md` §7, and **always regenerate + build via §6**.

## 1. Project facts (delta from XTOOLS-BUILD.md §1)

Everything in `XTOOLS-BUILD.md` §1–2 still holds: **xcodegen** (`project.yml` authoritative, `.xcodeproj` generated + gitignored, `Info.plist` generated, recursive sources), Xcode 16+ / Swift 5.9 / iOS 17 / SwiftUI `@Observable` / dark-only, SPM package `Packages/RareImageryAPI`, tokens in `Theme/` (`AppColor` / `AppFont`), mascot `Image("BudHound")`.

**Branch state:** work lives on `claude/nice-khayyam-034f5a`, based on `feat/circle-share-sheet`. ⚠️ The main checkout (`~/Desktop/rareimagery-ios`) may still hold the OAuth-claim WIP **uncommitted** in its working tree — identical content to commit `dfc3ddb`. Reconcile (discard or diff) before working there.

## 2. The flow — 4 acts, 11 mockup screens

Design source: `~/Downloads/RareImagery App Flow.html` — a **self-extracting bundle**. To read it, parse the `<script type="__bundler/template">` JSON string (the real HTML) and the `__bundler/manifest` (base64 assets, gzip when `compressed: true`). The flow rail:

| Act | Mockup screens | What happens |
|-----|----------------|--------------|
| **01 What's it worth?** | welcome → camera → voice → analyzing → valuation | Anonymous user films an item, narrates over the video, Grok values it. No account. |
| **02 Claim with X** | xauth → storecreated | One-tap X OAuth claims the valuation (`draft_token`) and provisions profile + store. |
| **03 First product** | camera → voice → analyzing → productdraft → productadded | Film something to sell; Grok drafts the listing. |
| **04 Launch your store** | storeeditor → launched | Arrange products, launch, "You're live." |

## 3. Current state (done + clean-build verified)

| Act | Screens | Implementation | Status |
|-----|---------|----------------|--------|
| 01 | welcome…valuation | `Funnel/` — `VideoSubmissionFunnelView` + `FunnelViewModel`; real AVFoundation capture (`Capture/VideoCaptureService`), on-device frame selection (`Capture/FrameSelector`) + STT (`Capture/SpeechService`). Entry: `ContentView` routes `.anonymous` users with `!hasSeenFunnel && !trialExhausted` into the funnel. | ✅ (`fb06312` + `dfc3ddb`) |
| 02 | xauth, storecreated | `FunnelResultView` "Claim this draft" → `AuthCoordinator.signInWithX(state:draftToken:)` (PKCE, `ASWebAuthenticationSession`); `pendingDraftToken` in Keychain; post-auth `LivePreviewView` = storecreated. Full contract: `VALUE-FIRST-OAUTH.md`. | ✅ (`dfc3ddb`) |
| 03 | productdraft, productadded | `Onboarding/FirstProduct/` wizard: `.setup → .capturing → .complete` (`FirstProductFlowView` + `FirstProductViewModel`); capture via `CaptureFlowView` sheet. | ✅ (pre-existing) |
| 04 | storeeditor, launched | **`Onboarding/FirstProduct/StoreEditorView.swift`** — new `.storeEditor` wizard phase. Banner/avatar via `LiveStorePreview`, ▲▼ reorder over in-session drafts, "Launch store" → launching → full-screen "You're live." → `onFinish` flips `hasSeenLivePreview`. | ✅ (`ac625c7`) |

**Deliberate skips (don't "fix" without a product decision):**
- **No separate voice-details screen** — voice is recorded *during* the video with rotating prompts (CAPTURE-CONTRACT.md §2). The mockup's standalone mic screen is superseded by that architecture.
- **No X sign-in CTA on welcome** — the account wall lives on the valuation result (XTOOLS-BUILD.md §3).
- **Launch is local-only** — no store-level launch endpoint exists; per-product `POST /api/products/[uuid]/publish` is a no-op today and in-session drafts carry **no uuid**. `StoreEditorView.launch()` has the `ponytail:` comment naming the upgrade path.

## 4. Key state & routing (where the flow decisions live)

- `State/AuthSession` — `.checking / .signedOut / .signedIn / .anonymous`; flags `hasSeenFunnel`, `hasSeenLivePreview`, `trialExhausted` (free-uses cap 3). All reset on sign-out.
- `ContentView` — the top-level router. Anonymous+fresh → funnel; signed-in+fresh → `LivePreviewView`; else → `MainTabView`.
- `State/AppState.useMocks` — **the whole backend switch** (currently `true`). Flip to `false` to hit `/api/vision/analyze` + raw-clip upload live. No view changes needed.
- Keychain keys incl. `pendingDraftToken`: `VALUE-FIRST-OAUTH.md` §4.

## 5. Remaining tasks (priority)

1. **Connect the backend** — flip `useMocks=false`; device-test the stubbed happy path in §6 against the live BFF (needs `X_CLIENT_ID` in `Configuration/*.xcconfig` and the redirect URI `rareimagery://auth/callback` on the X portal).
2. **Real launch** — when the BFF returns draft uuids (and/or a store-level launch endpoint lands), replace the sleep in `StoreEditorView.launch()` with per-product publish calls.
3. **Store editor persistence** — reorder is local-only (no product-list endpoint on the BFF; GET is by-uuid only, CLAUDE.md §3). Ask BFF for a mobile products-list + order PATCH before building sync.
4. **Claimed valuation in Act 4** — the editor lists only `FirstProductViewModel.createdDraft`; the Act-1 claimed valuation isn't threaded through post-auth yet (server claims it; client never re-fetches). Needs the products-list endpoint (task 3).
5. **Fonts** — OFL TTFs under `RareImagery/Resources/Fonts/` + `UIAppFonts` in `project.yml` (carried over from XTOOLS-BUILD.md §6.5).
6. **Reconcile legacy capture** — orphaned `CaptureResultView`/`QuickProductView` + `CaptureFlowView` stub CTA (XTOOLS-BUILD.md §6.6).

## 6. Build & verify

```bash
cd ~/Desktop/rareimagery-ios   # or the worktree
xcodegen generate
xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
Must end `** BUILD SUCCEEDED **`.

**Stubbed happy path (sim, `useMocks=true`):** launch (`.anonymous`) → funnel instructions → record (timer + rotating prompts) → processing → gold value card → "Claim this draft" → X sign-in → LivePreviewView ("store is ready") → "Create your first product" → wizard 1-2-3 → "Continue to your store" → store editor (reorder, "Launch store") → "You're live." → "Continue to Rare" → MainTabView. Real camera/STT/OAuth = device test.

## 7. Source-of-truth pointers

- This flow's screens: `RareImagery/Funnel/**`, `RareImagery/Onboarding/FirstProduct/**`, `RareImagery/Onboarding/LivePreviewView.swift`, `RareImagery/ContentView.swift`.
- Contracts: `CLAUDE.md` (BFF/auth rules), `CAPTURE-CONTRACT.md` (frames + transcript → `/api/vision/analyze`), `VALUE-FIRST-OAUTH.md` (draft claim), `XTOOLS-BUILD.md` (build workflow + funnel phases).
- Design: `~/Downloads/RareImagery App Flow.html` (bundled — see §2 for unpacking) + `~/rareimagery-brain/memory/design/video-submission-flow.dc.html`.

Update this file whenever an act's wiring or a §5 task changes.
