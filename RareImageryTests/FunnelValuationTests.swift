import XCTest
import RareImageryAPI
@testable import RareImagery

final class FunnelValuationTests: XCTestCase {

    private func draft(
        title: String = "Test Item",
        suggestedPriceLow: Decimal? = nil,
        suggestedPriceHigh: Decimal? = nil,
        tags: [String]? = nil,
        confidence: Double? = nil,
        estimatedValue: ProductDraft.EstimatedValue? = nil,
        category: ProductCategory? = nil,
        condition: ProductCondition? = nil
    ) -> ProductDraft {
        ProductDraft(
            title: title,
            category: category,
            condition: condition,
            suggestedPriceLow: suggestedPriceLow,
            suggestedPriceHigh: suggestedPriceHigh,
            tags: tags,
            confidence: confidence,
            estimatedValue: estimatedValue
        )
    }

    // MARK: - Price band

    func testUsesTopLevelEstimatedValueBand() {
        let result = VisionResult(
            ok: true,
            draft: draft(suggestedPriceLow: 50, suggestedPriceHigh: 90),
            estimatedValue: ProductDraft.EstimatedValue(low: 120, high: 180)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.valueLow, 120)
        XCTAssertEqual(v.valueHigh, 180)
        XCTAssertEqual(v.suggested, 150)
    }

    func testDoesNotMixEstimatedLowWithDraftHigh() {
        let result = VisionResult(
            ok: true,
            draft: draft(suggestedPriceLow: 10, suggestedPriceHigh: 200),
            estimatedValue: ProductDraft.EstimatedValue(low: 120, high: nil)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.valueLow, 120)
        XCTAssertEqual(v.valueHigh, 120)
    }

    func testCoalescesHighOnlyBand() {
        let result = VisionResult(
            ok: true,
            draft: draft(),
            estimatedValue: ProductDraft.EstimatedValue(low: nil, high: 180)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.valueLow, 180)
        XCTAssertEqual(v.valueHigh, 180)
    }

    func testFallsBackToDraftSuggestedPrices() {
        let result = VisionResult(
            ok: true,
            draft: draft(suggestedPriceLow: 45, suggestedPriceHigh: 80)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.valueLow, 45)
        XCTAssertEqual(v.valueHigh, 80)
        XCTAssertEqual(v.suggested, 62)
    }

    func testPrefersSuggestedListPriceOverMidpoint() {
        let result = VisionResult(
            ok: true,
            draft: draft(suggestedPriceLow: 120, suggestedPriceHigh: 180),
            suggestedListPrice: 149
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.suggested, 149)
    }

    func testRoundsDecimalPricesToNearestDollar() {
        let result = VisionResult(
            ok: true,
            draft: draft(),
            estimatedValue: ProductDraft.EstimatedValue(low: Decimal(string: "119.60")!, high: Decimal(string: "180.40")!)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.valueLow, 120)
        XCTAssertEqual(v.valueHigh, 180)
    }

    // MARK: - Insights

    func testUsesTopLevelInsights() {
        let result = VisionResult(
            ok: true,
            draft: draft(tags: ["vintage"]),
            insights: ["Collector demand is strong.", "Minor cuff wear."]
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.insights, ["Collector demand is strong.", "Minor cuff wear."])
    }

    func testPrefersReasoningOverTagsWhenInsightsMissing() {
        let result = VisionResult(
            ok: true,
            draft: draft(tags: ["vintage", "leather"]),
            estimatedValue: ProductDraft.EstimatedValue(
                low: 100,
                high: 150,
                reasoning: "Late-80s moto cut with genuine leather."
            )
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.insights, ["Late-80s moto cut with genuine leather."])
    }

    func testPrependsReasoningToInsightsWhenDistinct() {
        let result = VisionResult(
            ok: true,
            draft: draft(),
            estimatedValue: ProductDraft.EstimatedValue(
                low: 100,
                high: 150,
                reasoning: "Basis: recent auction comps."
            ),
            insights: ["Strong collector demand."]
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.insights, ["Basis: recent auction comps.", "Strong collector demand."])
    }

    func testPlaceholderWhenNoInsightsAvailable() {
        let result = VisionResult(ok: true, draft: draft())
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.insights, [FunnelValuation.missingInsightsPlaceholder])
    }

    // MARK: - Confidence & rarity

    func testScalesFractionalConfidenceToPercent() {
        let result = VisionResult(ok: true, draft: draft(), confidence: 0.92)
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.confidence, 92)
    }

    func testAcceptsAlreadyPercentConfidence() {
        let result = VisionResult(ok: true, draft: draft(confidence: 86))
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.confidence, 86)
    }

    func testRarityNilWhenAbsent() {
        let result = VisionResult(ok: true, draft: draft())
        let v = FunnelValuation(from: result)
        XCTAssertNil(v.rarity)
    }

    func testMapsRarityWhenPresent() {
        let result = VisionResult(ok: true, draft: draft(), rarity: 7.4)
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.rarity, 7.4)
    }

    // MARK: - Metadata

    func testMapsCategoryAndConditionDisplayNames() {
        let result = VisionResult(
            ok: true,
            draft: draft(category: .apparel, condition: .worn)
        )
        let v = FunnelValuation(from: result)
        XCTAssertEqual(v.category, "Apparel")
        XCTAssertEqual(v.condition, "Worn")
    }

    func testLegacyDraftInitializer() {
        let v = FunnelValuation(from: draft(suggestedPriceLow: 28, suggestedPriceHigh: 42, confidence: 0.75))
        XCTAssertEqual(v.valueLow, 28)
        XCTAssertEqual(v.valueHigh, 42)
        XCTAssertEqual(v.confidence, 75)
    }

    // MARK: - Helpers

    func testResolvePriceBandHelperPrioritizesTopLevelEstimatedValue() {
        let result = VisionResult(
            ok: true,
            draft: draft(
                suggestedPriceLow: 1,
                suggestedPriceHigh: 2,
                estimatedValue: ProductDraft.EstimatedValue(low: 3, high: 4)
            ),
            estimatedValue: ProductDraft.EstimatedValue(low: 120, high: 180)
        )
        let band = FunnelValuation.resolvePriceBand(from: result)
        XCTAssertEqual(band.low, 120)
        XCTAssertEqual(band.high, 180)
    }
}