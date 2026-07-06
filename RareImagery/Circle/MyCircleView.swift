import SwiftUI

struct MyCircleView: View {
    let members: [CircleMember]
    let onRemove: (CircleMember) -> Void
    let onFindFriends: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 90), spacing: 16)
    ]

    var body: some View {
        if members.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColor.accent)
                Text("Build your Rare Circle")
                    .font(AppFont.title)
                Text("Add friends for feedback, approvals, and co-promotion on your drops.")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: onFindFriends) {
                    Text("Find friends")
                        .font(AppFont.buttonLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.accent)
                .padding(.horizontal, 32)
                Spacer()
            }
        } else {
            ScrollView {
                if members.count >= CircleService.maxCircleSize {
                    AtCapWarningCard(count: members.count, cap: CircleService.maxCircleSize)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(members) { member in
                        VStack(spacing: 8) {
                            AsyncImage(url: member.profileImageURL.flatMap(URL.init(string:))) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    Circle()
                                        .fill(AppColor.surfaceSecondary)
                                        .overlay {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 30))
                                                .foregroundStyle(AppColor.textSecondary)
                                        }
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(AppColor.border, lineWidth: 1)
                            }

                            Text(member.displayName)
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(AppColor.textPrimary)
                                .lineLimit(1)

                            Text("@\(member.username)")
                                .font(.caption2)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)

                            if member.isFavorite {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.pink)
                            }
                        }
                        .contextMenu {
                            Button("Remove from Circle", role: .destructive) {
                                onRemove(member)
                            }
                        }
                    }
                }
                .padding()

                Button(action: onFindFriends) {
                    Label("Find more friends", systemImage: "person.badge.plus")
                        .font(AppFont.buttonLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(AppColor.accent)
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }
}
