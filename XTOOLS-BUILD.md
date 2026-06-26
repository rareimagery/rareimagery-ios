# XTOOLS Build Spec — RareImagery iOS (Video Submission Flow)

Self-contained build/handoff spec for the **native SwiftUI** app. Read top-to-bottom before building. Source-of-truth pointers in §9. Verified against the repo as of 2026-06-25.

---

## 0. How to use this
You are building the **value-first pre-login Video Submission Flow** in `~/Desktop/rareimagery-ios`. Phases 1–2 are done + committed (§4). Pick the next task from §6, follow the conventions (§7), and **always regenerate + build via §2/§8**.

## 1. Project facts
| | |
|---|---|
| Path | `~/Desktop/rareimagery-ios` |
| **Project gen** | **xcodegen** — `project.yml` is the source of truth; `RareImagery.xcodeproj` is **generated + gitignored**. See §2. |
| Toolchain | Xcode 16+ · Swift 5.9 · iOS 17 target · SwiftUI (`@Observable`/`@Environment`) · dark-only |
| Scheme / target | `RareImagery` · SPM package `Packages/RareImageryAPI` (mobile↔BFF contract) |
| Bundle id / team | `com.rareimagery.studio` · team `7ZGZLG2SRQ` (both in `project.yml`) |
| Brand tokens | `Theme/Colors.swift` (`AppColor`): brand `#7B2D8E`, gold `#D4AF37`, `vaultGradient` (`#561F62→#2C1033→#160D1A`), `foil`, `borderGold`, `success`; legacy `accent`→brand, `cta`→gold. |
| Type | `Theme/Typography.swift` (`AppFont`): `display`=Space Grotesk, `body`=Hanken Grotesk, `mono(_:)`=JetBrains Mono — **custom families with system fallback; TTFs not yet bundled** (§6). |
| Mascot | `Image("BudHound")` (asset catalog). |

