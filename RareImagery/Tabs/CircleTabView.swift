import SwiftUI
import SwiftData

struct CircleTabView: View {
    @Environment(AppState.self) private var state
    @Environment(\.modelContext) private var modelContext
    @State private var service: CircleService?
    @State private var selectedSegment: CircleSegment = .discover

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Circle", selection: $selectedSegment) {
                    ForEach(CircleSegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if let message = service?.errorMessage {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                Group {
                    switch selectedSegment {
                    case .discover:
                        if let service {
                            DiscoverView(service: service)
                        }
                    case .myCircle:
                        MyCircleView(
                            members: service?.circleMembers ?? [],
                            onRemove: { member in service?.removeMember(member) },
                            onFindFriends: { selectedSegment = .discover }
                        )
                    case .favorites:
                        FavoritesView(
                            favorites: service?.favorites ?? [],
                            onDiscover: { selectedSegment = .discover }
                        )
                    }
                }
            }
            .background(AppColor.background)
            .navigationTitle("Rare Circle")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                if service == nil {
                    service = CircleService(
                        modelContext: modelContext,
                        repository: state.circleRepository
                    )
                }
            }
        }
    }
}
