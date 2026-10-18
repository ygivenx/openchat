import SwiftUI

@main
struct OpenChatApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var history = ChatStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
                .frame(minWidth: 860, minHeight: 560)
                .tint(Theme.accent)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { history.newChat(model: settings.model) }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        Settings { SettingsView().environmentObject(settings) }
    }
}

// MARK: - Connection model

struct SavedConnection: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: String
    var model: String

    init(id: UUID = UUID(), name: String, baseURL: String, model: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
    }
}

@MainActor
final class AppSettings: ObservableObject {
    // Backing: @AppStorage for legacy single-connection keys still used for active values
    @AppStorage("baseURL") var baseURL: String = "https://api.openai.com/v1"
    @AppStorage("model") var model: String = "gpt-4o"
    @AppStorage("thinking") var thinking: String = "medium"

    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            // Save to active connection's keychain slot if multi-connection, else legacy
            if let id = activeConnectionID, connections.contains(where: { $0.id == id }) {
                CredentialStore.saveAPIKey(apiKey, for: id)
            } else {
                CredentialStore.saveAPIKey(apiKey)
            }
        }
    }

    @Published var availableModels: [String] = []
    @Published var modelsLoading = false
    @Published var modelsError: String? = nil

    @Published var connections: [SavedConnection] {
        didSet { persistConnections() }
    }
    @Published var activeConnectionID: UUID? {
        didSet { persistActiveID(); if oldValue != activeConnectionID { applyActiveConnection() } }
    }

    var activeConnection: SavedConnection? {
        guard let id = activeConnectionID else { return nil }
        return connections.first(where: { $0.id == id })
    }

    private let connectionsKey = "connections"
    private let activeIDKey = "activeConnectionID"

    init() {
        // Load apiKey fallback (will be reassigned after connections load)
        let legacyKey = CredentialStore.migrateFromUserDefaults()
        // Load connections
        var loaded: [SavedConnection]? = nil
        if let data = UserDefaults.standard.data(forKey: "connections"),
           let decoded = try? JSONDecoder().decode([SavedConnection].self, from: data), !decoded.isEmpty {
            loaded = decoded
        }
        // Load active ID
        var loadedID: UUID? = nil
        if let s = UserDefaults.standard.string(forKey: "activeConnectionID"), let u = UUID(uuidString: s) {
            loadedID = u
        }

        let currentBaseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.openai.com/v1"
        let currentModel = UserDefaults.standard.string(forKey: "model") ?? "gpt-4o"

        if let l = loaded {
            connections = l
            activeConnectionID = loadedID ?? l.first?.id
            // Migrate legacy apiKey into per-connection slots if needed (once)
            if !legacyKey.isEmpty {
                for c in l where CredentialStore.loadAPIKey(for: c.id).isEmpty {
                    CredentialStore.saveAPIKey(legacyKey, for: c.id)
                }
            }
            apiKey = ""
            // Defer applyActiveConnection until after init assigns; do manually here
            if let id = activeConnectionID, let active = connections.first(where: { $0.id == id }) {
                // sync @AppStorage values if stale
                if currentBaseURL != active.baseURL { UserDefaults.standard.set(active.baseURL, forKey: "baseURL") }
                if currentModel != active.model { UserDefaults.standard.set(active.model, forKey: "model") }
                apiKey = CredentialStore.loadAPIKey(for: id)
            } else {
                apiKey = CredentialStore.loadAPIKey()
            }
        } else {
            // First run or no connections yet — create one from legacy single values
            let c = SavedConnection(name: "Default", baseURL: currentBaseURL, model: currentModel)
            connections = [c]
            activeConnectionID = c.id
            apiKey = legacyKey.isEmpty ? CredentialStore.loadAPIKey() : legacyKey
            if !apiKey.isEmpty { CredentialStore.saveAPIKey(apiKey, for: c.id) }
            // persist
            if let data = try? JSONEncoder().encode(connections) {
                UserDefaults.standard.set(data, forKey: "connections")
            }
            UserDefaults.standard.set(c.id.uuidString, forKey: "activeConnectionID")
        }
    }

    func fetchModels() {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        modelsLoading = true
        modelsError = nil
        Task {
            do {
                let models = try await OpenAIClient(baseURL: baseURL, apiKey: apiKey).listModels()
                availableModels = models
                if !models.isEmpty && !models.contains(model) {
                    model = models[0]
                    updateActiveConnectionModel(model)
                }
            } catch {
                modelsError = error.localizedDescription
            }
            modelsLoading = false
        }
    }

    // MARK: - Connection CRUD

    func addConnection() {
        let n = nextDefaultName()
        let c = SavedConnection(name: n, baseURL: baseURL, model: model)
        connections.append(c)
        activeConnectionID = c.id
        CredentialStore.saveAPIKey(apiKey, for: c.id)
    }

    func duplicateConnection(_ id: UUID) {
        guard let src = connections.first(where: { $0.id == id }) else { return }
        let c = SavedConnection(name: src.name + " Copy", baseURL: src.baseURL, model: src.model)
        connections.append(c)
        CredentialStore.saveAPIKey(CredentialStore.loadAPIKey(for: src.id), for: c.id)
    }

    func deleteConnection(_ id: UUID) {
        guard connections.count > 1 else { return }
        connections.removeAll { $0.id == id }
        CredentialStore.deleteAPIKey(for: id)
        if activeConnectionID == id { activeConnectionID = connections.first?.id }
    }

    func selectConnection(_ id: UUID) {
        // Save current active's edits first
        syncActiveConnectionFromFields()
        activeConnectionID = id
    }

    func renameConnection(_ id: UUID, to name: String) {
        guard let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].name = name
    }

    func updateActiveConnectionBaseURL(_ v: String) {
        guard let id = activeConnectionID, let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].baseURL = v
    }

    func updateActiveConnectionModel(_ v: String) {
        guard let id = activeConnectionID, let idx = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[idx].model = v
    }

    // Called when baseURL/model edited via binding - keep connection in sync
    func syncActiveConnectionFromFields() {
        if let id = activeConnectionID, let idx = connections.firstIndex(where: { $0.id == id }) {
            if connections[idx].baseURL != baseURL { connections[idx].baseURL = baseURL }
            if connections[idx].model != model { connections[idx].model = model }
        }
    }

    // MARK: - Private

    private func applyActiveConnection() {
        guard let id = activeConnectionID, let c = connections.first(where: { $0.id == id }) else { return }
        // Update @AppStorage-backed fields without triggering redundant sync loop
        if baseURL != c.baseURL { baseURL = c.baseURL }
        if model != c.model { model = c.model }
        let key = CredentialStore.loadAPIKey(for: id)
        if apiKey != key { apiKey = key }
        // clear model cache when switching server, refetch
        availableModels = []
        modelsError = nil
        fetchModels()
        persistActiveID()
    }

    private func persistConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: connectionsKey)
        }
        // Also sync active connection's baseURL/model to storage if needed
        syncActiveConnectionFromFields()
    }

    private func persistActiveID() {
        if let id = activeConnectionID {
            UserDefaults.standard.set(id.uuidString, forKey: activeIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIDKey)
        }
    }

    private func nextDefaultName() -> String {
        let base = "Connection"
        if !connections.contains(where: { $0.name == base }) { return base }
        var i = 2
        while connections.contains(where: { $0.name == "\(base) \(i)" }) { i += 1 }
        return "\(base) \(i)"
    }
}

// ── Design ──
enum Theme {
    static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let accent = dyn(NSColor(red: 0.04, green: 0.35, blue: 0.52, alpha: 1), NSColor(red: 0.35, green: 0.72, blue: 0.88, alpha: 1))
    static let accentSoft = accent.opacity(0.12)
    static let bg = Color(nsColor: .textBackgroundColor)
    static let sidebarBg = Color.clear
    static let surface = Color.primary.opacity(0.06)
    static let border = Color(nsColor: .separatorColor)
    static let codeBg = Color(nsColor: .textBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let subtle = Color(nsColor: .tertiaryLabelColor)
}
