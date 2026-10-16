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

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("baseURL") var baseURL: String = "https://api.openai.com/v1"
    @AppStorage("model") var model: String = "gpt-4o"
    @AppStorage("thinking") var thinking: String = "medium"
    @Published var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            CredentialStore.saveAPIKey(apiKey)
        }
    }
    @Published var availableModels: [String] = []
    @Published var modelsLoading = false
    @Published var modelsError: String? = nil

    init() {
        apiKey = CredentialStore.migrateFromUserDefaults()
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
                }
            } catch {
                modelsError = error.localizedDescription
            }
            modelsLoading = false
        }
    }
}

// ── Design ──
enum Theme {
    /// Dynamic color: follows macOS Light/Dark appearance automatically.
    static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
    static let accent = dyn(NSColor(red: 0.04, green: 0.35, blue: 0.52, alpha: 1), NSColor(red: 0.35, green: 0.72, blue: 0.88, alpha: 1))
    static let accentSoft = accent.opacity(0.12)
    static let bg = Color(nsColor: .textBackgroundColor)
    static let sidebarBg = Color.clear   // native sidebar material shows through
    static let surface = Color.primary.opacity(0.06)
    static let border = Color(nsColor: .separatorColor)
    static let codeBg = Color(nsColor: .textBackgroundColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let subtle = Color(nsColor: .tertiaryLabelColor)
}
