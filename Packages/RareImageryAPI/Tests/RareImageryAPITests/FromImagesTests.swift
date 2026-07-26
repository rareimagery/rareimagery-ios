import XCTest
@testable import RareImageryAPI

/// Phase 4A — contract tests for `POST /api/products/from-images`.
/// The request must serialize to snake_case (via `APIEndpoint.json`), and the
/// snake_case response must decode through `JSONDecoder.rareImagery`.
final class FromImagesTests: XCTestCase {

    // MARK: Request encoding

    func testRequestEncodesSnakeCaseKeys() throws {
        let req = FromImagesRequest(
            imageUrls: ["data:image/jpeg;base64,AAAA"],
            heroOnly: false,
            voiceTranscript: "blue denim jacket",
            productIntent: "resell",
            storeUuid: "11111111-1111-1111-1111-111111111111",
            metadata: .init(source: "photo")
        )
        let endpoint = try APIEndpoint.json(
            path: "/api/products/from-images",
            method: .post,
            body: req
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(endpoint.body)) as? [String: Any]
        )

        // snake_case keys present, camelCase absent
        XCTAssertNotNil(json["image_urls"])
        XCTAssertNil(json["imageUrls"])
        XCTAssertEqual(json["hero_only"] as? Bool, false)
        XCTAssertEqual(json["voice_transcript"] as? String, "blue denim jacket")
        XCTAssertEqual(json["product_intent"] as? String, "resell")
        XCTAssertEqual(json["store_uuid"] as? String, "11111111-1111-1111-1111-111111111111")
        let metadata = try XCTUnwrap(json["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["source"] as? String, "photo")
    }

    // MARK: Response decoding

    func testResponseDecodesDraftId() throws {
        let data = Data("""
        {
          "draft_id": "abcd-1234-uuid",
          "draft": {
            "confidence": 0.86,
            "title": "Vintage Levi's Denim Jacket",
            "description": "Heavyweight denim, classic red tab.",
            "category": "apparel",
            "condition": "lightly_worn",
            "condition_notes": "light cuff wear",
            "specs": { "brand": "Levi's" },
            "suggested_price_usd": 62.5,
            "price_reasoning": "Range $45–$80 by condition.",
            "estimated_value": { "low": 45, "high": 80, "currency": "USD", "basis": "resale_market" },
            "tags": ["denim", "vintage"],
            "flags": { "appears_handmade": false }
          },
          "preview_image_url": "https://cdn.example/x.jpg",
          "processing_time_ms": 1200
        }
        """.utf8)

        let resp = try JSONDecoder.rareImagery.decode(FromImagesResponse.self, from: data)

        XCTAssertEqual(resp.draftId, "abcd-1234-uuid")
        XCTAssertEqual(resp.previewImageUrl, "https://cdn.example/x.jpg")
        XCTAssertEqual(resp.processingTimeMs, 1200)
        XCTAssertEqual(resp.draft.title, "Vintage Levi's Denim Jacket")
        XCTAssertEqual(resp.draft.suggestedPriceUsd, Decimal(string: "62.5"))
        XCTAssertEqual(resp.draft.conditionNotes, "light cuff wear")
        XCTAssertEqual(resp.draft.specs?["brand"], "Levi's")
        XCTAssertEqual(resp.draft.estimatedValue?.low, 45)
        XCTAssertEqual(resp.draft.estimatedValue?.high, 80)
        XCTAssertEqual(resp.draft.tags, ["denim", "vintage"])
    }

    // MARK: Bridge to the analyze-flow draft

    func testMapsToProductDraftForReviewUI() throws {
        let draft = MobileCaptureDraft(
            confidence: 0.9,
            title: "Test Item",
            description: "A thing.",
            condition: "good",
            specs: ["brand": "Acme"],
            suggestedPriceUsd: 30,
            estimatedValue: .init(low: 20, high: 40, currency: "USD", basis: "resale_market", reasoning: nil),
            tags: ["a", "b"]
        )
        let mapped = draft.toProductDraft()
        XCTAssertEqual(mapped.title, "Test Item")
        XCTAssertEqual(mapped.brand, "Acme")
        XCTAssertEqual(mapped.suggestedPriceLow, 20)
        XCTAssertEqual(mapped.suggestedPriceHigh, 40)
        XCTAssertEqual(mapped.tags, ["a", "b"])
    }
}
