# XTOOLS Build Spec — RareImagery iOS (value-first funnel)

Self-contained build/handoff spec for continuing the **native SwiftUI** app. Read top-to-bottom before building. Source-of-truth pointers in §9. Everything here is verified against the repo as of 2026-06-25.

---

## 0. How to use this
You are building the **value-first pre-login funnel** in `~/Desktop/rareimagery-ios`. The flow is partly built (§4) and compiles. Pick a task from §6, follow the conventions (§7), build + verify (§8). **Respect the file-add constraint in §2 — it's the #1 way to break this project.**

## 1. Project facts
| | |
|---|---|
| Path | `~/Desktop/rareimagery-ios` |
| Xcode | 16+ (`objectVersion = 77`) · Swift 5.9 · iOS 17 target |
| UI | SwiftUI, `@Observable` / `@Environment`, dark-only (`.preferredColorScheme(.dark)`) |
| Scheme / target | `RareImagery` (also `RareImageryAPI`) |
| Package | SPM `Packages/RareImageryAPI` — the mobile↔BFF contract (models + repositories) |
| Bundle id | `com.rareimagery.studio` (⚠️ shared with the legacy Expo app; this native app is the one shipping per ADR-012) |
| Design tokens | `Theme/Colors.swift` (`AppColor`): bg `#0a0a0a`, surface `#171717`, accent `#7c3aed`, **cta `#FF6B00`**, textPrimary/Secondary, border. `Theme/Typography.swift` (`AppFont`). System fonts (Bebas/DM Sans not yet bundled). |

