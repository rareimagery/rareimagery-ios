# Plan: Phase 3 — Video + Voice Capture → Grok (hybrid) + the Grok handoff doc

## Context
Real on-device **video + audio capture** for the Video Submission Flow, feeding **Grok** for valuation. Grounded in the verified Grok contract: **Grok Vision = images only (≤4 base64 JPEG data URLs, ≤1024px server target) + text — no video/audio**; the existing `POST /api/v1/vision/analyze` already accepts `imageUrls` + `voiceTranscript` + a `source:"photo"|"video"` tag. Founder decision: **Hybrid** — reduce on-device to frames+transcript for an *instant* valuation (reuse the existing endpoint; **no new valuation backend**), AND upload the **raw clip** async (off the critical path) for the listing / re-analysis / future multimodal Grok. "Captured correctly" = framing guidance during capture **+ on-device frame-quality selection** so Grok receives sharp, diverse stills.

## ⭐ Primary deliverable — `CAPTURE-CONTRACT.md` (hand to the Grok/backend side)
A standalone capture→Grok data contract. Sections:
1. **Capture (iOS produces):** portrait `.mov`, H.264, ~720–1080p, ≤~30s, AAC audio; framing brackets + min-duration guidance.
2. **On-device reduction:** *frames* — sample candidates (`AVAssetImageGenerator`), score **sharpness** (Laplacian variance) + **diversity** (feature-print distance), keep ≤4, compress ≤1280px JPEG 0.85 → base64 data URLs; *voice* — `SFSpeechRecognizer` on-device → `voiceTranscript` (≤1000 chars).
3. **Valuation handoff (existing Grok path):** `POST /api/v1/vision/analyze` `{ imageUrls:[≤4 data URLs], voiceTranscript, source:"video", heroOnly:false, productIntent }` → `VisionResult{ ok, draft:ProductDraft, model, confidence }`. Precedence: voice > visible text > visual inference. Rate limit 30/hr/user; Bearer JWT.
4. **Raw-video retention (async, new):** `POST /api/mobile/upload-video` (multipart, Bearer) → `{ video_id, url }`; link to the draft; retention/expiry policy (esp. anonymous drafts).
5. **Gaps to close on the Grok/backend side (explicit asks):**
   - Add **`rarity` (0–10)**, **`insights: string[]`**, and a single **`suggestedPrice`** to `ProductDraft`/`VisionResult` — the result screen shows Rarity + suggested list price + 3 insights, which the current schema lacks (client uses a local `FunnelValuation` placeholder until then).
   - A **video-frame-aware system prompt**: tell Grok these are stills from a quick handheld video (not studio photos) so condition/quality grading is fair; honor `source:"video"`.
   - Confirm multi-frame (`heroOnly:false`) valuation uses 3–4 frames well.
   - Stand up the **upload-video endpoint + draft-linking**, and the **unauthenticated-Grok throttle** (open loop) — capture is available pre-login.
6. **Rationale + privacy/cost:** hybrid = instant cheap valuation (small frames+text payload) + raw retention; **no raw A/V on the valuation path**; raw clip uploaded separately under a retention policy.

> The `.md` lives at `rareimagery-ios/CAPTURE-CONTRACT.md` (with the capture code; easy to share) and is mirrored as a pointer in the brain `memory/design/`.

