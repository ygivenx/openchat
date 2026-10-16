import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var testing = false
    @State private var testResult: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let p = Bundle.main.path(forResource: "Logo", ofType: "png"), let img = NSImage(contentsOfFile: p) {
                    Image(nsImage: img).resizable().scaledToFit().frame(width: 28, height: 28).cornerRadius(3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenChat").font(.headline)
                    Text("Bring any OpenAI-compatible API").font(.caption).foregroundColor(Theme.muted)
                }
                Spacer()
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connection").font(.headline)
                            TextField("Base URL", text: $settings.baseURL).textFieldStyle(.roundedBorder)
                            Text("Both HTTP and HTTPS are allowed.").font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                            SecureField("API Key (optional for local servers)", text: $settings.apiKey).textFieldStyle(.roundedBorder)
                            Text("Stored in macOS Keychain and sent only to this API.").font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model").font(.headline)
                            HStack {
                                TextField("Model ID", text: $settings.model).textFieldStyle(.roundedBorder)
                                if settings.modelsLoading { ProgressView().scaleEffect(0.7) }
                            }
                            if !settings.availableModels.isEmpty {
                                Text("Available models (\(settings.availableModels.count))").font(.caption).foregroundColor(Theme.muted)
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(settings.availableModels, id: \.self) { m in
                                        HStack {
                                            Text(m).font(.caption).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            if m == settings.model { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent).font(.caption) }
                                        }
                                        .contentShape(Rectangle()).onTapGesture { settings.model = m }
                                        .padding(.vertical, 6).padding(.horizontal, 6)
                                        if m != settings.availableModels.last { Divider().opacity(0.5) }
                                    }
                                }.frame(maxHeight: 140).background(Theme.surface).cornerRadius(6).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                            } else if let e = settings.modelsError {
                                Text(e).font(.caption).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
                            }
                            HStack(spacing: 8) {
                                Button { test() } label: { Label("Test connection & list models", systemImage: "antenna.radiowaves.left.and.right") }
                                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                                    .disabled(testing || settings.baseURL.isEmpty)
                                if testing { ProgressView().scaleEffect(0.7) }
                                if let r = testResult { Text(r).font(.caption).foregroundColor(r.hasPrefix("OK") ? .green : .red).fixedSize(horizontal: false, vertical: true) }
                            }
                        }
                    }
                    GroupBox {
                        Label("Chats and resized attachments stay in protected Application Support files on this Mac.", systemImage: "lock.shield")
                            .font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(16)
            }
        }.frame(width: 560, height: 600)
    }

    func test() {
        testing = true
        testResult = nil
        Task {
            do {
                let ids = try await OpenAIClient(
                    baseURL: settings.baseURL,
                    apiKey: settings.apiKey
                ).listModels()
                settings.availableModels = ids
                settings.modelsError = nil
                testResult = "OK — \(ids.count) model(s) found"
            } catch {
                testResult = "Error: \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