## 2. ⚠️ The build workflow (xcodegen — read this)
- **`project.yml` is authoritative; the `.xcodeproj` is generated.** Never hand-edit `project.pbxproj` (it's regenerated + gitignored).
- **Adding files is free:** `sources: - path: RareImagery` is **recursive**, so any file you create under `RareImagery/**` is auto-included on the next generate. No per-file registration.
- **`Info.plist` is generated** from `project.yml` → `targets.RareImagery.info.properties`. So **permissions, URL schemes, and `UIAppFonts` go in `project.yml`**, not a hand-edited plist. (Camera/mic/photo usage strings already there.)
- **Always:** after creating files or editing `project.yml` →
  ```bash
  cd ~/Desktop/rareimagery-ios && xcodegen generate && \
  xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build
  ```
  must end `** BUILD SUCCEEDED **`.
- Project config (team, settings, deployment target) lives in `project.yml` + `Configuration/*.xcconfig`.

## 3. What we're building
**Value-first pre-login funnel** (brain: `value-first-prelogin-funnel.md`, ADR-012 native pivot). Founder decisions: **app-wide brand refresh** + **full video pipeline** (AVFoundation capture + audio, STT, `from-video` BFF). Design: `~/rareimagery-brain/memory/design/video-submission-flow.dc.html` (+ `…-budhound.png`).
4 screens: **Instructions → Record → Processing → Result**. Capture **video + voice**; rotating voice prompts; Grok valuation; result/hook with gold value card; **account wall at "Create your store to sell"** (X-OAuth); storeless draft adopted at signup (backend open-loop).

## 4. Current state (done + clean-build verified)
- **Phase 1 ✅ (`3eb7b8a`)** — app-wide brand refresh: `Theme/Colors.swift` (vault palette), `Theme/Typography.swift` (font families + fallback), `BudHound` asset.
- **Phase 2 ✅ (`e98a104`)** — `Funnel/` module: `VideoSubmissionFunnelView` + `FunnelViewModel` (mock record→recording→processing→result state machine) + `Instructions/Record/Processing/Result` screens, faithful to the design.
- **Not wired into navigation yet** — `ContentView`/`MainTabView` have other-agent routing WIP; the funnel compiles standalone but isn't presented. Entry wiring is task #1.

## 5. Architecture & reuse map
- **`Funnel/`** — the value-first flow (above). `FunnelViewModel` is `@Observable`; recorder is a mock (Phase 3 swaps real). `FunnelResultView` gates the sell CTA on `AppState.session.isSignedIn` → `AuthCoordinator.signInWithX`.
- **State (`State/`)** — `AppState` (`@Observable` root; wires `RareImageryAPI` repos + `AuthSession` + `CaptureSession`; **`useMocks` swap**). `AuthSession` (`.checking/.signedOut/.signedIn(MobileClaims)/.anonymous(AnonymousClaims)`; `isSignedIn`/`isAnonymous`/`freeUsesRemaining` cap 3). `CaptureSession` (`phase: .idle/.picking/.working/.ready(ProductDraft)/.error`).
- **Auth (`Auth/`)** — `SignInView`, `AuthCoordinator.signInWithX(state:)` (PKCE), `RareImageryAPI/AuthService`. Anonymous mint in `AppState.bootstrapAnonymous`.
- **Legacy capture (`Capture/`)** — the earlier photo path: `CaptureFlowView` (+ a stub value-first CTA from commit `a075e05`) and the **orphaned** `CaptureResultView`/`QuickProductView`. The **Funnel supersedes these for the value-first flow** — reconcile/remove (task).
- **Models (`RareImageryAPI`)** — `ProductDraft` (title/summary/price range/tags/confidence; no rarity/insights — the funnel uses a local `FunnelValuation`). `ProductRepository.analyze(dataURLs:intent:voiceTranscript:heroOnly:) -> VisionResult`.

## 6. Remaining tasks (priority)
1. **Wire the entry** — present `VideoSubmissionFunnelView` for `.anonymous` users (coordinate with the `ContentView`/`MainTabView` routing WIP; don't whole-file `git add` over it).
2. **Phase 3 — real capture:** `Capture/VideoCaptureService` (AVCaptureSession video+audio → temp `.mov`, preview layer, start/stop/duration). Replace `FunnelViewModel`'s mock recorder.
3. **Phase 4 — STT:** `Capture/SpeechService` (SFSpeechRecognizer, on-device). Add `NSSpeechRecognitionUsageDescription` to `project.yml` info.
4. **Phase 5 — `from-video`:** `RareImageryAPI` `VideoValuation*` (Codable) + repository → `POST /api/products/from-video` (proposed, backend-owned); upload + transcript. Map response → `FunnelValuation`. Flip `useMocks=false` to connect.
5. **Fonts:** add the OFL TTFs under `RareImagery/Resources/Fonts/` + `UIAppFonts` in `project.yml` → `xcodegen generate`.
6. **Reconcile legacy** — remove/merge orphaned `CaptureResultView`/`QuickProductView` + the `CaptureFlowView` stub CTA now that the Funnel exists.

## 7. Conventions
- **xcodegen first** (§2): files under `RareImagery/**`, config in `project.yml`, then `xcodegen generate`.
- SwiftUI `@Observable` + `@Environment(AppState.self)`. **Tokens only** (`AppColor`/`AppFont`), never inline hex. Thin client; fail loud; dark-only.
- All network via `RareImageryAPI` through `AppState`; gate new calls behind `useMocks`. No new third-party SPM deps without a written reason.

## 8. Build & verify
```bash
cd ~/Desktop/rareimagery-ios
xcodegen generate                                                                      # regenerate from project.yml
xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build   # compile gate
# device run (real camera/STT): xcodebuild ... -destination 'platform=iOS Simulator,name=iPhone 16' build, or open in Xcode
```
**Stubbed happy path (sim):** launch (`.anonymous`) → Instructions → tap Bud → recording (timer + rotating prompts) → tap Bud → processing → result (gold value card + "Create your store to sell") → anonymous taps CTA → X sign-in. AVFoundation capture + STT + live backend = device test pass.

## 9. Source-of-truth pointers
- App rules: `CLAUDE.md`. Design: `~/rareimagery-brain/memory/design/video-submission-flow.{dc.html,md}` + `…-budhound.png`.
- Brain: `~/rareimagery-brain/` — `value-first-prelogin-funnel.md`, `2026-06-25-adr-012-ios-native-swift-pivot.md`, `open-loops.md` (storeless-draft, unauth-Grok throttle [P1], anon-draft lifecycle).
- Design contract: `~/Projects/x-store-drupal/ai-rules/design.md`. BFF: `~/Projects/x-store-next/src/app/api/**`.
