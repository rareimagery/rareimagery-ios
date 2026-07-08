import Foundation
import Observation
import RareImageryAPI

/// State + coordination for the 3-screen first-product wizard plugged
/// into LivePreviewView's primary CTA.
///
/// Flow shape:
///
///   .setup     → Screen 1: product-type + style chips (chips drive
///                downstream UX bias; not persisted to Drupal yet)
///   .capturing → Screen 2: presents CaptureFlowView as a sheet, reads
///                state.capture.phase on dismiss, accepts the resulting
///                ProductDraft
///   .complete  → Screen 3: share-on-X + "Continue to Rare"
///
/// Persistence story (v1 — 2026-05-23):
///
///   Chip selections (`selectedProductTypes`, `selectedStyle`) are
///   LOCAL-ONLY. We use them to bias defaults the next time the user
///   opens TweakSheet / picks a color scheme — e.g., "Minimal" maps to
///   `.arctic`, "Bold" to `.cherry`, etc. No PATCH to Drupal tonight.
///
///   When Phase-N adds `field_product_intent` + `field_style_vibe` to
///   `x_profile`, extend OnboardingRepository.updateStore and PATCH from
///   acceptDraft (or on .complete advance). Until then, the bias lives
///   on this view-model only.
@Observable
@MainActor
final class FirstProductViewModel {

    /// Wizard step. Drives FirstProductFlowView's switch.
    enum Phase: Equatable {
        case setup
        case capturing
        case complete
        case storeEditor
    }

    // MARK: - Wizard state

    var phase: Phase = .setup

    /// Multi-select chips. Subset of the catalog the creator wants to
    /// focus on. Empty set is valid — user can advance without picking
    /// anything (the chips are a directional hint, not a gate).
    var selectedProductTypes: Set<String> = []

    /// Single-select chip — the creator's stated brand vibe. nil means
    /// "no preference"; downstream UX falls back to defaults.
    var selectedStyle: String?

    /// Populated after Screen 2's capture completes. Drives the result
    /// card on Screen 2 + the "almost done" header on Screen 3.
    var createdDraft: ProductDraft?

    /// Surfaced on Screen 2 when CaptureFlowView returns a `.failed`
    /// phase. Cleared when the user re-presents the capture sheet.
    var errorMessage: String?

    // MARK: - Catalog

    /// Stable chip catalogs — extracted as `static let` so tests +
    /// previews can compare against the same source of truth without
    /// duplicating strings.
    static let productTypeOptions: [String] = [
        "Merch",
        "Digital Products",
        "Art / Prints",
        "Apparel"
    ]

    static let styleOptions: [String] = [
        "Streetwear",
        "Minimal",
        "Bold",
        "Nostalgic",
        "Premium"
    ]

    // MARK: - Intents

    func toggleProductType(_ type: String) {
        if selectedProductTypes.contains(type) {
            selectedProductTypes.remove(type)
        } else {
            selectedProductTypes.insert(type)
        }
    }

    func selectStyle(_ style: String) {
        if selectedStyle == style {
            // Tap-to-deselect — gives the user an out if they tapped the
            // wrong one. Matches the iOS HIG pattern for single-select
            // chip groups.
            selectedStyle = nil
        } else {
            selectedStyle = style
        }
    }

    func advanceToCapture() {
        guard phase == .setup else { return }
        phase = .capturing
        errorMessage = nil
    }

    /// Called by FirstProductCaptureView after the capture sheet
    /// dismisses with a `.ready(draft)` phase. Mirrors how QuickProductView
    /// receives its draft today.
    func acceptDraft(_ draft: ProductDraft) {
        createdDraft = draft
        errorMessage = nil
    }

    /// Called when capture returns a `.error(message)` phase. Surfaces
    /// the failure on the result card so the user can retry without
    /// losing chip selections.
    func recordCaptureError(_ message: String) {
        errorMessage = message
        createdDraft = nil
    }

    func advanceToComplete() {
        guard createdDraft != nil else { return }
        phase = .complete
    }

    /// Act 4 of the app flow — "Continue to your store" on the complete
    /// screen routes into the store editor (arrange + launch).
    func advanceToStoreEditor() {
        guard phase == .complete else { return }
        phase = .storeEditor
    }

    /// Lets the user re-capture without losing their setup selections.
    /// Resets the draft + error so the result card re-hides; phase stays
    /// `.capturing` so Screen 2 keeps rendering.
    func resetCapture() {
        createdDraft = nil
        errorMessage = nil
    }
}
