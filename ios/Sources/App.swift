import SwiftUI

@main
struct RemoteControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var client = RemoteClient()
    @State private var serverURL = "ws://168.144.36.51:8081"
    @State private var targetId = ""
    @State private var targetPassword = ""
    @State private var personalPassword = ""
    @State private var showServerAlert = false
    @State private var showHelpAlert = false

    var body: some View {
        Group {
            if client.isControlling {
                RemoteDesktopView(client: client)
            } else {
                UltraViewerHomeView(
                    client: client,
                    serverURL: $serverURL,
                    targetId: $targetId,
                    targetPassword: $targetPassword,
                    personalPassword: $personalPassword,
                    showServerAlert: $showServerAlert,
                    showHelpAlert: $showHelpAlert
                )
            }
        }
        .alert("Thông báo", isPresented: Binding(
            get: { client.errorMessage != nil },
            set: { if !$0 { client.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { client.errorMessage = nil }
        } message: {
            Text(client.errorMessage ?? "")
        }
    }
}

struct UltraViewerHomeView: View {
    @ObservedObject var client: RemoteClient
    @Binding var serverURL: String
    @Binding var targetId: String
    @Binding var targetPassword: String
    @Binding var personalPassword: String
    @Binding var showServerAlert: Bool
    @Binding var showHelpAlert: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top blue window title bar
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .foregroundColor(.white)
                    .font(.system(size: 13))
                Text("UltraViewer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.25, green: 0.50, blue: 0.80), Color(red: 0.45, green: 0.67, blue: 0.88)],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Menu bar: Tệp tin | Thiết lập | Trợ giúp
            HStack(spacing: 18) {
                Button("Tệp tin") {
                    client.myPassword = String(Int.random(in: 1000...9999))
                }
                Button("Thiết lập") { showServerAlert = true }
                Button("Trợ giúp") { showHelpAlert = true }
                Spacer()
            }
            .font(.system(size: 12))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(red: 0.84, green: 0.89, blue: 0.95))

            // Banner strip with round blue monitor icon
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.93, green: 0.91, blue: 0.85))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.35), lineWidth: 1))
                    .frame(height: 36)
                    .padding(.leading, 22)

                HStack {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.14, green: 0.46, blue: 0.79))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        Image(systemName: "desktopcomputer")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    }
                    Spacer()
                    Button {
                        showHelpAlert = true
                    } label: {
                        Image(systemName: "questionmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.14, green: 0.46, blue: 0.79))
                            .frame(width: 24, height: 24)
                            .background(Color.white)
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4)))
                    }
                    .padding(.trailing, 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Main body (responsive 2-column or stacked on narrow iPhone)
            ScrollView {
                HStack(alignment: .top, spacing: 14) {
                    // Left column: Cho phép điều khiển
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(Color(red: 0.14, green: 0.46, blue: 0.79))
                            Text("Cho phép điều khiển")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.11, green: 0.46, blue: 0.74))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color(red: 0.93, green: 0.95, blue: 0.97))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.35)))

                        Text("Hãy gửi ID và Mật khẩu dưới đây cho đối tác nếu bạn muốn cho họ điều khiển máy tính của mình")
                            .font(.system(size: 10.5))
                            .foregroundColor(.black.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text("ID của bạn")
                                .font(.system(size: 11.5))
                                .frame(width: 72, alignment: .leading)
                            Text(client.myId)
                                .font(.system(size: 12.5, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
                        }

                        HStack {
                            Text("Mật khẩu")
                                .font(.system(size: 11.5))
                                .frame(width: 72, alignment: .leading)
                            Text(client.myPassword)
                                .font(.system(size: 12.5, weight: .bold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(5)
                                .background(Color(white: 0.94))
                                .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
                        }

                        Divider().padding(.vertical, 2)

                        HStack {
                            Text("Mật khẩu\nriêng")
                                .font(.system(size: 11))
                                .frame(width: 72, alignment: .leading)
                            SecureField("", text: $personalPassword)
                                .font(.system(size: 12))
                                .padding(5)
                                .background(Color(white: 0.94))
                                .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
                            Button {
                                if !personalPassword.isEmpty {
                                    client.myPassword = personalPassword
                                }
                            } label: {
                                Image(systemName: "key.fill")
                                    .foregroundColor(.orange)
                                    .padding(6)
                                    .background(Color.white)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.5)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider()

                    // Right column: Điều khiển máy tính khác
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .foregroundColor(Color(red: 0.14, green: 0.46, blue: 0.79))
                            Text("Điều khiển máy tính khác")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(red: 0.11, green: 0.46, blue: 0.74))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color(red: 0.93, green: 0.95, blue: 0.97))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.gray.opacity(0.35)))

                        Text("Hãy nhập ID và Mật khẩu của máy bạn cần điều khiển")
                            .font(.system(size: 10.5))
                            .foregroundColor(.black.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            Text("ID đối tác")
                                .font(.system(size: 11.5))
                                .frame(width: 66, alignment: .leading)
                            TextField("VD: 528192", text: $targetId)
                                .keyboardType(.numberPad)
                                .font(.system(size: 12.5))
                                .padding(5)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
                        }

                        HStack {
                            Text("Mật khẩu")
                                .font(.system(size: 11.5))
                                .frame(width: 66, alignment: .leading)
                            TextField("Mật khẩu", text: $targetPassword)
                                .font(.system(size: 12.5))
                                .padding(5)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.gray.opacity(0.5)))
                        }

                        Button {
                            client.connectToPartner(
                                serverURL: serverURL,
                                targetId: targetId,
                                password: targetPassword
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(Color(red: 0.14, green: 0.46, blue: 0.79))
                                    .font(.system(size: 12, weight: .bold))
                                Text("Bắt đầu điều khiển")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.92, green: 0.94, blue: 0.96))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.6)))
                        }
                        .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Spacer()

            // Bottom status bar
            HStack {
                Circle()
                    .fill(client.isReady ? Color.green : Color.orange)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 0.5))
                Text(client.status)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                Spacer()
                Text("Copyright DucFabulous Co,ltd")
                    .font(.system(size: 10))
                    .underline()
                    .foregroundColor(Color(red: 0.16, green: 0.38, blue: 0.72))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(red: 0.91, green: 0.93, blue: 0.97))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.3)), alignment: .top)
        }
        .background(Color(red: 0.95, green: 0.96, blue: 0.98))
        .alert("Thiết lập Server", isPresented: $showServerAlert) {
            TextField("ws://168.144.36.51:8081", text: $serverURL)
            Button("Lưu", role: .cancel) {}
        } message: {
            Text("Nhập địa chỉ WebSocket Server")
        }
        .alert("Trợ giúp", isPresented: $showHelpAlert) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text("Server hiện tại:\n\(serverURL)\n\nChạy ultraviewer_pc.py trên PC để lấy ID và Mật khẩu rồi nhập vào mục Điều khiển máy tính khác.")
        }
    }
}

