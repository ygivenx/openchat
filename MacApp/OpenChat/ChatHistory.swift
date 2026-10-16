import Foundation

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: String
    var text: String
    var reasoning: String = ""
    var imageFilename: String?
    var imageMimeType: String?
    var timestamp = Date()

    // Read old history files, but never write large images inline again.
    var legacyImageBase64: String?

    enum CodingKeys: String, CodingKey {
        case id, role, text, reasoning, imageFilename, imageMimeType, timestamp
        case legacyImageBase64 = "imageBase64"
    }

    init(
        id: UUID = UUID(),
        role: String,
        text: String,
        reasoning: String = "",
        imageFilename: String? = nil,
        imageMimeType: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.imageFilename = imageFilename
        self.imageMimeType = imageMimeType
        self.timestamp = timestamp
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(role, forKey: .role)
        try values.encode(text, forKey: .text)
        try values.encode(reasoning, forKey: .reasoning)
        try values.encodeIfPresent(imageFilename, forKey: .imageFilename)
        try values.encodeIfPresent(imageMimeType, forKey: .imageMimeType)
        try values.encode(timestamp, forKey: .timestamp)
    }
}

struct ChatSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    var messages: [ChatMessage] = []
    var model: String = ""

    var preview: String {
        messages.last(where: { !$0.text.isEmpty })?.text.prefix(80).description ?? "New chat"
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var sessions: [ChatSession] = []
    @Published var selectedID: UUID? {
        didSet { saveSelection() }
    }
    @Published private(set) var persistenceError: String?

    var selected: ChatSession? {
        sessions.first(where: { $0.id == selectedID })
    }

    private let baseDirectory: URL
    private let historyURL: URL
    private let mediaDirectory: URL
    private let defaults: UserDefaults
    private let selectionKey = "openchat.selectedID"
    private var saveTask: Task<Void, Never>?

    init(baseDirectory: URL? = nil, defaults: UserDefaults = .standard) {
        let directory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("OpenChat", isDirectory: true)
        self.baseDirectory = directory
        self.historyURL = directory.appendingPathComponent("history.json")
        self.mediaDirectory = directory.appendingPathComponent("Media", isDirectory: true)
        self.defaults = defaults
        createDirectories()
        load()
    }

    func newChat(model: String = "") {
        let session = ChatSession(title: "New chat", model: model)
        sessions.insert(session, at: 0)
        selectedID = session.id
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard let chat = session(id) else { return }
        chat.messages.forEach(removeMedia)
        sessions.removeAll { $0.id == id }
        if selectedID == id { selectedID = sessions.first?.id }
        if sessions.isEmpty { newChat() } else { scheduleSave() }
    }

    func session(_ id: UUID) -> ChatSession? {
        sessions.first(where: { $0.id == id })
    }

    func setModel(_ model: String, for sessionID: UUID) {
        updateSession(sessionID) { $0.model = model }
    }

    @discardableResult
    func append(_ message: ChatMessage, to sessionID: UUID) -> Bool {
        updateSession(sessionID) { $0.messages.append(message) }
    }

    @discardableResult
    func updateMessage(
        sessionID: UUID,
        messageID: UUID,
        _ mutate: (inout ChatMessage) -> Void
    ) -> Bool {
        updateSession(sessionID) { chat in
            guard let index = chat.messages.firstIndex(where: { $0.id == messageID }) else { return }
            mutate(&chat.messages[index])
        }
    }

    func removeMessage(sessionID: UUID, messageID: UUID) {
        updateSession(sessionID) { chat in
            guard let message = chat.messages.first(where: { $0.id == messageID }) else { return }
            removeMedia(for: message)
            chat.messages.removeAll { $0.id == messageID }
        }
    }

    func attachImage(_ image: PreparedImage, to messageID: UUID, in sessionID: UUID) throws {
        let filename = "\(messageID.uuidString).jpg"
        let url = mediaDirectory.appendingPathComponent(filename)
        try image.data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        updateMessage(sessionID: sessionID, messageID: messageID) {
            $0.imageFilename = filename
            $0.imageMimeType = image.mimeType
        }
    }

    func imageData(for message: ChatMessage) -> Data? {
        guard let filename = message.imageFilename else { return nil }
        return try? Data(contentsOf: mediaDirectory.appendingPathComponent(filename))
    }

    func flush() {
        saveTask?.cancel()
        saveNow()
    }

    @discardableResult
    private func updateSession(_ id: UUID, _ mutate: (inout ChatSession) -> Void) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        mutate(&sessions[index])
        sessions[index].updatedAt = Date()
        if ["New chat"].contains(sessions[index].title),
           let first = sessions[index].messages.first(where: { $0.role == "user" }) {
            let title = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { sessions[index].title = String(title.prefix(40)) }
        }
        objectWillChange.send()
        scheduleSave()
        return true
    }

    private func createDirectories() {
        do {
            try FileManager.default.createDirectory(
                at: mediaDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            persistenceError = "Unable to create chat storage: \(error.localizedDescription)"
        }
    }

    private func load() {
        do {
            if FileManager.default.fileExists(atPath: historyURL.path) {
                sessions = try JSONDecoder().decode(
                    [ChatSession].self,
                    from: Data(contentsOf: historyURL)
                )
                migrateInlineImages()
            }
        } catch {
            let backup = baseDirectory.appendingPathComponent(
                "history-corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? FileManager.default.moveItem(at: historyURL, to: backup)
            persistenceError = "Unreadable history was moved to \(backup.lastPathComponent)."
            sessions = []
        }

        if let value = defaults.string(forKey: selectionKey) {
            selectedID = UUID(uuidString: value)
        }
        if sessions.isEmpty {
            newChat()
        } else if selectedID == nil || selectedID.flatMap(session) == nil {
            selectedID = sessions.first?.id
        }
    }

    private func migrateInlineImages() {
        var changed = false
        for sessionIndex in sessions.indices {
            for messageIndex in sessions[sessionIndex].messages.indices {
                var message = sessions[sessionIndex].messages[messageIndex]
                guard message.imageFilename == nil,
                      let encoded = message.legacyImageBase64,
                      let data = Data(base64Encoded: encoded) else { continue }
                let filename = "\(message.id.uuidString)-legacy.jpg"
                do {
                    try data.write(
                        to: mediaDirectory.appendingPathComponent(filename),
                        options: [.atomic, .completeFileProtection]
                    )
                    message.imageFilename = filename
                    message.imageMimeType = "image/jpeg"
                    message.legacyImageBase64 = nil
                    sessions[sessionIndex].messages[messageIndex] = message
                    changed = true
                } catch {
                    persistenceError = "An older image could not be migrated: \(error.localizedDescription)"
                }
            }
        }
        if changed { saveNow() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: historyURL, options: [.atomic, .completeFileProtection])
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: historyURL.path
            )
            persistenceError = nil
        } catch {
            persistenceError = "Unable to save chat history: \(error.localizedDescription)"
        }
    }

    private func saveSelection() {
        if let id = selectedID {
            defaults.set(id.uuidString, forKey: selectionKey)
        } else {
            defaults.removeObject(forKey: selectionKey)
        }
    }

    private func removeMedia(for message: ChatMessage) {
        guard let filename = message.imageFilename else { return }
        try? FileManager.default.removeItem(at: mediaDirectory.appendingPathComponent(filename))
    }
}
