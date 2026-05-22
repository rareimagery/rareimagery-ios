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

