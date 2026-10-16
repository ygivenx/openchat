import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss
    @State private var testing = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Base URL", text: $settings.baseURL).textInputAutocapitalization(.never).keyboardType(.URL)
                    Text("Both HTTP and HTTPS allowed").font(.caption).foregroundStyle(.secondary)
                    SecureField("API Key (optional)", text: $settings.apiKey)
                    Text("Stored in Keychain").font(.caption).foregroundStyle(.secondary)
                }
                Section("Model") {
                    TextField("Model ID", text: $settings.model).textInputAutocapitalization(.never)
                    if !settings.availableModels.isEmpty {
                        ForEach(settings.availableModels, id: \.self) { m in
                            Button(m) { settings.model = m }.lineLimit(1)
                        }
                    }
                    Button { test() } label: { Label("Test connection", systemImage: "antenna.radiowaves.left.and.right") }
                    if testing { ProgressView() }
                    if let r=result { Text(r).font(.caption).foregroundStyle(r.hasPrefix("OK") ? .green : .red) }
                }
                Section("Privacy") {
                    Label("Chats stay on device", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    func test() {
        testing=true; result=nil
        Task {
            do { let ids = try await OpenAIClient(baseURL: settings.baseURL, apiKey: settings.apiKey).listModels(); settings.availableModels=ids; result="OK — \(ids.count) model(s)" }
            catch { result="Error: \(error.localizedDescription)" }
            testing=false
        }
    }
}
