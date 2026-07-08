import Foundation

// Sales dashboard models — GET /api/sales/* (per-creator orders, revenue,
// shipping, read-only). BFF sends camelCase; `.convertFromSnakeCase` leaves
// it untouched.

/// One order row (list + summary.recentOrders + detail header).
public struct OrderSummary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let orderNumber: String
    public let buyerEmail: String?
    public let total: Double
    public let currency: String?
    public let state: String
    public let placedAt: String?
    public let itemCount: Int?
    public let shippingState: String?

    public var totalDisplay: String {
        "$" + String(format: total.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f", total)
    }

    /// Short date from the ISO8601 `placedAt` (falls back to the raw string).
    public var placedDisplay: String? {
        guard let placedAt else { return nil }
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: placedAt) else { return String(placedAt.prefix(10)) }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

public struct SalesSummary: Decodable, Sendable {
    public let period: Int
    public let currency: String?
    public let grossRevenue: Double
    public let platformFees: Double
    public let netRevenue: Double
    public let orderCount: Int
    public let avgOrderValue: Double
    public let pendingOrderCount: Int
    public let pendingValue: Double
    public let lifetimeOrderCount: Int
    public let lifetimeRevenue: Double
    public let recentOrders: [OrderSummary]
}

public struct OrderItemLine: Codable, Sendable, Equatable {
    public let title: String
    public let quantity: Int
    public let unitPrice: Double
    public let total: Double
}

public struct ShipmentInfo: Codable, Sendable, Equatable {
    public let state: String
    public let trackingCode: String?
    public let method: String?
    public let shippedAt: String?
    public let destination: String?
}

public struct OrderDetail: Decodable, Sendable {
    public let id: String
    public let orderNumber: String
    public let buyerEmail: String?
    public let total: Double
    public let currency: String?
    public let state: String
    public let placedAt: String?
    public let completedAt: String?
    public let itemCount: Int?
    public let shippingState: String?
    public let items: [OrderItemLine]
    public let shipments: [ShipmentInfo]

    public var header: OrderSummary {
        OrderSummary(id: id, orderNumber: orderNumber, buyerEmail: buyerEmail, total: total,
                     currency: currency, state: state, placedAt: placedAt,
                     itemCount: itemCount, shippingState: shippingState)
    }
}

public struct OrdersPage: Decodable, Sendable {
    public let page: Int
    public let pageSize: Int
    public let hasMore: Bool
    public let orders: [OrderSummary]
}
