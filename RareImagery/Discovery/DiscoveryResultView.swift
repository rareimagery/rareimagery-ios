import SwiftUI
import SwiftData

struct DiscoveryResultView: View {
    let capturedItem: CapturedItem
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Photo
                        if let data = capturedItem.thumbnailData ?? capturedItem.imageData,
                           let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 340)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .padding(.horizontal)
                        }
                        
                        // Analysis from Rare
                        VStack(alignment: .leading, spacing: 14) {
                            Text(capturedItem.suggestedTitle ?? "Something interesting")
                                .font(.title2.bold())
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
                        
                        Spacer(minLength: 30)
                        
                        // Actions
                        VStack(spacing: 14) {
                            Button {
                                saveAndMakeSellable()
                            } label: {
                                Text("Make this sellable")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColor.cta)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            
                            Button {
                                saveToDrafts()
                            } label: {
                                Text("Save to drafts")
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }
                            
                            Button(role: .cancel) {
                                dismiss()
                            } label: {
                                Text("Close")
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle("What Rare Saw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func saveAndMakeSellable() {
        // Ensure it's saved
        if capturedItem.modelContext == nil {
            modelContext.insert(capturedItem)
        }
        appState.makeSellable(from: capturedItem)
        dismiss()
    }
    
    private func saveToDrafts() {
        if capturedItem.modelContext == nil {
            modelContext.insert(capturedItem)
        }
        // Optionally mark as draft
        dismiss()
    }
}

struct FlowLayout: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.12))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }
}
