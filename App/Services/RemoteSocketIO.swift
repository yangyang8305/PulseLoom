import Foundation

@MainActor protocol RemoteSocketIO: AnyObject {
    func resume()
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    func receive() async throws -> URLSessionWebSocketTask.Message
    func cancel()
}

@MainActor final class AppleRemoteSocket: RemoteSocketIO {
    private let task: URLSessionWebSocketTask
    init(url: URL) { task = URLSession.shared.webSocketTask(with: url) }
    func resume() { task.resume() }
    func send(_ message: URLSessionWebSocketTask.Message) async throws { try await task.send(message) }
    func receive() async throws -> URLSessionWebSocketTask.Message { try await task.receive() }
    func cancel() { task.cancel(with: .goingAway, reason: nil) }
}
