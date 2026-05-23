import SwiftUI
import SwiftData

struct QuickProductView: View {
    let capturedItem: CapturedItem
    @State private var title: String
    @State private var productDescription: String
    @State private var price: Double
    @State private var productType = "T-Shirt"
    @State private var postToX = true
    @State private var isCreating = false
    
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    init(capturedItem: CapturedItem) {
        self.capturedItem = capturedItem
        _title = State(initialValue: capturedItem.suggestedTitle ?? "New Item")
        _productDescription = State(initialValue: capturedItem.suggestedDescription ?? "")
        _price = State(initialValue: 28)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("What Rare saw") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $productDescription, axis: .vertical)
                        .lineLimit(3...6)
                    
                    Picker("Product Type", selection: $productType) {
                        Text("T-Shirt").tag("T-Shirt")
                        Text("Hoodie").tag("Hoodie")
                        Text("Poster").tag("Poster")
                        Text("Sticker").tag("Sticker")
                    }
                    
                    HStack {
                        Text("Price")
                        Spacer()
                        TextField("Price", value: $price, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                Section {
                    Toggle("Post about this on X", isOn: $postToX)
                } footer: {
                    Text("Rare will draft a post for you to review.")
                }
                
                Section {
                    Button {
                        createProduct()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Create Product")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isCreating)
                }
            }
            .navigationTitle("Make it Sellable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func createProduct() {
        isCreating = true
        
        // Create and persist ProductDraft
        let draft = ProductDraft(
            title: title,
            productDescription: productDescription,
            price: price,
            productType: productType
        )
        draft.captureItem = capturedItem
        draft.xPostDraft = postToX ? "Just dropped this with Rare \u2192 \(title)" : nil
        
        modelContext.insert(draft)
        
        // TODO: Call real backend
        // try await ProductRepository().createProduct(from: draft)
        // or call /api/creator/provision-store if this is first product
        
        // For now simulate network + save
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            await MainActor.run {
                isCreating = false
                appState.didCreateProduct(draft: draft)
                dismiss()
            }
        }
    }
}
