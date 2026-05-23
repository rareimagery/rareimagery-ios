import Foundation
import SwiftData

// MARK: - CapturedItem
// Represents a single photo capture during Discovery or Product creation.
// One thing at a time philosophy.
@Model
final class CapturedItem {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var imageData: Data?          // Local full-res or processed JPEG
    var thumbnailData: Data?      // Small preview for lists
    var analysisJSON: String?     // Raw Grok Vision response (or decoded later)
    var suggestedTitle: String?
    var suggestedDescription: String?
    var suggestedTags: [String] = []
    var isProcessed: Bool = false
    
    // Relationship to draft if user decided to make it sellable
    var productDraft: ProductDraft?
    
    init(imageData: Data? = nil, thumbnailData: Data? = nil) {
        self.imageData = imageData
        self.thumbnailData = thumbnailData
    }
}

// MARK: - ProductDraft
// Lightweight draft ready to become a real product.
// Minimal fields for fastest path to sell.
@Model
final class ProductDraft {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String = ""
    var productDescription: String = ""
    var price: Double = 0.0
    var productType: String = "T-Shirt"   // T-Shirt, Hoodie, Poster, Sticker, etc.
    var tags: [String] = []
    var captureItem: CapturedItem?
    
    var isPublished: Bool = false
    var xPostDraft: String?           // Optional tweet text
    
    init(title: String = "", productDescription: String = "", price: Double = 24.0, productType: String = "T-Shirt") {
        self.title = title
        self.productDescription = productDescription
        self.price = price
        self.productType = productType
    }
}
