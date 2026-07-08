import Foundation
import RareImageryAPI

/// Local valuation model for the funnel result/hook screen. Mirrors the design's
/// fields (incl. rarity + insights, which the shared `ProductDraft` doesn't carry
/// yet). Phase 5 maps the real `/api/products/from-video` response into this.
struct FunnelValuation: Equatable {
    var title: String
    var valueLow: Int
    var valueHigh: Int
    var suggested: Int
    var category: String
    var condition: String
    /// 0–10 when the BFF emits it; `nil` hides the rarity pill.
    var rarity: Double?
    var confidence: Int     // 0–100
    var insights: [String]

    static let missingInsightsPlaceholder =
        "Analysis complete — sign in to refine your listing."

    static let mock = FunnelValuation(
        title: "Vintage Leather Moto Jacket",
        valueLow: 120, valueHigh: 180, suggested: 149,
        category: "Apparel · Outerwear", condition: "Good",
        rarity: 7.4, confidence: 92,
        insights: [
            "Genuine leather, late-80s cut — desirable with collectors.",
            "Minor wear at cuffs reads as patina, not damage.",
            "Best sold as a limited drop — Edition № 001 / 001.",
        ]
    )
}

extension FunnelValuation {
    /// Maps a backend `VisionResult` → funnel valuation. Prefers top-level
    /// `estimatedValue`, `insights`, and `rarity` when the BFF sends them.
    init(from result: VisionResult) {
        let draft = result.draft
        let estimatedValue = result.estimatedValue ?? draft.estimatedValue

        let band = Self.resolvePriceBand(from: result)
        var low = Self.decimalToUSD(band.low)
        var high = Self.decimalToUSD(band.high)
        if low == 0, high > 0 { low = high }
        if high == 0, low > 0 { high = low }

        let suggested = Self.resolveSuggestedPrice(
            listPrice: result.suggestedListPrice,
            low: low,
            high: high
        )

        self.init(
            title: draft.title,
            valueLow: low,
            valueHigh: high,
            suggested: suggested,
            category: draft.category?.displayName ?? draft.summary ?? "—",
            condition: draft.condition?.displayName ?? "—",
            rarity: result.rarity,
            confidence: Int(Self.normalizeConfidencePercent(
                result.confidence ?? draft.confidence ?? 0
            ).rounded()),
            insights: Self.resolveInsights(from: result, estimatedValue: estimatedValue)
        )
    }

    /// Legacy mapper when only a `ProductDraft` is available.
    init(from draft: ProductDraft) {
        self.init(from: VisionResult(ok: true, draft: draft))
    }

    // MARK: - Mapping helpers (tested via `init(from: VisionResult)`)

    static func resolvePriceBand(from result: VisionResult) -> (low: Decimal?, high: Decimal?) {
        let draft = result.draft

        if let top = result.estimatedValue, top.low != nil || top.high != nil {
            return (top.low, top.high)
        }
        if let nested = draft.estimatedValue, nested.low != nil || nested.high != nil {
            return (nested.low, nested.high)
        }
        if draft.suggestedPriceLow != nil || draft.suggestedPriceHigh != nil {
            return (draft.suggestedPriceLow, draft.suggestedPriceHigh)
        }
        if let band = result.suggestedPrice, band.low != nil || band.high != nil {
            return (band.low, band.high)
        }
        return (nil, nil)
    }

    static func resolveSuggestedPrice(listPrice: Decimal?, low: Int, high: Int) -> Int {
        let point = decimalToUSD(listPrice)
        if point > 0 { return point }
        if high > low { return (low + high) / 2 }
        return low
    }

    static func resolveInsights(
        from result: VisionResult,
        estimatedValue: ProductDraft.EstimatedValue?
    ) -> [String] {
        if let insights = result.insights, !insights.isEmpty {
            var list = insights
            if let reasoning = estimatedValue?.reasoning,
               !reasoning.isEmpty,
               !list.contains(reasoning) {
                list.insert(reasoning, at: 0)
            }
            return list
        }
        if let reasoning = estimatedValue?.reasoning, !reasoning.isEmpty {
            return [reasoning]
        }
        if let tags = result.draft.tags, !tags.isEmpty {
            return tags
        }
        return [missingInsightsPlaceholder]
    }

    static func normalizeConfidencePercent(_ value: Double) -> Double {
        value > 1 ? min(value, 100) : value * 100
    }

    static func decimalToUSD(_ value: Decimal?) -> Int {
        guard let value else { return 0 }
        var rounded = Decimal()
        var input = value
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}