import SwiftUI
import PhotosUI
import RareImageryAPI

struct CaptureView: View {
    @Environment(AppState.self) private var state
    @Environment(CaptureSession.self) private var capture
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(spacing: 24) {
            header

            if capture.shots.isEmpty {
                emptyState
            } else {
                FilmstripView()

                // Multi-photo curation grid (Phase 1 for full Create First Drop / Rare Drop)
                // Matches web PhotoCurationGrid + spec: select 1-2 favorites (for Grok Vision + product pics),
                // trash the rest, only selected sent to analyze.
                // High fidelity: dark palette, orange accents, star badges, trash.
                curationGrid

                intentPicker

                Spacer(minLength: 0)

                analyzeButton
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.background)
        .onChange(of: pickerItems) { _, newItems in
            Task { await ingest(newItems) }
        }
    }

    private var header: some View {
        HStack {
            Text("Capture")
                .font(AppFont.title)
                .foregroundStyle(AppColor.textPrimary)
            Spacer()
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: CaptureSession.maxShots,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text(capture.shots.isEmpty ? "Add photos" : "Add more")
                }
                .font(AppFont.callout)
                .foregroundStyle(AppColor.accent)
            }
            .disabled(!capture.canAddMore)
        }
        .padding(.horizontal, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(AppColor.textSecondary)
            Text("Pick up to 5 photos")
                .font(AppFont.headline)
                .foregroundStyle(AppColor.textPrimary)
            Text("Tap a photo to mark it as the main image.")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
        }
    }

    private var intentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's this for?")
                .font(AppFont.callout)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ProductIntent.allCases, id: \.self) { intent in
                        Button {
                            capture.intent = intent
                        } label: {
                            Text(intent.displayName)
                                .font(AppFont.callout)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(capture.intent == intent ? AppColor.accent : AppColor.surface)
                                .foregroundStyle(capture.intent == intent ? .white : AppColor.textPrimary)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var curationGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select 1-2 favorites")
                    .font(AppFont.callout)
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text("\(capture.selectedFavoriteIds.count)/2")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(capture.shots) { shot in
                        let isFavorite = capture.selectedFavoriteIds.contains(shot.id)
                        ShotCurationThumbnail(
                            shot: shot,
                            isFavorite: isFavorite,
                            isHero: capture.hero?.id == shot.id
                        )
                        .onTapGesture {
                            capture.toggleFavorite(id: shot.id)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                capture.removeShot(id: shot.id)
                                capture.selectedFavoriteIds.remove(shot.id)
                            } label: {
                                Label("Trash", systemImage: "trash")
                            }
                            if isFavorite {
                                Button("Unfavorite") {
                                    capture.toggleFavorite(id: shot.id)
                                }
                            } else if capture.selectedFavoriteIds.count < 2 {
                                Button("Favorite") {
                                    capture.toggleFavorite(id: shot.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack {
                Button {
                    capture.trashUnselected()
                } label: {
                    Text("Trash unselected")
                        .font(AppFont.callout)
                }
                .disabled(capture.selectedFavoriteIds.count == capture.shots.count)
                .foregroundStyle(AppColor.textSecondary)

                Spacer()

                Button {
                    Task { await CaptureCoordinator.run(state: state) }
                } label: {
                    Text("Analyze \(capture.selectedFavoriteIds.count) selected")
                        .font(AppFont.buttonLabel)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.cta)
                .disabled(capture.selectedFavoriteIds.isEmpty || capture.selectedFavoriteIds.count > 2)
            }
            .padding(.horizontal, 16)

            Text("Only your chosen favorites are sent to Grok Vision and saved as product pictures.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 16)
        }
    }

    // NOTE: pre-existing structural fix — a stray `}` here was closing CaptureView
    // early, orphaning analyzeButton/ingest and making the final brace extraneous.
    // Removed it so those stay members of CaptureView; ShotCurationThumbnail nests.
    private struct ShotCurationThumbnail: View {
    let shot: CaptureSession.Shot
    let isFavorite: Bool
    let isHero: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let uiImage = UIImage(data: shot.jpegData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFavorite ? AppColor.accent : AppColor.border, lineWidth: isFavorite ? 3 : 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppColor.surface)
                    .frame(width: 80, height: 80)
            }

            if isFavorite {
                Text("FAV")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColor.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(4)
            }

            if isHero {
                Text("HERO")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(AppColor.cta)
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                    .padding(4)
                    .offset(x: 0, y: 22)
            }
        }
    }
}

    private var analyzeButton: some View {
        Button {
            Task { await CaptureCoordinator.run(state: state) }
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Analyze with AI")
            }
            .font(AppFont.buttonLabel)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(capture.canAnalyze ? AppColor.accent : AppColor.surface)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .disabled(!capture.canAnalyze)
    }

    private func ingest(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items where capture.canAddMore {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let compressed = ImageCompression.compressForUpload(data: data) {
                capture.addShot(jpegData: compressed)
            }
        }
        pickerItems = []
    }
}

