import Foundation
import UIKit

final class RemoteClient: NSObject, ObservableObject {
    @Published var status: String = "Sẵn sàng kết nối"
    @Published var isReady: Bool = true
    @Published var isControlling: Bool = false
    @Published var errorMessage: String?
    @Published var currentFrame: UIImage?
    @Published var myId: String = String(Int.random(in: 100000...999999))
    @Published var myPassword: String = String(Int.random(in: 1000...9999))

    private var wsTask: URLSessionWebSocketTask?

    func connectToPartner(serverURL: String, targetId: String, password: String) {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tid = targetId.trimmingCharacters(in: .whitespacesAndNewlines)
        let pw = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedURL) else {
            errorMessage = "Địa chỉ server không hợp lệ"
            return
        }
        guard !tid.isEmpty, !pw.isEmpty else {
            errorMessage = "Vui lòng nhập ID đối tác và Mật khẩu"
            return
        }

        wsTask?.cancel()
        currentFrame = nil
        errorMessage = nil
        status = "Đang kết nối tới \(tid)..."
        isReady = false

        wsTask = URLSession.shared.webSocketTask(with: url)
        wsTask?.resume()
        sendJSON(["type": "connect", "targetId": tid, "password": pw])
        receiveLoop()
    }

    func disconnect() {
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        DispatchQueue.main.async {
            self.isControlling = false
            self.currentFrame = nil
            self.status = "Sẵn sàng kết nối"
            self.isReady = true
        }
    }

    func sendClick(x: Double, y: Double) {
        sendJSON(["type": "click", "x": clamp(x), "y": clamp(y)])
    }

    func sendRightClick(x: Double, y: Double) {
        sendJSON(["type": "rightclick", "x": clamp(x), "y": clamp(y)])
    }

    func sendDoubleClick(x: Double, y: Double) {
        sendJSON(["type": "dblclick", "x": clamp(x), "y": clamp(y)])
    }

    func sendMove(x: Double, y: Double) {
        sendJSON(["type": "move", "x": clamp(x), "y": clamp(y)])
    }

    func sendDrag(x1: Double, y1: Double, x2: Double, y2: Double) {
        sendJSON([
            "type": "drag",
            "x1": clamp(x1), "y1": clamp(y1),
            "x2": clamp(x2), "y2": clamp(y2)
        ])
    }

    func sendScroll(dy: Int) {
        sendJSON(["type": "scroll", "dy": dy])
    }

    func sendKey(_ key: String) {
        sendJSON(["type": "key", "key": key])
    }

    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        sendJSON(["type": "text", "text": text])
    }

    private func clamp(_ v: Double) -> Double {
        min(max(v, 0.0), 1.0)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        wsTask?.send(.string(str)) { _ in }
    }

    private func receiveLoop() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.data(let data)):
                if let img = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.currentFrame = img
                    }
                }
            case .success(.string(let text)):
                if let data = text.data(using: .utf8),
                   let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let type = msg["type"] as? String {
                    DispatchQueue.main.async {
                        switch type {
                        case "connected":
                            self.isControlling = true
                            self.isReady = true
                            self.status = "Đang điều khiển PC: \(msg["targetId"] ?? "")"
                        case "error":
                            self.errorMessage = msg["message"] as? String ?? "Lỗi kết nối"
                            self.isControlling = false
                            self.isReady = true
                            self.status = "Sẵn sàng kết nối"
                        case "host-disconnected":
                            self.errorMessage = "Máy đối tác đã ngắt kết nối"
                            self.isControlling = false
                            self.currentFrame = nil
                            self.isReady = true
                            self.status = "Sẵn sàng kết nối"
                        default:
                            break
                        }
                    }
                }
            case .failure(let err):
                DispatchQueue.main.async {
                    self.isControlling = false
                    self.isReady = true
                    self.status = "Lỗi: \(err.localizedDescription)"
                }
                return
            @unknown default:
                break
            }
            self.receiveLoop()
        }
    }
}
