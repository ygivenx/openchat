import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var testing = false
    @State private var testResult: String? = nil
    @State private var editingNameID: UUID? = nil
    @State private var editingName: String = ""

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
                    // Connections picker
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Connections").font(.headline)
                                Spacer()
                                Button { settings.addConnection() } label: {
                                    Label("Add", systemImage: "plus.circle")
                                }.controlSize(.small)
                            }
                            if settings.connections.isEmpty {
                                Text("No connections").font(.caption).foregroundColor(Theme.muted)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(settings.connections) { conn in
                                        HStack(spacing: 6) {
                                            Button {
                                                settings.selectConnection(conn.id)
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: conn.id == settings.activeConnectionID ? "checkmark.circle.fill" : "circle")
                                                        .foregroundColor(conn.id == settings.activeConnectionID ? Theme.accent : Theme.muted)
                                                    if editingNameID == conn.id {
                                                        TextField("Name", text: $editingName, onCommit: {
                                                            let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
                                                            if !trimmed.isEmpty { settings.renameConnection(conn.id, to: trimmed) }
                                                            editingNameID = nil
                                                        })
                                                        .textFieldStyle(.roundedBorder)
                                                        .frame(width: 140)
                                                    } else {
                                                        Text(conn.name).font(.system(size: 13)).lineLimit(1)
                                                            .foregroundColor(conn.id == settings.activeConnectionID ? .primary : .secondary)
                                                    }
                                                    Spacer(minLength: 4)
                                                    Text(conn.baseURL).font(.caption2).foregroundColor(Theme.muted).lineLimit(1).truncationMode(.middle)
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Menu {
                                                Button("Rename") {
                                                    editingName = conn.name
                                                    editingNameID = conn.id
                                                }
                                                Button("Duplicate") { settings.duplicateConnection(conn.id) }
                                                if settings.connections.count > 1 {
                                                    Divider()
                                                    Button("Delete", role: .destructive) { settings.deleteConnection(conn.id) }
                                                }
                                            } label: {
                                                Image(systemName: "ellipsis.circle").foregroundColor(Theme.muted)
                                            }
                                            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                                            .frame(width: 20)
                                        }
                                        .padding(.vertical, 4).padding(.horizontal, 6)
                                        .background(conn.id == settings.activeConnectionID ? Theme.accentSoft : Color.clear)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            Text("API key is stored per-connection in Keychain.").font(.caption2).foregroundColor(Theme.muted)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Connection").font(.headline)
                            TextField("Base URL", text: Binding(
                                get: { settings.baseURL },
                                set: { settings.baseURL = $0; settings.updateActiveConnectionBaseURL($0) }
                            )).textFieldStyle(.roundedBorder)
                            Text("Both HTTP and HTTPS are allowed.").font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                            SecureField("API Key (optional for local servers)", text: $settings.apiKey).textFieldStyle(.roundedBorder)
                            Text("Stored in macOS Keychain and sent only to this API.").font(.caption).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model").font(.headline)
                            HStack {
                                TextField("Model ID", text: Binding(
                                    get: { settings.model },
                                    set: { settings.model = $0; settings.updateActiveConnectionModel($0) }
                                )).textFieldStyle(.roundedBorder)
                                if settings.modelsLoading { ProgressView().scaleEffect(0.7) }
                            }
                            if !settings.availableModels.isEmpty {
                                Text("Available models (\(settings.availableModels.count))").font(.caption).foregroundColor(Theme.muted)
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(settings.availableModels, id: \.self) { m in
                                            HStack {
                                                Text(m).font(.caption).lineLimit(1).truncationMode(.middle)
                                                Spacer()
                                                if m == settings.model { Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.accent).font(.caption) }
                                            }
                                            .contentShape(Rectangle()).onTapGesture {
                                                settings.model = m
                                                settings.updateActiveConnectionModel(m)
                                            }
                                            .padding(.vertical, 6).padding(.horizontal, 6)
                                            if m != settings.availableModels.last { Divider().opacity(0.5) }
                                        }
                                    }
                                }
                                .frame(maxHeight: 240)
                                .background(Theme.surface).cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
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