## Phase 3 implementation (each step compiles; AV/STT verified on device)
1. **`Capture/VideoCaptureService.swift`** — `AVCaptureSession` (video+audio) → `AVCaptureMovieFileOutput` (temp `.mov`); `AVCaptureVideoPreviewLayer`; start/stop, live duration, max-duration cap; camera+mic permission gating.
2. **`Capture/FrameSelector.swift`** — `AVAssetImageGenerator` samples N candidates → sharpness (Laplacian variance via vImage/CIFilter) + diversity (`VNGenerateImageFeaturePrintRequest`) → pick ≤4 → `ImageCompression.toBase64DataURL` → data URLs.
3. **`Capture/SpeechService.swift`** — `SFSpeechRecognizer` (on-device) transcribes the clip audio → `voiceTranscript`; add `NSSpeechRecognitionUsageDescription` to `project.yml`.
4. **`RareImageryAPI` `VideoUploadRepository`** — typed `POST /api/mobile/upload-video` client; **stub behind `useMocks`** until the backend endpoint exists; fired async (never blocks the result).
5. **Wire `FunnelViewModel`** — replace the mock recorder: real record → on stop: extract frames + transcribe → `ProductRepository.analyze(imageUrls:…, voiceTranscript:…, source:"video", heroOnly:false)` → map `VisionResult` → `FunnelValuation` → Result; kick off raw upload async. Add a `source` param to `ProductRepository.analyze` (endpoint already accepts it).
6. **`Funnel/FunnelRecordView`** — swap the mock viewfinder for the real `AVCaptureVideoPreviewLayer` (`UIViewRepresentable`), keeping the design's gold brackets / REC timer / rotating prompts / Bud shutter.

## Files
- **New:** `Capture/VideoCaptureService.swift`, `Capture/FrameSelector.swift`, `Capture/SpeechService.swift`, `Packages/RareImageryAPI/.../VideoUploadRepository.swift` (+ request/response models), **`CAPTURE-CONTRACT.md`**.
- **Edit:** `Funnel/FunnelView.swift` (real recorder in `FunnelViewModel`), `Funnel/FunnelRecordView.swift` (real preview), `Packages/RareImageryAPI/.../ProductRepository.swift` (+`source`), `project.yml` (speech perm) → `xcodegen generate`.

## Reuse
`ImageCompression` (frame compress + data URLs), `ProductRepository.analyze` (valuation — reused, +`source`), the existing `/api/v1/vision/analyze` + `VisionResult`/`ProductDraft`, `AuthSession`/Bearer + `apiFetch`, the Phase-2 funnel screens, `AppColor`/`AppFont`.

## Open flags
- **`rarity`/`insights`/`suggestedPrice`** missing from `ProductDraft` → result screen uses placeholders until the backend adds them (in `CAPTURE-CONTRACT.md`).
- **`upload-video` endpoint is backend-owned** → client stubbed via `useMocks`.
- **AV/STT need a device** → I verify compile + sim UI; record/transcribe is your device test.
- **Entry still unwired** (anonymous → funnel) — separate task, needs the routing WIP coordination.
- Fonts (TTFs) still pending (separate).

## Verification
- `cd ~/Desktop/rareimagery-ios && xcodegen generate && xcodebuild -scheme RareImagery -destination 'generic/platform=iOS Simulator' -configuration Debug build` → **BUILD SUCCEEDED**.
- **Device:** record a product clip → on-device sharp frames + transcript → `analyze` returns a real `VisionResult` → Result shows the real valuation. Confirm via a network proxy that **only frames+text** hit `/api/v1/vision/analyze` (no raw A/V), `source:"video"` + `heroOnly:false` present; raw clip uploads async (stubbed) without blocking the result.

## Execution note (this pass)
- **Build the Grok-independent parts now:** `VideoCaptureService` (AVFoundation video+audio), `FrameSelector` (sharpness + diversity), `SpeechService` (on-device STT), and the `analyze()` wiring (`source:"video"`, `heroOnly:false`) + the real `AVCaptureVideoPreviewLayer` in `FunnelRecordView`.
- **Stub** `VideoUploadRepository` (raw-clip upload) and the `rarity`/`insights`/`suggestedPrice` mapping behind `useMocks` until Grok answers `CAPTURE-CONTRACT.md` §7.
- **Also save** this plan to `rareimagery-ios/Plans/Phase-3-Video-Voice-Capture-Plan.md` (versioned copy for the team / Grok).
- `CAPTURE-CONTRACT.md` already exists (committed `79af300`) — do not regenerate.
