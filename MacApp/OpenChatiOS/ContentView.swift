import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var history: ChatHistory
    @EnvironmentObject var requests: ChatRequestController
    @State private var input = ""
    @State private var pendingImage: Data?
    @State private var pendingFile: PickedFile?
    @State private var errorMsg: String?
    @State private var showSettings = false
    @State private var showPhotoPicker = false
    @State private var showFilePicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                chatList
                composer
            }
            .navigationTitle(history.selectedSession?.title ?? "OpenChat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(history.sessions) { s in
                            Button(s.title) { history.selectedID = s.id }
                        }
                        Button("New Chat", systemImage: "plus") { _ = history.createSession() }
                    } label: { Image(systemName: "line.3.horizontal") }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView().environmentObject(settings) }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        pendingImage = try? MediaProcessor.prepareImage(data)
                    }
                }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.plainText, .pdf, .json]) { result in
                if case .success(let url) = result, let data = try? Data(contentsOf: url) {
                    guard data.count <= 5*1024*1024 else { errorMsg = "File too large"; return }
                    let text = String(data: data, encoding: .utf8) ?? "[Binary \(data.count) bytes]"
                    pendingFile = PickedFile(name: url.lastPathComponent, content: text)
                }
            }
            .alert("Error", isPresented: .constant(errorMsg != nil)) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(history.selectedSession?.messages ?? []) { m in
                        MessageBubble(message: m, imageData: history.imageData(for: m))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }.padding()
            }
            .onChange(of: history.selectedSession?.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let img = pendingImage, let ui = UIImage(data: img) {
                HStack {
                    Image(uiImage: ui).resizable().scaledToFit().frame(height: 60).cornerRadius(6)
                    Spacer()
                    Button("Remove") { pendingImage = nil }.font(.caption)
                }
            }
            if let f = pendingFile {
                HStack { Label(f.name, systemImage: "doc.text"); Spacer(); Button("Remove") { pendingFile = nil } }.font(.caption)
            }
            HStack(spacing: 8) {
                Menu {
                    Button("Photo", systemImage: "photo") { showPhotoPicker = true }
                    Button("File", systemImage: "doc") { showFilePicker = true }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }

                TextField("Message...", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)

                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }.disabled(input.trimmingCharacters(in: .whitespaces).isEmpty && pendingImage == nil && pendingFile == nil)
            }
        }.padding().background(.bar)
    }

    private func send() {
        let text: String
        if let f = pendingFile {
            text = input + "\n\n[Attached file: \(f.name)]\n\(String(f.content.prefix(8000)))"
            pendingFile = nil
        } else { text = input }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil else { return }
        let imgData = pendingImage
        pendingImage = nil; input = ""
        let sid = history.selectedID ?? history.createSession().id
        let uid = UUID()
        history.append(ChatMessage(id: uid, role: "user", text: text, imageData: imgData), to: sid)
        Task { await performRequest(sessionID: sid, userMessageID: uid, model: settings.model) }
    }

    private func performRequest(sessionID: UUID, userMessageID: UUID, model: String) async {
        let client = OpenAIClient(baseURL: settings.baseURL, apiKey: settings.apiKey)
        guard var messages = makeAPIMessages(sessionID: sessionID, latestUserID: userMessageID) else { return }
        let aid = UUID()
        guard history.append(ChatMessage(id: aid, role: "assistant", text: ""), to: sessionID) else { return }
        var pending = ""
        var pendingReasoning = ""
        // Simple tool loop (same as macOS)
        var rounds = 0
        var apiMessages = messages
        while rounds < 5 {
            var toolCalls: [Int: (id: String, name: String, args: String)] = [:]
            var finish: String?
            do {
                try await client.streamChat(model: model, messages: apiMessages, responseStyle: settings.responseStyle, tools: LocalTools.all) { chunk in
                    if let tc = chunk.toolCalls { for t in tc { let i = t.index ?? 0; var c = toolCalls[i] ?? ("","",""); if let id=t.id {c.0=id}; if let n=t.function?.name {c.1+=n}; if let a=t.function?.arguments {c.2+=a}; toolCalls[i]=c } }
                    if let f=chunk.finishReason { finish=f }
                    pending += chunk.content ?? ""; pendingReasoning += chunk.reasoning ?? ""
                    history.updateMessage(sessionID: sessionID, messageID: aid) { $0.text = pending; $0.reasoning = pendingReasoning }
                }
            } catch { errorMsg = error.localizedDescription; break }
            let hasTools = toolCalls.values.contains { !$0.1.isEmpty }
            if finish == "tool_calls" || hasTools {
                let calls = toolCalls.sorted(by: {$0.key<$1.key}).compactMap { _,v -> ToolCallParam? in guard !v.1.isEmpty else {return nil}; return ToolCallParam(id: v.0.isEmpty ? UUID().uuidString : v.0, function: .init(name: v.1, arguments: v.2.isEmpty ? "{}" : v.2)) }
                if calls.isEmpty { break }
                apiMessages.append(APIMessage(assistantToolCalls: calls))
                for c in calls {
                    var dict: [String:String]=[:]
                    if let d=c.function.arguments.data(using: .utf8), let o=try? JSONSerialization.jsonObject(with: d) as? [String:Any] { for (k,v) in o { dict[k]="\(v)" } }
                    let res = await LocalTools.dispatch(name: c.function.name, args: dict)
                    apiMessages.append(APIMessage(toolResult: res, toolCallId: c.id))
                }
                rounds+=1; continue
            }
            break
        }
    }

    private func makeAPIMessages(sessionID: UUID, latestUserID: UUID) -> [APIMessage]? {
        guard let s = history.session(sessionID) else { return nil }
        return s.messages.compactMap { m in
            if m.role == "assistant" { return m.text.isEmpty ? nil : APIMessage(role: "assistant", content: .text(m.text)) }
            guard m.role == "user" else { return nil }
            var parts: [APIContentPart]=[]
            if !m.text.isEmpty { parts.append(.text(m.text)) }
            if m.id == latestUserID, let d = history.imageData(for: m) { parts.append(.image(data: d, mimeType: "image/jpeg")) }
            if parts.count==1 && m.imageData == nil { return APIMessage(role: "user", content: .text(m.text)) }
            return parts.isEmpty ? nil : APIMessage(role: "user", content: .parts(parts))
        }
    }
}

struct PickedFile { let name:String; let content:String }

struct MessageBubble: View {
    let message: ChatMessage; let imageData: Data?
    var body: some View {
        Group {
            if message.role == "user" {
                VStack(alignment: .trailing, spacing: 6) {
                    if let d=imageData, let ui=UIImage(data: d) { Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 200).cornerRadius(8) }
                    if !message.text.isEmpty { Text(message.text).padding(10).background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 10)).frame(maxWidth: .infinity, alignment: .trailing) }
                }.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !message.reasoning.isEmpty { DisclosureGroup("Reasoning") { Text(message.reasoning).font(.caption).foregroundStyle(.secondary) } }
                    if message.text.isEmpty && message.reasoning.isEmpty { ProgressView() } else { MarkdownView(text: message.text) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
