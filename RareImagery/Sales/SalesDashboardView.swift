import SwiftUI
import RareImageryAPI

/// Profile → Sales: the creator's store sales system, read-only from Drupal
/// Commerce. Dashboard (revenue/orders/pending + recent orders) → all orders
/// → order detail with items + shipping/tracking.
struct SalesDashboardView: View {
    @Environment(AppState.self) private var state

    @State private var summary: SalesSummary?
    @State private var period = 30
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading && summary == nil {
                    ProgressView().tint(AppColor.gold)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if let summary {
                    periodPicker
                    statGrid(summary)
                    lifetimeLine(summary)
                    recentSection(summary)
                } else {
                    ContentUnavailableView(
                        "No sales data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text(message ?? "Sales show up here once orders come in.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(AppColor.background)
        .navigationTitle("Sales")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: period) { Task { await load() } }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
        }
        .pickerStyle(.segmented)
    }

    private func statGrid(_ s: SalesSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statCard("NET REVENUE", money(s.netRevenue), accent: true)
            statCard("ORDERS", "\(s.orderCount)")
            statCard("AVG ORDER", money(s.avgOrderValue))
            statCard("PENDING", s.pendingOrderCount == 0 ? "—" : "\(s.pendingOrderCount) · \(money(s.pendingValue))")
        }
    }

    private func statCard(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(AppColor.textSecondary)
            Text(value)
                .font(AppFont.mono(22, .bold))
                .foregroundStyle(accent ? AppColor.gold : AppColor.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent ? AppColor.borderGold : AppColor.border, lineWidth: 1))
    }

    private func lifetimeLine(_ s: SalesSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "infinity").font(.system(size: 11))
            Text("All-time: \(s.lifetimeOrderCount) orders · \(money(s.lifetimeRevenue)) gross · fees \(money(s.platformFees)) this period")
        }
        .font(AppFont.bodyText(12))
        .foregroundStyle(AppColor.textSecondary)
    }

    @ViewBuilder private func recentSection(_ s: SalesSummary) -> some View {
        HStack {
            Text("RECENT ORDERS")
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            NavigationLink("All orders") { OrdersListView().environment(state) }
                .font(AppFont.bodyText(13)).foregroundStyle(AppColor.gold)
        }
        .padding(.top, 6)

        if s.recentOrders.isEmpty {
            Text("No orders in this period.")
                .font(AppFont.bodyText(13)).foregroundStyle(AppColor.textSecondary)
        } else {
            VStack(spacing: 10) {
                ForEach(s.recentOrders) { order in
                    NavigationLink {
                        OrderDetailScreen(orderId: order.id).environment(state)
                    } label: {
                        OrderRow(order: order)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func money(_ v: Double) -> String {
        "$" + String(format: v.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f", v)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            summary = try await state.salesRepository.summary(period: period)
            message = nil
        } catch {
            message = "Couldn't load sales. Pull to retry."
        }
    }
}

// MARK: - Shared order row

struct OrderRow: View {
    let order: OrderSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("#\(order.orderNumber)")
                        .font(AppFont.mono(13, .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    stateBadge
                }
                Text(order.buyerEmail ?? "—")
                    .font(AppFont.bodyText(12))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(order.totalDisplay)
                    .font(AppFont.mono(15, .bold)).foregroundStyle(AppColor.gold)
                if let placed = order.placedDisplay {
                    Text(placed).font(AppFont.bodyText(11)).foregroundStyle(AppColor.textSecondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(12)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColor.border, lineWidth: 1))
    }

    @ViewBuilder private var stateBadge: some View {
        let (label, color): (String, Color) = switch order.state {
        case "completed": ("PAID", AppColor.success)
        case "fulfillment": ("FULFILLING", AppColor.gold)
        case "canceled": ("CANCELED", AppColor.textSecondary)
        default: (order.state.uppercased(), AppColor.textSecondary)
        }
        Text(label)
            .font(AppFont.mono(9, .semibold)).tracking(1.2)
            .foregroundStyle(color)
    }
}

// MARK: - All orders (paginated)

struct OrdersListView: View {
    @Environment(AppState.self) private var state

    @State private var orders: [OrderSummary] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if loading && orders.isEmpty {
                    ProgressView().tint(AppColor.gold).padding(.top, 60)
                } else if orders.isEmpty {
                    ContentUnavailableView(
                        "No orders yet",
                        systemImage: "shippingbox",
                        description: Text(message ?? "Orders for your products land here.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(orders) { order in
                        NavigationLink {
                            OrderDetailScreen(orderId: order.id).environment(state)
                        } label: {
                            OrderRow(order: order)
                        }
                        .buttonStyle(.plain)
                    }
                    if hasMore {
                        Button {
                            Task { await load(page: page + 1) }
                        } label: {
                            Text(loading ? "Loading…" : "Load more")
                                .font(AppFont.bodyText(14)).foregroundStyle(AppColor.gold)
                                .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(AppColor.background)
        .navigationTitle("Orders")
        .refreshable { await load(page: 0) }
        .task { if orders.isEmpty { await load(page: 0) } }
    }

    private func load(page newPage: Int) async {
        loading = true
        defer { loading = false }
        do {
            let result = try await state.salesRepository.listOrders(page: newPage)
            orders = newPage == 0 ? result.orders : orders + result.orders
            page = result.page
            hasMore = result.hasMore
            message = nil
        } catch {
            message = "Couldn't load orders. Pull to retry."
        }
    }
}

// MARK: - Order detail

struct OrderDetailScreen: View {
    let orderId: String

    @Environment(AppState.self) private var state
    @State private var detail: OrderDetail?
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if loading {
                    ProgressView().tint(AppColor.gold)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if let detail {
                    OrderRow(order: detail.header)

                    section("ITEMS") {
                        VStack(spacing: 8) {
                            ForEach(Array(detail.items.enumerated()), id: \.offset) { _, item in
                                HStack {
                                    Text("\(item.quantity)×")
                                        .font(AppFont.mono(13)).foregroundStyle(AppColor.textSecondary)
                                    Text(item.title)
                                        .font(AppFont.bodyText(14)).foregroundStyle(AppColor.textPrimary)
                                        .lineLimit(2)
                                    Spacer()
                                    Text("$" + String(format: "%.2f", item.total))
                                        .font(AppFont.mono(13)).foregroundStyle(AppColor.gold)
                                }
                            }
                        }
                    }

                    if !detail.shipments.isEmpty {
                        section("SHIPPING") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(detail.shipments.enumerated()), id: \.offset) { _, s in
                                    shipmentRow(s)
                                }
                            }
                        }
                    }
                } else {
                    Text(message ?? "Couldn't load this order.")
                        .font(AppFont.caption).foregroundStyle(AppColor.textSecondary)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                }
            }
            .padding(16)
        }
        .background(AppColor.background)
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder private func section(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(AppFont.mono(10, .semibold)).tracking(1.4)
                .foregroundStyle(AppColor.textSecondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColor.border, lineWidth: 1))
    }

    @ViewBuilder private func shipmentRow(_ s: ShipmentInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: s.state == "shipped" || s.state == "delivered" ? "shippingbox.fill" : "shippingbox")
                    .font(.system(size: 13))
                    .foregroundStyle(s.state == "delivered" ? AppColor.success : AppColor.gold)
                Text(s.state.uppercased())
                    .font(AppFont.mono(11, .semibold)).tracking(1.2)
                    .foregroundStyle(s.state == "delivered" ? AppColor.success : AppColor.gold)
                if let method = s.method {
                    Text("· \(method)").font(AppFont.bodyText(12)).foregroundStyle(AppColor.textSecondary)
                }
            }
            if let tracking = s.trackingCode, !tracking.isEmpty {
                Button {
                    UIPasteboard.general.string = tracking
                } label: {
                    HStack(spacing: 6) {
                        Text(tracking).font(AppFont.mono(12)).foregroundStyle(AppColor.textPrimary)
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                .buttonStyle(.plain)
            }
            if let dest = s.destination {
                Text(dest).font(AppFont.bodyText(12)).foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            detail = try await state.salesRepository.order(id: orderId)
        } catch {
            message = "Couldn't load this order. Go back and retry."
        }
    }
}
