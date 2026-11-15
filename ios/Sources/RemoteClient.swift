import Foundation
import UIKit
import WebKit
import VideoToolbox
import CoreMedia
import CoreImage

final class RemoteClient: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var status: String = "Sẵn sàng kết nối"
    @Published var isReady: Bool = true
    @Published var isControlling: Bool = false
    @Published var errorMessage: String?
    @Published var currentFrame: UIImage?
    @Published var myId: String = RemoteClient.generateId9()
    @Published var myPassword: String = String(Int.random(in: 1000...9999))

    private var wsTask: URLSessionWebSocketTask?
    private let h264Decoder = H264HardwareDecoder()
    private var rtcWebView: WKWebView?
    private var rtcReady = false

    static func generateId9() -> String {
        let n = Int.random(in: 100000000...999999999)
        let s = String(n)
        let a = s.prefix(3)
        let b = s.dropFirst(3).prefix(3)
        let c = s.suffix(3)
        return "\(a) \(b) \(c)"
    }

    override init() {
        super.init()
        h264Decoder.onFrame = { [weak self] img in
            DispatchQueue.main.async {
                self?.currentFrame = img
            }
        }
        setupWebRTCEngine()
    }

    private func setupWebRTCEngine() {
        DispatchQueue.main.async {
            let cfg = WKWebViewConfiguration()
            cfg.userContentController.add(self, name: "rtcBridge")
            let wv = WKWebView(frame: .zero, configuration: cfg)
            let html = """
            <!doctype html><html><script>
            let pc = null, dc = null;
            function initPeer(ice) {
              pc = new RTCPeerConnection({ iceServers: ice || [{ urls: 'stun:stun.l.google.com:19302' }] });
              dc = pc.createDataChannel('control', { ordered: false, maxRetransmits: 0 });
              pc.onicecandidate = e => {
                if (e.candidate) window.webkit.messageHandlers.rtcBridge.postMessage({ type: 'ice-candidate', candidate: e.candidate });
              };
              pc.createOffer().then(o => pc.setLocalDescription(o)).then(() => {
                window.webkit.messageHandlers.rtcBridge.postMessage({ type: 'sdp-offer', sdp: pc.localDescription });
              }).catch(() => {});
            }
            function sendDC(obj) {
              if (dc && dc.readyState === 'open') { dc.send(JSON.stringify(obj)); return true; }
              return false;
            }
            function handleSignal(msg) {
              if (!pc) return;
              if (msg.type === 'sdp-answer' && msg.sdp) pc.setRemoteDescription(new RTCSessionDescription(msg.sdp)).catch(() => {});
              if (msg.type === 'ice-candidate' && msg.candidate) pc.addIceCandidate(new RTCIceCandidate(msg.candidate)).catch(() => {});
            }
            </script></html>
            """
            wv.loadHTMLString(html, baseURL: nil)
            self.rtcWebView = wv
            self.rtcReady = true
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        sendJSON(body)
    }

    func connectToPartner(serverURL: String, targetId: String, password: String) {
        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let tid = targetId.replacingOccurrences(of: " ", with: "")
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

    func sendClick(x: Double, y: Double) { sendControl(["type": "click", "x": clamp(x), "y": clamp(y)]) }
    func sendRightClick(x: Double, y: Double) { sendControl(["type": "rightclick", "x": clamp(x), "y": clamp(y)]) }
    func sendDoubleClick(x: Double, y: Double) { sendControl(["type": "dblclick", "x": clamp(x), "y": clamp(y)]) }
    func sendMove(x: Double, y: Double) { sendControl(["type": "move", "x": clamp(x), "y": clamp(y)]) }
    func sendDrag(x1: Double, y1: Double, x2: Double, y2: Double) {
        sendControl(["type": "drag", "x1": clamp(x1), "y1": clamp(y1), "x2": clamp(x2), "y2": clamp(y2)])
    }
    func sendScroll(dy: Int) { sendControl(["type": "scroll", "dy": dy]) }
    func sendKey(_ key: String) { sendControl(["type": "key", "key": key]) }
    func sendText(_ text: String) {
        guard !text.isEmpty else { return }
        sendControl(["type": "text", "text": text])
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0.0), 1.0) }

    private func sendControl(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        if rtcReady, let wv = rtcWebView {
            DispatchQueue.main.async {
                wv.evaluateJavaScript("sendDC(\(str))") { res, _ in
                    if (res as? Bool) != true {
                        self.wsTask?.send(.string(str)) { _ in }
                    }
                }
            }
            return
        }
        wsTask?.send(.string(str)) { _ in }
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
                    DispatchQueue.main.async { self.currentFrame = img }
                } else {
                    self.h264Decoder.decodeAnnexB(data)
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
                            self.rtcWebView?.evaluateJavaScript("initPeer()", completionHandler: nil)
                        case "sdp-answer", "ice-candidate":
                            self.rtcWebView?.evaluateJavaScript("handleSignal(\(text))", completionHandler: nil)
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

private final class H264HardwareDecoder {
    var onFrame: ((UIImage) -> Void)?
    private var sps: Data?
    private var pps: Data?
    private var formatDesc: CMVideoFormatDescription?
    private var session: VTDecompressionSession?
    private let ciContext = CIContext()
    private let decodeQueue = DispatchQueue(label: "vt.h264.decode")

    func decodeAnnexB(_ data: Data) {
        decodeQueue.async { [weak self] in
            self?.processPacket(data)
        }
    }

    private func processPacket(_ data: Data) {
        let nalus = splitAnnexB(data)
        var frameNalus: [Data] = []
        var updated = false

        for nalu in nalus where !nalu.isEmpty {
            let t = nalu[0] & 0x1F
            if t == 7 && sps != nalu { sps = nalu; updated = true }
            else if t == 8 && pps != nalu { pps = nalu; updated = true }
            else if t == 1 || t == 5 { frameNalus.append(nalu) }
        }
        if updated { recreateSession() }
        guard let session, let formatDesc, !frameNalus.isEmpty else { return }

        var avcc = Data()
        for n in frameNalus {
            var len = UInt32(n.count).bigEndian
            avcc.append(Data(bytes: &len, count: 4))
            avcc.append(n)
        }

        var blockBuffer: CMBlockBuffer?
        let count = avcc.count
        let st = avcc.withUnsafeBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress else { return -1 }
            var bb: CMBlockBuffer?
            let err = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: count, flags: 0, blockBufferOut: &bb
            )
            guard err == kCMBlockBufferNoErr, let bb else { return err }
            blockBuffer = bb
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: bb, offsetIntoDestination: 0, dataLength: count)
        }
        guard st == kCMBlockBufferNoErr, let blockBuffer else { return }

        var sb: CMSampleBuffer?
        var sz = count
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, formatDescription: formatDesc,
            sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 1, sampleSizeArray: &sz, sampleBufferOut: &sb
        ) == noErr, let sb else { return }

        var flags = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sb, flags: [._1xRealTimePlayback], infoFlagsOut: &flags) { [weak self] status, _, buf, _, _ in
            guard status == noErr, let buf, let self else { return }
            let ci = CIImage(cvPixelBuffer: buf)
            guard let cg = self.ciContext.createCGImage(ci, from: ci.extent) else { return }
            self.onFrame?(UIImage(cgImage: cg))
        }
    }

    private func recreateSession() {
        guard let sps, let pps else { return }
        if let session { VTDecompressionSessionInvalidate(session); self.session = nil }
        formatDesc = nil
        var desc: CMVideoFormatDescription?
        let st = sps.withUnsafeBytes { sp in
            pps.withUnsafeBytes { pp in
                let ptrs = [sp.baseAddress!.assumingMemoryBound(to: UInt8.self), pp.baseAddress!.assumingMemoryBound(to: UInt8.self)]
                let sizes = [sps.count, pps.count]
                return ptrs.withUnsafeBufferPointer { pb in
                    sizes.withUnsafeBufferPointer { sb in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault, parameterSetCount: 2,
                            parameterSetPointers: pb.baseAddress!, parameterSetSizes: sb.baseAddress!,
                            nalUnitHeaderLength: 4, formatDescriptionOut: &desc
                        )
                    }
                }
            }
        }
        guard st == noErr, let desc else { return }
        formatDesc = desc
        let attrs: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: desc, decoderSpecification: nil, imageBufferAttributes: attrs as CFDictionary, outputCallback: nil, decompressionSessionOut: &session)
    }

    private func splitAnnexB(_ data: Data) -> [Data] {
        var res: [Data] = []
        let b = [UInt8](data)
        var i = 0, start: Int?
        while i < b.count {
            let s4 = i + 3 < b.count && b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 0 && b[i + 3] == 1
            let s3 = !s4 && i + 2 < b.count && b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1
            if s4 || s3 {
                if let st = start, st < i { res.append(Data(b[st..<i])) }
                i += s4 ? 4 : 3
                start = i
            } else { i += 1 }
        }
        if let st = start, st < b.count { res.append(Data(b[st..<b.count])) }
        return res
    }
}
