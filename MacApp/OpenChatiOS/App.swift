import SwiftUI

@main
struct OpenChatiOSApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var history = ChatHistory()
    @StateObject private var requests = ChatRequestController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(requests)
        }
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("baseURL") var baseURL: String = "http://ppliapppytorc01:8000/v1"
    @AppStorage("model") var model: String = "meta-models/Muse-Spark-Open-816B-A42B-NVFP4"
    @AppStorage("responseStyle") var responseStyle: String = "medium"
    @Published var apiKey: String = CredentialStore.load(key: "openchat_api_key") ?? ""
    @Published var availableModels: [String] = []
    @Published var modelsLoading = false
    @Published var modelsError: String?

    func saveKey(_ key: String) { apiKey = key; CredentialStore.save(key: "openchat_api_key", value: key) }
}
