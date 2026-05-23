import SwiftUI
import SwiftData

struct QuickProductView: View {
    let capturedItem: CapturedItem
    @State private var title: String
    @State private var description: String
    @State private var price: Double
    @State private var productType = "T-Shirt"
    @State private var postToX = true
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    init(capturedItem: CapturedItem) {
        self.capturedItem = capturedItem
        _title = State(initialValue: capturedItem.suggestedTitle ?? "New Item")
        _description = State(initialValue: capturedItem.suggestedDescription ?? "")
        _price = State(initialValue: 28.0)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Product Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
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
                    Text("We'll draft a post for you to review before publishing.")
                }
                
                Section {
                    Button {
                        createProduct()
                    } label: {
                        Text("Create Product & Share")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Quick Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func createProduct() {
        // TODO: Create ProductDraft in SwiftData + call backend
        // Then optionally post to X
        appState.didCreateProduct()
        dismiss()
    }
}
