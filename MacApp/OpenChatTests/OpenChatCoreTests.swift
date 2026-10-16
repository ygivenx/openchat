import Foundation
import XCTest
@testable import OpenChatCore

final class OpenChatCoreTests: XCTestCase {
    func testSSEErrorIsParsedWithoutChoices() throws {
        let data = Data(#"{"error":{"message":"model unavailable"}}"#.utf8)
        XCTAssertThrowsError(try OpenAIClient.parseSSEPayload(data)) { error in
            XCTAssertEqual(error as? OpenAIClientError, .api("model unavailable"))
        }
    }

    func testSSEReasoningCompatibilityFields() throws {
        let data = Data(
            #"{"choices":[{"delta":{"content":"answer","reasoning_content":"work"}}]}"#.utf8
        )
        let chunk = try OpenAIClient.parseSSEPayload(data)
        XCTAssertEqual(chunk?.content, "answer")
        XCTAssertEqual(chunk?.reasoning, "work")
    }

    @MainActor
    func testUpdatesUseSessionAndMessageIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenChatTests-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "OpenChatTests-\(UUID().uuidString)")!
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChatStore(baseDirectory: directory, defaults: defaults)
        let firstSession = try XCTUnwrap(store.selectedID)
        let firstMessage = ChatMessage(role: "assistant", text: "")
        XCTAssertTrue(store.append(firstMessage, to: firstSession))

        store.newChat(model: "other")
        XCTAssertTrue(
            store.updateMessage(sessionID: firstSession, messageID: firstMessage.id) {
                $0.text = "correct chat"
            }
        )

        XCTAssertEqual(
            store.session(firstSession)?.messages.first?.text,
            "correct chat"
        )
        XCTAssertTrue(store.selected?.messages.isEmpty == true)
    }

    @MainActor
    func testStaleSelectionFallsBackToExistingSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenChatTests-\(UUID().uuidString)", isDirectory: true)
        let suite = "OpenChatTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(UUID().uuidString, forKey: "openchat.selectedID")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }

        let store = ChatStore(baseDirectory: directory, defaults: defaults)
        XCTAssertNotNil(store.selected)
    }

    @MainActor
    func testReplacedRequestCannotClearNewRequestState() async {
        let controller = ChatRequestController()
        let sessionID = UUID()
        controller.start(sessionID: sessionID) {
            try? await Task.sleep(for: .milliseconds(100))
        }
        controller.start(sessionID: sessionID) {
            try? await Task.sleep(for: .seconds(1))
        }

        await Task.yield()
        XCTAssertTrue(controller.isActive(sessionID))
        controller.cancelAll()
    }
}
