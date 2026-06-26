# Capture → Grok Data Contract — Video Submission Flow

**Audience:** the Grok / backend (BFF) team. **Owner of this doc:** iOS (`rareimagery-ios`).
**Status:** proposed (iOS Phase 3 in progress). **Updated:** 2026-06-25.

This defines exactly what the iOS app captures, how it's reduced, and the precise payloads exchanged with the backend so **Grok values a product correctly from a quick video + voice**. It also lists what we need **from** the Grok/backend side (§5).

---

## 0. TL;DR — the architecture (hybrid)
Grok Vision ingests **images + text only** (no video/audio). So:

1. **On-device, instant valuation path** — iOS records video+voice, then **reduces on-device** to a few sharp **frames** + a **voice transcript**, and calls the **existing** `POST /api/v1/vision/analyze` (`source:"video"`). Small payload, cheap, private (no raw A/V leaves the phone), works with Grok as-is. **No new valuation endpoint needed.**
2. **Async raw-clip retention path (new)** — separately and off the critical path, iOS uploads the **raw video** to storage for the eventual listing / re-analysis / future multimodal Grok.

```
record video+audio (.mov, on device)
   ├─► REDUCE on device ─► ≤4 sharp frames (JPEG data URLs) + voice transcript
   │        └─► POST /api/v1/vision/analyze {imageUrls, voiceTranscript, source:"video"} ─► Grok ─► VisionResult  (drives the result screen — fast)
   └─► (async, non-blocking) POST /api/mobile/upload-video (raw .mov) ─► {video_id,url} ─► linked to the draft at signup
```

**Privacy/cost:** the valuation path never sends raw audio or video — only ≤4 small JPEGs + ≤1000 chars of text. The raw clip is uploaded separately under a retention policy.

---

## 1. What iOS captures
| | |
|---|---|
| Container / codec | `.mov`, **H.264** (HEVC acceptable), portrait |
| Resolution | 720p–1080p (capped to keep clips small) |
| Duration | target 5–20s, hard cap ~30s |
| Audio | **AAC**, mono, recorded with the video (creator narrates) |
| Guidance ("captured correctly") | on-screen framing brackets, "keep the item in frame", min-duration nudge; **on-device frame-quality selection** discards blurry frames |

## 2. On-device reduction (iOS produces the Grok inputs)
**Frames (for Grok Vision):**
- Sample candidate frames across the clip (`AVAssetImageGenerator`).
- Score **sharpness** (Laplacian variance) and **diversity** (Vision feature-print distance); keep the **best ≤4**, distinct angles, product-centered.
- Compress each to **≤1280px long edge, JPEG q0.85** → `data:image/jpeg;base64,…` (matches the existing photo pipeline; server re-targets ~1024px).
- If no frame clears a sharpness floor → still send the best available and set the expectation that Grok may flag `blurry`/`needs_review`.

**Voice (for the transcript):**
- **On-device** `SFSpeechRecognizer` transcribes the clip's audio → `voiceTranscript` (trimmed to **≤1000 chars**). No audio leaves the device.

## 3. Valuation handoff — EXISTING endpoint (no change required to call it)
`POST /api/v1/vision/analyze` · Auth: **Bearer JWT** (mobile) or session · Rate limit: **30/hr/user**.

**Request**
```jsonc
{
  "imageUrls": ["data:image/jpeg;base64,<frame1>", "…up to 4…"],
  "voiceTranscript": "vintage Levi's denim jacket, small stain on the left cuff, from the 90s",
  "source": "video",          // tags the analysis; transcript suffixed [source:video]
  "heroOnly": false,          // analyze all provided frames, not just the first
  "productIntent": "resell"   // "resell" | "design_merch"
}
```
**Response** (`VisionResult`)
```jsonc
{
  "ok": true,
  "model": "grok-2-vision-1212",   // or claude-… (fallback) | "fallback"
  "confidence": 0.92,               // 0–1; <0.65 triggers Claude fallback server-side
  "processingTimeMs": 4200,
  "draft": {                        // ProductDraft (today)
    "title": "Vintage Leather Moto Jacket",
    "summary": "…", "description": "…",
    "category": "apparel", "condition": "good",
    "brand": "Levi's",
    "suggestedPriceLow": 120, "suggestedPriceHigh": 180,
    "tags": ["denim","vintage"], "handmade": false,
    "confidence": 0.92, "flags": []
  }
}
```
**Prompt precedence (confirmed):** `voiceTranscript` > visible text on the item > visual inference. The creator's spoken facts (brand/size/price/condition) are authoritative.

## 4. Raw-video retention — NEW (backend-owned)
Off the critical path; **never blocks the result screen**.
```jsonc
// POST /api/mobile/upload-video   (multipart/form-data, field "file"; Bearer JWT)
// → 200
{ "video_id": "uuid", "url": "https://…/video.mov" }
```
- **Linking:** the value-first funnel valuates **pre-login** and persists nothing until the **sell** step (X-OAuth → storeless-draft adoption). So the raw video should be **held against the anonymous device id** pre-login and **linked to the draft at draft-creation/adoption**. Backend to define the holding + linking.
- **Retention:** define expiry/cleanup, especially for anonymous clips that never convert (ties to the existing `anonymous-draft lifecycle` open loop).

## 5. What we need FROM the Grok / backend side (asks)
1. **Add to `ProductDraft`/`VisionResult`:** `rarity` (0–10), `insights: string[]` (≈3 short bullets), and a single `suggestedPrice` (USD). The result screen renders **Rarity x/10**, a **suggested list price**, and **3 insight bullets** — none of which exist in the schema today. *Until added, iOS shows placeholders (local `FunnelValuation`) for those three fields only.*
2. **Video-frame-aware prompt:** when `source:"video"`, tell Grok the images are **stills from a quick handheld video** (not studio photos) so it grades condition/quality fairly and leans on the voice transcript. Honor the `source` tag.
3. **Multi-frame quality:** confirm `heroOnly:false` with 3–4 frames meaningfully improves the read (angles/condition) vs a single hero.
4. **Stand up** `POST /api/mobile/upload-video` + the pre-login holding + draft-linking (§4).
5. **Unauthenticated-Grok throttle (priority-1 open loop):** capture is available pre-login; even though each payload is small (≤4 JPEGs + text), it's still a Grok call with no per-user anchor. Define the abuse/cost control (device token / IP / challenge / cheaper pre-login model).

## 6. Why this design
- **Reuses the proven valuation path** (`/api/v1/vision/analyze`) — zero new valuation backend; the `source:"video"` tag already exists.
- **Cheapest + fastest** read (small frames+text), which matters because capture is **pre-login / unauthenticated**.
- **Privacy-first:** raw audio/video never touch the valuation call; the raw clip is a separate, retention-governed upload.
- **Future-proof:** when a multimodal Grok can take video directly, the raw clip is already retained to feed it — no re-capture.

## 7. Open questions for the Grok/backend team
- OK to add the three `ProductDraft` fields (§5.1), or should the client derive rarity/insights from existing fields for now?
- Preferred raw-video transport: direct multipart to the BFF, or a signed-URL-to-storage handshake?
- Pre-login holding mechanism for the raw clip + the throttle (§5.5) — your call; iOS will conform.

---
*iOS side: frames + transcript are produced by `Capture/FrameSelector` + `Capture/SpeechService`; the valuation call is `ProductRepository.analyze(…, source:"video", heroOnly:false)`; raw upload is `VideoUploadRepository` (stubbed until §4 lands). See `XTOOLS-BUILD.md` for the build workflow.*