struct RemoteDesktopView: View {
    @ObservedObject var client: RemoteClient
    @State private var textInput = ""
    @State private var showKeyboard = false
    @State private var dragStart: CGPoint = .zero

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Circle().fill(Color.green).frame(width: 9, height: 9)
                Text(client.status)
                    .font(.caption)
                    .foregroundColor(.white)
                Spacer()
                Button("Ngắt kết nối") {
                    client.disconnect()
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.85))
                .cornerRadius(4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(red: 0.13, green: 0.25, blue: 0.42))

            // Remote PC Screen
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let img = client.currentFrame {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        ProgressView("Đang chờ hình ảnh từ PC...")
                            .foregroundColor(.white)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            if dragStart == .zero { dragStart = val.startLocation }
                        }
                        .onEnded { val in
                            let p1 = normalizePoint(dragStart, container: geo.size, imageSize: client.currentFrame?.size)
                            let p2 = normalizePoint(val.location, container: geo.size, imageSize: client.currentFrame?.size)
                            dragStart = .zero
                            if abs(p2.x - p1.x) < 0.015 && abs(p2.y - p1.y) < 0.015 {
                                client.sendClick(x: p2.x, y: p2.y)
                            } else {
                                client.sendDrag(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y)
                            }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            client.sendRightClick(x: 0.5, y: 0.5)
                        }
                )
            }

            if showKeyboard {
                HStack(spacing: 6) {
                    TextField("Gõ văn bản gửi tới PC...", text: $textInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Gửi") {
                        client.sendText(textInput)
                        textInput = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(6)
                .background(Color(white: 0.92))
            }

            // Bottom toolbar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button("⌨️ Phím") { showKeyboard.toggle() }
                    Button("Enter") { client.sendKey("enter") }
                    Button("⌫") { client.sendKey("backspace") }
                    Button("Esc") { client.sendKey("esc") }
                    Button("Win") { client.sendKey("win") }
                    Button("▲ Cuộn") { client.sendScroll(dy: 4) }
                    Button("▼ Cuộn") { client.sendScroll(dy: -4) }
                    Button("Chuột phải") { client.sendRightClick(x: 0.5, y: 0.5) }
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color(red: 0.16, green: 0.22, blue: 0.31))
        }
    }

    private func normalizePoint(_ pt: CGPoint, container: CGSize, imageSize: CGSize?) -> CGPoint {
        guard let imgSize = imageSize, imgSize.width > 0, imgSize.height > 0 else {
            return CGPoint(x: pt.x / max(container.width, 1), y: pt.y / max(container.height, 1))
        }
        let scale = min(container.width / imgSize.width, container.height / imgSize.height)
        let dispW = imgSize.width * scale
        let dispH = imgSize.height * scale
        let offX = (container.width - dispW) / 2
        let offY = (container.height - dispH) / 2
        return CGPoint(x: (pt.x - offX) / max(dispW, 1), y: (pt.y - offY) / max(dispH, 1))
    }
}
