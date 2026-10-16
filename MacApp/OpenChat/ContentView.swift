import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var history: ChatStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var requests = ChatRequestController()
    @State private var input = ""
    @State private var pendingImage: PreparedImage?
    @State private var pendingImageName: String?
    @State private var pendingFile: PickedFile?
    @State private var pendingFileName: String?
    @State private var showSettings = false
    @State private var errorMsg: String?
    @State private var deleteCandidate: UUID?
    @State private var search = ""
    @FocusState private var inputFocused: Bool

    private var selectedIsActive: Bool {
        requests.isActive(history.selectedID)
    }

    private var activeModel: String {
        let sessionModel = history.selected?.model ?? ""
        return sessionModel.isEmpty ? settings.model : sessionModel
    }

    private var filteredSessions: [ChatSession] {
        guard !search.isEmpty else { return history.sessions }
        return history.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 300)
        } detail: {
            mainPane
                .navigationTitle("OpenChat")
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(settings)
        }
        .alert(
            "OpenChat",
            isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )
        ) {
            Button("OK") { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Chat", role: .destructive) {
                guard let id = deleteCandidate else { return }
                requests.cancel(sessionID: id)
                history.delete(id)
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This removes the conversation and its saved attachments from this Mac.")
        }
        .onAppear {
            if settings.availableModels.isEmpty { settings.fetchModels() }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { history.flush() }
        }
        .onDisappear {
            requests.cancelAll()
            history.flush()
        }
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    private var sidebar: some View {
        List(selection: $history.selectedID) {
            HStack(spacing: 10) {
                logoView(size: 28)
                Text("OpenChat").font(.headline)
                Spacer()
            }
            .padding(.vertical, 6)
            .listRowSeparator(.hidden)

            Button {
                history.newChat(model: settings.model)
                inputFocused = true
            } label: {
                Label("New Chat", systemImage: "square.and.pencil")
            }
            .buttonStyle(.plain)

            Section("Recents") {
                ForEach(filteredSessions) { session in
                    HStack(spacing: 7) {
                        Image(systemName: "bubble.left")
                        Text(session.title).lineLimit(1)
                        Spacer(minLength: 4)
                        if requests.isActive(session.id) {
                            ProgressView().controlSize(.mini)
                        }
                    }
                    .tag(session.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteCandidate = session.id
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $search, placement: .sidebar, prompt: "Search chats")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    @State private var autoScrollEnabled = true

    private var mainPane: some View {
        VStack(spacing: 0) {
            chatArea
            Divider()
            composer
                .frame(maxWidth: Layout.readingWidth)
                .padding(.horizontal, Layout.gutter)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) { modelControl }
                .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { responseStyleControl }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { modelControl }
            ToolbarItem(placement: .primaryAction) { responseStyleControl }
        }
    }

    private var modelControl: some View {
        Group {
            if settings.modelsLoading {
                ProgressView().controlSize(.small).help("Loading models")
            } else if !settings.availableModels.isEmpty {
                Menu {
                    ForEach(settings.availableModels, id: \.self) { model in
                        Button { selectModel(model) } label: {
                            if model == activeModel {
                                Label(model, systemImage: "checkmark")
                            } else {
                                Text(model)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(activeModel).lineLimit(1).truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .frame(maxWidth: 300)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
            } else {
                TextField(
                    "Model",
                    text: Binding(get: { activeModel }, set: selectModel)
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }
        }
        .disabled(selectedIsActive)
        .help(selectedIsActive ? "Stop this response before changing models" : "Model for this chat")
    }

    private var responseStyleControl: some View {
        HStack(spacing: 0) {
            ForEach([("low", "Fast"), ("medium", "Balanced"), ("high", "Deep")], id: \.0) {
                key, label in
                let selected = settings.thinking == key
                Button { settings.thinking = key } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: selected ? .medium : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected ? Color.primary.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .help("Response length and depth")
    }

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let session = history.selected {
                        if session.messages.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 24) {
                                ForEach(session.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        imageData: history.imageData(for: message)
                                    )
                                }
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: Layout.readingWidth)
                            .padding(.horizontal, Layout.gutter)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Color.clear.frame(height: 12).id("bottom")
                }
            }
            .modifier(ScrollAnchorModifier())
            .background(Color(nsColor: .textBackgroundColor))
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                autoScrollEnabled = false
            })
            .onTapGesture { autoScrollEnabled = true }
            .onChange(of: history.selected?.messages.count ?? 0) { _ in
                autoScrollEnabled = true
                scrollToBottom(proxy)
            }
            .onChange(of: history.selected?.messages.last?.text.count ?? 0) { _ in
                guard autoScrollEnabled else { return }
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: history.selected?.messages.last?.reasoning.count ?? 0) { _ in
                guard autoScrollEnabled else { return }
                scrollToBottom(proxy, animated: false)
            }
            .overlay(alignment: .bottomTrailing) {
                if !autoScrollEnabled && history.selected?.messages.isEmpty == false {
                    Button {
                        autoScrollEnabled = true
                        scrollToBottom(proxy)
                    } label: {
                        Label("Jump to bottom", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 4)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            logoView(size: 44).padding(.bottom, 4)
            Text("How can I help?").font(.title2.weight(.medium))
            Text("Chat with any compatible model. History stays on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                promptButton("Explain a concept")
                promptButton("Draft a message")
                promptButton("Review code")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private func promptButton(_ title: String) -> some View {
        Button(title) {
            input = title
            inputFocused = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let image = pendingImage, let preview = NSImage(data: image.data) {
                HStack(spacing: 8) {
                    Image(nsImage: preview)
                        .resizable().scaledToFit().frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(pendingImageName ?? "Image")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button {
                        pendingImage = nil
                        pendingImageName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Remove image")
                }
            }
            if let f = pendingFile {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundStyle(.secondary)
                    Text(pendingFileName ?? f.name)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button {
                        pendingFile = nil
                        pendingFileName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Remove file")
                }
            }

            HStack(alignment: .bottom, spacing: 4) {
                Menu {
                    Button("Add Image…") { pickImage() }
                    Button("Add File…") { pickFile() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14))
                        .frame(width: Layout.control, height: Layout.control)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .foregroundStyle(.secondary).fixedSize()
                .accessibilityLabel("Attach")

                TextField("Message OpenChat", text: $input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .frame(minHeight: Layout.control)

                if selectedIsActive {
                    Button { stopSelectedRequest() } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 22))
                            .frame(width: Layout.control, height: Layout.control)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Stop response")
                    .accessibilityLabel("Stop response")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .frame(width: Layout.control, height: Layout.control)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.4))
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        inputFocused ? Theme.accent.opacity(0.6) : Color(nsColor: .separatorColor),
                        lineWidth: inputFocused ? 1.5 : 0.5
                    )
            )

            HStack {
                if selectedIsActive {
                    ProgressView().controlSize(.mini)
                    Text("Generating with \(activeModel)")
                } else if let persistenceError = history.persistenceError {
                    Image(systemName: "exclamationmark.triangle")
                    Text(persistenceError)
                } else {
                    Image(systemName: "lock.shield")
                    Text(settings.apiKey.isEmpty ? "Local connection · no API key" : "API key secured in Keychain")
                }
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(history.persistenceError == nil ? Color.secondary : Color.orange)
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingImage != nil
            || pendingFile != nil
    }

    @ViewBuilder
    private func logoView(size: CGFloat) -> some View {
        if let path = Bundle.main.path(forResource: "Logo", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Theme.accent)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "bubble.left")
                        .font(.system(size: size * 0.45)).foregroundColor(.white)
                )
        }
    }

    private func selectModel(_ model: String) {
        settings.model = model
        if let id = history.selectedID { history.setModel(model, for: id) }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, let sessionID = history.selectedID else { return }
        let model = activeModel
        if history.selected?.model.isEmpty == true {
            history.setModel(model, for: sessionID)
        }

        let userID = UUID()
        var enrichedText = text
        if let f = pendingFile {
            let excerpt = String(f.content.prefix(8000))
            enrichedText += "\n\n[Attached file: \(f.name)]\n\(excerpt)"
        }
        let userMessage = ChatMessage(id: userID, role: "user", text: enrichedText)
        guard history.append(userMessage, to: sessionID) else { return }
        do {
            if let image = pendingImage {
                try history.attachImage(image, to: userID, in: sessionID)
            }
        } catch {
            history.removeMessage(sessionID: sessionID, messageID: userID)
            errorMsg = error.localizedDescription
            return
        }

        let style = settings.thinking
        input = ""
        pendingImage = nil
        pendingImageName = nil
        pendingFile = nil
        pendingFileName = nil

        requests.start(sessionID: sessionID) {
            await performRequest(
                sessionID: sessionID,
                userMessageID: userID,
                originalText: enrichedText,
                model: model,
                responseStyle: style
            )
        }
    }

    @MainActor
    private func performRequest(
        sessionID: UUID,
        userMessageID: UUID,
        originalText: String,
        model: String,
        responseStyle: String
    ) async {
        let client = OpenAIClient(baseURL: settings.baseURL, apiKey: settings.apiKey)

        guard var messages = makeAPIMessages(
            sessionID: sessionID,
            latestUserID: userMessageID,
            responseStyle: responseStyle
        ) else { return }

        let assistantID = UUID()
        guard history.append(
            ChatMessage(id: assistantID, role: "assistant", text: ""),
            to: sessionID
        ) else { return }

        var pendingContent = ""
        var pendingReasoning = ""
        var lastFlush = ContinuousClock.now
        func flushChunks() {
            guard !pendingContent.isEmpty || !pendingReasoning.isEmpty else { return }
            let content = pendingContent
            let reasoning = pendingReasoning
            pendingContent = ""
            pendingReasoning = ""
            history.updateMessage(sessionID: sessionID, messageID: assistantID) {
                $0.text += content
                $0.reasoning += reasoning
            }
            lastFlush = .now
        }

        // Tool loop: stream, execute tools, re-stream up to 5 turns
        var apiMessages = messages
        var toolRounds = 0
        outer: while toolRounds < 5 {
            var accToolCalls: [Int: (id: String, name: String, args: String)] = [:]
            var finishReason: String?
            do {
                try await client.streamChat(model: model, messages: apiMessages, responseStyle: responseStyle, tools: LocalTools.all) { chunk in
                    if let tc = chunk.toolCalls {
                        for t in tc {
                            let idx = t.index ?? 0
                            var cur = accToolCalls[idx] ?? (id: "", name: "", args: "")
                            if let id = t.id { cur.id = id }
                            if let n = t.function?.name { cur.name += n }
                            if let a = t.function?.arguments { cur.args += a }
                            accToolCalls[idx] = cur
                        }
                    }
                    if let fr = chunk.finishReason { finishReason = fr }
                    pendingContent += chunk.content ?? ""
                    pendingReasoning += chunk.reasoning ?? ""
                    if lastFlush.duration(to: .now) >= .milliseconds(50) { flushChunks() }
                }
                flushChunks()
            } catch is CancellationError {
                flushChunks(); removeAssistantIfEmpty(sessionID: sessionID, messageID: assistantID); break outer
            } catch {
                flushChunks(); removeAssistantIfEmpty(sessionID: sessionID, messageID: assistantID)
                errorMsg = error.localizedDescription; break outer
            }
            let hasTools = accToolCalls.values.contains { !$0.name.isEmpty }
            if finishReason == "tool_calls" || hasTools {
                let calls = accToolCalls.sorted(by: { $0.key < $1.key }).compactMap { _, v -> ToolCallParam? in
                    guard !v.name.isEmpty else { return nil }
                    return ToolCallParam(id: v.id.isEmpty ? UUID().uuidString : v.id, function: .init(name: v.name, arguments: v.args.isEmpty ? "{}" : v.args))
                }
                if calls.isEmpty { break }
                // Show tool activity
                let names = calls.map { $0.function.name }.joined(separator: ", ")
                history.updateMessage(sessionID: sessionID, messageID: assistantID) { $0.text += "\n*Using \(names)…*\n" }
                apiMessages.append(APIMessage(assistantToolCalls: calls))
                for c in calls {
                    let args = (try? JSONDecoder().decode([String: String].self, from: c.function.arguments.data(using: String.Encoding.utf8) ?? Data())) ?? [:]
                    var dict: [String: String] = [:]
                    if let data = c.function.arguments.data(using: String.Encoding.utf8), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        for (k, v) in obj { dict[k] = "\(v)" }
                    }
                    let result = await LocalTools.dispatch(name: c.function.name, args: dict.merging(args) { a,_ in a })
                    apiMessages.append(APIMessage(toolResult: result, toolCallId: c.id))
                }
                toolRounds += 1
                continue
            }
            break
        }
    }

    private func makeAPIMessages(
        sessionID: UUID,
        latestUserID: UUID,
        responseStyle: String
    ) -> [APIMessage]? {
        guard let session = history.session(sessionID) else { return nil }
        return session.messages.compactMap { message in
            if message.role == "assistant" {
                guard !message.text.isEmpty else { return nil }
                return APIMessage(role: "assistant", content: .text(message.text))
            }
            guard message.role == "user" else { return nil }
            var text = message.text
            if message.id == latestUserID {
                if responseStyle == "low" { text += "\n\nPlease answer concisely." }
                if responseStyle == "high" { text += "\n\nPlease give a careful, thorough answer." }
            }
            var parts: [APIContentPart] = []
            if !text.isEmpty { parts.append(.text(text)) }
            // Avoid retransmitting every historical image on every turn.
            if message.id == latestUserID,
               let data = history.imageData(for: message) {
                parts.append(
                    .image(
                        data: data,
                        mimeType: message.imageMimeType ?? "image/jpeg"
                    )
                )
            }
            guard !parts.isEmpty else { return nil }
            if parts.count == 1, message.imageFilename == nil {
                return APIMessage(role: "user", content: .text(text))
            }
            return APIMessage(role: "user", content: .parts(parts))
        }
    }

    private func removeAssistantIfEmpty(sessionID: UUID, messageID: UUID) {
        guard let message = history.session(sessionID)?
            .messages.first(where: { $0.id == messageID }),
              message.text.isEmpty, message.reasoning.isEmpty else { return }
        history.removeMessage(sessionID: sessionID, messageID: messageID)
    }

    private func stopSelectedRequest() {
        guard let sessionID = history.selectedID else { return }
        requests.cancel(sessionID: sessionID)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png, .heic, .webP]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            pendingImage = try MediaProcessor.prepareImage(Data(contentsOf: url))
            pendingImageName = url.lastPathComponent
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .pdf, .commaSeparatedText, .json, .swiftSource, UTType(filenameExtension: "md")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [] // allow any
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 5 * 1024 * 1024 else { throw MediaError.fileTooLarge }
            let content = String(data: data, encoding: .utf8) ?? "[Binary file: \(url.lastPathComponent) - \(data.count) bytes]"
            pendingFile = PickedFile(name: url.lastPathComponent, content: content)
            pendingFileName = url.lastPathComponent
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    do {
                        pendingImage = try MediaProcessor.prepareImage(data)
                        pendingImageName = "Dropped image"
                    } catch {
                        errorMsg = error.localizedDescription
                    }
                }
            }
            break
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct ScrollAnchorModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.defaultScrollAnchor(.bottom)
        } else {
            content
        }
    }
}

private enum Layout {
    static let readingWidth: CGFloat = 760
    static let gutter: CGFloat = 24
    static let control: CGFloat = 28
}

private struct MessageBubble: View {
    let message: ChatMessage
    let imageData: Data?
    @State private var showReasoning = false
    @State private var copied = false

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        if isUser { userBody } else { assistantBody }
    }

    private var userBody: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 14.5)).lineSpacing(3).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contextMenu { copyButton }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button { showReasoning.toggle() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .rotationEffect(.degrees(showReasoning ? 90 : 0))
                            Text(message.text.isEmpty ? "Working…" : "Model reasoning")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    if showReasoning {
                        Text(message.reasoning)
                            .font(.system(size: 12.5)).foregroundStyle(.secondary)
                            .lineSpacing(3).textSelection(.enabled)
                            .padding(.leading, 12)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 2)
                            }
                    }
                }
            }
            if !message.text.isEmpty {
                MarkdownView(text: message.text)
                    .contextMenu { copyButton }
                Button(copied ? "Copied" : "Copy response", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    copyText()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if message.reasoning.isEmpty {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var copyButton: some View {
        Button("Copy") { copyText() }
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

struct PickedFile { let name: String; let content: String }