## 2. ⚠️ CRITICAL build constraints
- **Adding new `.swift` files requires editing `project.pbxproj`.** The project has `objectVersion 77` but **zero file-system-synchronized groups**, so every source file is an explicit reference (`PBXFileReference` + `PBXBuildFile` + group child + `PBXSourcesBuildPhase` entry). No `xcodeproj` Ruby gem is installed; `xcodegen` is present but the project is **not** xcodegen-based.
  - **Preferred:** put new code in **existing** files, or add files via **Xcode → Add Files…** (then they're registered). Only hand-edit `pbxproj` if you can do it cleanly (4 insertions per file, unique 24-hex IDs).
- **Always build before and after your change.** The project has had WIP brace breakage (a stray `}` in `CaptureView.swift` closed the struct early — already fixed). A broken sibling file fails the whole compile.
- **Compile gate:** `xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build` → must end `** BUILD SUCCEEDED **`.

## 3. The decision (what we're building)
**Value-first pre-login funnel** (founder decision; brain note `value-first-prelogin-funnel.md`, status `proposed`):
- Unauthenticated user: **capture → Grok valuation → result (the hook)** — no account required.
- **Account wall sits at the *sell* step.** Result screen's primary CTA = **"Create your store to sell"** → X-OAuth.
- Draft is created **storeless** and **adopted into a store at signup** (backend open-loop).
- Capture **modality (video vs stills) is deliberately undecided** — the app is PhotosUI stills today; the layout is named "Video Submission," so confirm before adding AVFoundation video.
- Native-SwiftUI pivot rationale: ADR-012 (`2026-06-25-adr-012-ios-native-swift-pivot.md`).

## 4. Current state (done + compiling)
- `State/AppState.swift` — **`useMocks` flag** (the single backend swap point; `true` = stubbed).
- `Capture/CaptureFlowView.swift` — `CaptureCoordinator.run` returns a **mock `ProductDraft`** when `useMocks` (no network); `DraftPreview` now has the **"Create your store to sell"** CTA, gated: signed-in → `QuickProductView` sheet; anonymous → `AuthCoordinator.signInWithX`.
- `Capture/CaptureView.swift` — fixed the pre-existing brace break.

## 5. Architecture & reuse map (don't reinvent)
**State (`State/`)**
- `AppState` (`@Observable`) — composition root; wires `RareImageryAPI` repositories + `AuthSession` + `CaptureSession`; owns `useMocks`; `bootstrap()` resolves prod → existing-anonymous → fresh-anonymous → signedOut.
- `AuthSession` — `status: .checking/.signedOut/.signedIn(MobileClaims)/.anonymous(AnonymousClaims)`; `isSignedIn`, `isAnonymous`, `freeUsesRemaining` (anon cap 3), `shouldShowSignUpReminder`.
- `CaptureSession` — `shots: [Shot]`, `selectedFavoriteIds` (≤2), `hero`, `intent: ProductIntent`, `phase: .idle/.picking/.working/.ready(ProductDraft)/.error`.

**Capture (`Capture/`)**
- `CaptureView` — PhotosUI picker + curation grid + intent picker + analyze button. Calls `CaptureCoordinator.run`.
- `CaptureFlowView` — wraps `CaptureView`, overlays `DraftPreview` on `.ready`. **The live result screen.**
- `CaptureCoordinator.run(state:)` — builds base64 data URLs, calls `productRepository.analyze(...)` (or `mockDraft()` when `useMocks`), sets `phase`.
- `ImageCompression.compressForUpload` / `toBase64DataURL`.

**Auth (`Auth/`)** — `SignInView`, `AuthCoordinator.signInWithX(state:)` (ASWebAuthenticationSession PKCE), `RareImageryAPI/AuthService` (JWT/keychain). Anonymous mint in `AppState.bootstrapAnonymous`.

**Sell** — `Product/QuickProductView(draft:heroImageData:)` (form; create-product call is still a TODO stub). ⚠️ `Capture/CaptureResultView` is **orphaned** (only in its own `#Preview`) — reconcile vs `DraftPreview` or delete.

**Routing** — `ContentView`: `.signedOut→SignInView`, `.signedIn→LivePreviewView`(if `!hasSeenLivePreview`)`→MainTabView`, `.anonymous→MainTabView`. `Tabs/MainTabView` → primarily **OnePageCreator** (merch-ideas→design→publish), which is a *different* pipeline from capture/valuation.

**Models (`RareImageryAPI/Models/`)** — `ProductDraft` (title, summary, description, category/condition enums, brand, `suggestedPriceLow/High: Decimal`, tags, confidence, `priceDisplay`), `ProductIntent`, `MobileClaims`, `AnonymousClaims`. `ProductRepository.analyze(dataURLs:intent:voiceTranscript:heroOnly:) -> VisionResult { ok, draft, model }`.

## 6. Remaining build tasks (priority order)
1. **Anonymous entry to the funnel** — capture→valuation→sell must be reachable for `.anonymous` users. Today the live result screen lives in the FirstProduct/onboarding path; `MainTabView` (anonymous landing) routes to OnePageCreator. Add a capture/valuation entry surfaced for `.anonymous`.
2. **Apply the layouts** — `Video Submission Flow.dc.html` + the Design-System/Design-Studio `.dc.html` (deliver to `~/Downloads`; not present yet). Map screens onto §5; refine `DraftPreview`/result to the design.
3. **Sell-screen reconcile** — keep `DraftPreview → QuickProductView`; delete or merge the orphaned `CaptureResultView`.
4. **Draft adoption after auth** — after X-OAuth from the funnel, resume to the sell sheet with the draft (today the root re-routes to `LivePreviewView` on auth; the draft persists in `CaptureSession`). Backend storeless-draft adoption is an open-loop.
5. **Video modality** — only if the layout/founder requires: AVFoundation capture + video upload (stills via PhotosUI today).
6. **Connect backend** — set `AppState.useMocks = false`; verify `analyze`/upload/publish against the BFF; remove mock.

## 7. Conventions (match exactly)
- SwiftUI `@Observable` + `@Environment(AppState.self) private var state`. Tokens only — `AppColor`/`AppFont`, never inline hex.
- All network via `RareImageryAPI` repositories through `AppState`. **Thin client** (no business logic on device). **Fail loud** (surface errors, never silently drop). Dark-only.
- **Prefer editing existing files** (§2). No new third-party SPM deps without a written reason.
- Stub-everything is the current phase: gate new network behind `useMocks` so screens run offline; connecting later = flip the flag.

## 8. Build & verify
```bash
cd ~/Desktop/rareimagery-ios
xcodebuild -list -project RareImagery.xcodeproj           # schemes: RareImagery, RareImageryAPI
xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build   # compile gate
# Run in a simulator:
xcodebuild -scheme RareImagery -destination 'platform=iOS Simulator,name=iPhone 16' build
# (or open RareImagery.xcodeproj in Xcode and Run)
```
**Stubbed happy path:** launch (lands `.anonymous`) → reach capture → pick 1–2 photos → Analyze → ~1s mock → result shows a value + **"Create your store to sell"** → anonymous taps it → X sign-in; signed-in taps it → `QuickProductView`. Live X-OAuth + real backend = the founder's test pass.

## 9. Source-of-truth pointers
- App rules: `~/Desktop/rareimagery-ios/CLAUDE.md`
- Brain: `~/rareimagery-brain/` — `memory/decisions/value-first-prelogin-funnel.md`, `2026-06-25-adr-012-ios-native-swift-pivot.md`, `memory/open-loops.md` (storeless-draft, unauth-Grok throttle [P1], anon-draft lifecycle)
- Design contract: `~/Projects/x-store-drupal/ai-rules/design.md`
- BFF contract: `RareImageryAPI` package sources; `~/Projects/x-store-next/src/app/api/**`
