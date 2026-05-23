import SwiftUI
import SwiftData

struct DiscoveryResultView: View {
    let capturedItem: CapturedItem
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Photo
                        if let data = capturedItem.thumbnailData ?? capturedItem.imageData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .padding(.horizontal)
                        }
                        
                        // Analysis
                        VStack(alignment: .leading, spacing: 12) {
                            Text(capturedItem.suggestedTitle ?? "Unknown Item")
                                .font(.title.bold())
                                .foregroundStyle(.white)
                            
                            if let desc = capturedItem.suggestedDescription {
                                Text(desc)
                                    .font(.body)
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            
                            if !capturedItem.suggestedTags.isEmpty {
                                FlowLayout(tags: capturedItem.suggestedTags)
                            }
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 40)
                        
                        // Actions
                        VStack(spacing: 12) {
                            Button {
                                appState.makeSellable(from: capturedItem)
                            } label: {
                                Text("Make this sellable")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.white)
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            
                            Button {
                                appState.captureAnother()
                            } label: {
                                Text("Capture another thing")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }
                            
                            Button(role: .cancel) {
                                dismiss()
                            } label: {
                                Text("Save to drafts & close")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle("What Grok Saw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// Simple tag flow layout
struct FlowLayout: View {
    let tags: [String]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.15))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}
