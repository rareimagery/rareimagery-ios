import SwiftUI

struct FilmstripView: View {
    @Environment(CaptureSession.self) private var capture

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(capture.shots.enumerated()), id: \.element.id) { index, shot in
                    ShotThumbnail(
                        shot: shot,
                        isHero: index == capture.heroIndex,
                        isUploaded: shot.uploadedURL != nil
                    )
                    .onTapGesture { capture.setHero(index: index) }
                    .contextMenu {
                        Button(role: .destructive) {
                            capture.removeShot(id: shot.id)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 116)
    }
}

private struct ShotThumbnail: View {
    let shot: CaptureSession.Shot
    let isHero: Bool
    let isUploaded: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let uiImage = UIImage(data: shot.jpegData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHero ? AppColor.accent : AppColor.border, lineWidth: isHero ? 3 : 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColor.surface)
                    .frame(width: 96, height: 96)
            }

            VStack(alignment: .trailing, spacing: 4) {
                if isHero {
                    Text("MAIN")
                        .font(.system(size: 10, weight: .heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColor.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                if !isUploaded {
                    Image(systemName: "icloud.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .clipShape(Circle())
                }
            }
            .padding(6)
        }
    }
}
