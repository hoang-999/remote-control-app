import io
import json
import random
import threading
import time
import tkinter as tk
from tkinter import messagebox, simpledialog
import mss
import pyautogui
from PIL import Image, ImageTk
import websocket

pyautogui.FAILSAFE = False

DEFAULT_SERVER = "ws://168.144.36.51:8081"


class UltraViewerPC:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("UltraViewer")
        self.root.geometry("610x420")
        self.root.resizable(False, False)
        self.root.configure(bg="#F2F5FA")

        self.server_url = DEFAULT_SERVER
        self.my_id = str(random.randint(100000, 999999))
        self.my_pw = str(random.randint(1000, 9999))
        self.personal_pw = ""

        self.host_ws = None
        self.viewer_ws = None
        self.streaming = False
        self.viewer_count = 0

        self.remote_win = None
        self.remote_canvas = None
        self.remote_photo = None
        self.remote_img_size = (1, 1)

        self._build_ui()
        self.root.after(200, self.connect_host)

    def _build_ui(self):
        # Top menu strip
        menu_bar = tk.Frame(self.root, bg="#D7E2F1", height=24)
        menu_bar.pack(fill="x")
        for label, cmd in [
            ("Tệp tin", self.on_file_menu),
            ("Thiết lập", self.on_settings),
            ("Trợ giúp", lambda: messagebox.showinfo("Trợ giúp", f"Server: {self.server_url}")),
        ]:
            btn = tk.Button(
                menu_bar, text=label, bg="#D7E2F1", relief="flat",
                font=("Segoe UI", 9), padx=8, pady=1, command=cmd, cursor="hand2"
            )
            btn.pack(side="left")

        # Banner strip with blue monitor icon + help button
        banner = tk.Frame(self.root, bg="#F2F5FA", height=54)
        banner.pack(fill="x", padx=14, pady=(6, 2))
        strip = tk.Canvas(banner, height=42, bg="#ECE9D8", highlightthickness=1, highlightbackground="#D3CFC0")
        strip.pack(fill="x", pady=5)
        strip.create_oval(6, 2, 44, 40, fill="#2474C9", outline="#19599E", width=2)
        strip.create_rectangle(15, 12, 35, 26, fill="#FFFFFF", outline="#FFFFFF")
        strip.create_rectangle(17, 14, 33, 24, fill="#2474C9", outline="#2474C9")
        strip.create_rectangle(22, 26, 28, 30, fill="#FFFFFF", outline="#FFFFFF")
        strip.create_line(19, 31, 31, 31, fill="#FFFFFF", width=2)

        # Two-column body
        body = tk.Frame(self.root, bg="#F2F5FA")
        body.pack(fill="both", expand=True, padx=16, pady=4)

        left = tk.Frame(body, bg="#F2F5FA", width=275)
        left.pack(side="left", fill="both", expand=True)

        sep = tk.Frame(body, bg="#C8CED8", width=1)
        sep.pack(side="left", fill="y", padx=10, pady=10)

        right = tk.Frame(body, bg="#F2F5FA", width=275)
        right.pack(side="left", fill="both", expand=True)

        # Left Header: Cho phép điều khiển
        lh = tk.Label(
            left, text="📡  Cho phép điều khiển", bg="#EEF2F8", fg="#1B75BC",
            font=("Segoe UI", 11, "bold"), anchor="w", padx=8, pady=5,
            relief="groove", bd=1
        )
        lh.pack(fill="x", pady=(0, 8))
        tk.Label(
            left,
            text="Hãy gửi ID và Mật khẩu dưới đây cho đối tác nếu\nbạn muốn cho họ điều khiển máy tính của mình",
            bg="#F2F5FA", fg="#222222", font=("Segoe UI", 8.5), justify="left", anchor="w"
        ).pack(fill="x", pady=(0, 12))

        f_id = tk.Frame(left, bg="#F2F5FA")
        f_id.pack(fill="x", pady=4)
        tk.Label(f_id, text="ID của bạn", bg="#F2F5FA", font=("Segoe UI", 9.5), width=11, anchor="w").pack(side="left")
        self.var_my_id = tk.StringVar(value=self.my_id)
        tk.Entry(f_id, textvariable=self.var_my_id, state="readonly", font=("Segoe UI", 10, "bold"), width=18).pack(side="left")

        f_pw = tk.Frame(left, bg="#F2F5FA")
        f_pw.pack(fill="x", pady=4)
        tk.Label(f_pw, text="Mật khẩu", bg="#F2F5FA", font=("Segoe UI", 9.5), width=11, anchor="w").pack(side="left")
        self.var_my_pw = tk.StringVar(value=self.my_pw)
        tk.Entry(f_pw, textvariable=self.var_my_pw, state="readonly", font=("Segoe UI", 10, "bold"), width=18).pack(side="left")

        tk.Frame(left, bg="#D0D7E2", height=1).pack(fill="x", pady=14)

        f_ppw = tk.Frame(left, bg="#F2F5FA")
        f_ppw.pack(fill="x", pady=4)
        tk.Label(f_ppw, text="Mật khẩu\nriêng", bg="#F2F5FA", font=("Segoe UI", 9), width=11, anchor="w", justify="left").pack(side="left")
        self.var_personal_pw = tk.StringVar(value="")
        tk.Entry(f_ppw, textvariable=self.var_personal_pw, show="*", font=("Segoe UI", 10), width=14).pack(side="left")
        tk.Button(f_ppw, text="🔑", font=("Segoe UI", 9), command=self.apply_personal_pw, padx=5).pack(side="left", padx=4)

        # Right Header: Điều khiển máy tính khác
        rh = tk.Label(
            right, text="👤  Điều khiển máy tính khác", bg="#EEF2F8", fg="#1B75BC",
            font=("Segoe UI", 11, "bold"), anchor="w", padx=8, pady=5,
            relief="groove", bd=1
        )
        rh.pack(fill="x", pady=(0, 8))
        tk.Label(
            right,
            text="Hãy nhập ID và Mật khẩu của máy bạn cần điều\nkhiển",
            bg="#F2F5FA", fg="#222222", font=("Segoe UI", 8.5), justify="left", anchor="w"
        ).pack(fill="x", pady=(0, 12))

        f_tid = tk.Frame(right, bg="#F2F5FA")
        f_tid.pack(fill="x", pady=4)
        tk.Label(f_tid, text="ID đối tác", bg="#F2F5FA", font=("Segoe UI", 9.5), width=11, anchor="w").pack(side="left")
        self.ent_target_id = tk.Entry(f_tid, font=("Segoe UI", 10), width=18)
        self.ent_target_id.pack(side="left")

        f_tpw = tk.Frame(right, bg="#F2F5FA")
        f_tpw.pack(fill="x", pady=4)
        tk.Label(f_tpw, text="Mật khẩu", bg="#F2F5FA", font=("Segoe UI", 9.5), width=11, anchor="w").pack(side="left")
        self.ent_target_pw = tk.Entry(f_tpw, show="*", font=("Segoe UI", 10), width=18)
        self.ent_target_pw.pack(side="left")

        btn_connect = tk.Button(
            right, text="➔  Bắt đầu điều khiển", font=("Segoe UI", 9.5, "bold"),
            bg="#E9EEF5", fg="#1E395B", relief="raised", padx=12, pady=6,
            cursor="hand2", command=self.start_control
        )
        btn_connect.pack(pady=(18, 0), anchor="center")

        # Bottom Status Bar
        status_bar = tk.Frame(self.root, bg="#E8EEF7", height=28, bd=1, relief="sunken")
        status_bar.pack(fill="x", side="bottom")
        self.dot_canvas = tk.Canvas(status_bar, width=16, height=16, bg="#E8EEF7", highlightthickness=0)
        self.dot_canvas.pack(side="left", padx=(10, 4), pady=4)
        self.dot_id = self.dot_canvas.create_oval(2, 2, 14, 14, fill="#E0A800", outline="#7A5A00")

        self.lbl_status = tk.Label(status_bar, text="Đang kết nối máy chủ...", bg="#E8EEF7", fg="#222222", font=("Segoe UI", 9))
        self.lbl_status.pack(side="left")

        tk.Label(status_bar, text="Copyright DucFabulous Co,ltd", bg="#E8EEF7", fg="#2A62B6", font=("Segoe UI", 8.5, "underline")).pack(side="right", padx=12)

    def set_status(self, text: str, color: str = "#5CB85C"):
        self.root.after(0, lambda: (
            self.lbl_status.config(text=text),
            self.dot_canvas.itemconfig(self.dot_id, fill=color)
        ))

    def on_file_menu(self):
        self.my_pw = str(random.randint(1000, 9999))
        self.var_my_pw.set(self.my_pw)
        self.connect_host()

    def on_settings(self):
        url = simpledialog.askstring("Thiết lập Server", "Địa chỉ WebSocket Server:", initialvalue=self.server_url, parent=self.root)
        if url:
            self.server_url = url.strip()
            self.connect_host()

    def apply_personal_pw(self):
        pw = self.var_personal_pw.get().strip()
        if pw:
            self.my_pw = pw
            self.var_my_pw.set(pw)
            self.connect_host()

    def connect_host(self):
        if self.host_ws:
            try:
                self.host_ws.close()
            except Exception:
                pass
        threading.Thread(target=self._host_loop, daemon=True).start()

    def _host_loop(self):
        while True:
            try:
                self.set_status("Đang kết nối máy chủ...", "#E0A800")
                ws = websocket.WebSocketApp(
                    self.server_url,
                    on_open=lambda w: w.send(json.dumps({"type": "register", "id": self.my_id, "password": self.my_pw})),
                    on_message=self._on_host_message,
                    on_error=lambda w, e: self.set_status(f"Lỗi kết nối: {e}", "#D9534F"),
                    on_close=lambda w, c, m: self.set_status("Mất kết nối, đang thử lại...", "#D9534F"),
                )
                self.host_ws = ws
                ws.run_forever(ping_interval=20, ping_timeout=10)
            except Exception:
                pass
            time.sleep(3)

    def _on_host_message(self, ws, message):
        if isinstance(message, (bytes, bytearray)):
            return
        try:
            msg = json.loads(message)
        except Exception:
            return
        mtype = msg.get("type")
        if mtype == "registered":
            self.set_status("Sẵn sàng kết nối", "#5CB85C")
        elif mtype == "viewer-joined":
            self.set_status("Đang bị điều khiển", "#337AB7")
            if not self.streaming:
                self.streaming = True
                threading.Thread(target=self._stream_screen, daemon=True).start()
        else:
            self._handle_input_event(msg)

    def _stream_screen(self):
        with mss.mss() as sct:
            mon = sct.monitors[1]
            while self.streaming and self.host_ws and self.host_ws.sock and self.host_ws.sock.connected:
                t0 = time.time()
                try:
                    raw = sct.grab(mon)
                    img = Image.frombytes("RGB", raw.size, raw.bgra, "raw", "BGRX")
                    max_w = 1280
                    if img.width > max_w:
                        h = int(img.height * (max_w / img.width))
                        img = img.resize((max_w, h), Image.BILINEAR)
                    buf = io.BytesIO()
                    img.save(buf, format="JPEG", quality=65, optimize=False)
                    self.host_ws.send(buf.getvalue(), opcode=websocket.ABNF.OPCODE_BINARY)
                except Exception:
                    break
                dt = time.time() - t0
                if dt < 0.055:
                    time.sleep(0.055 - dt)
        self.streaming = False

    def _handle_input_event(self, msg: dict):
        sw, sh = pyautogui.size()
        t = msg.get("type")
        try:
            if t == "move":
                pyautogui.moveTo(int(msg["x"] * sw), int(msg["y"] * sh))
            elif t == "click":
                pyautogui.click(int(msg["x"] * sw), int(msg["y"] * sh), button="left")
            elif t == "dblclick":
                pyautogui.doubleClick(int(msg["x"] * sw), int(msg["y"] * sh))
            elif t == "rightclick":
                pyautogui.click(int(msg["x"] * sw), int(msg["y"] * sh), button="right")
            elif t == "drag":
                pyautogui.moveTo(int(msg["x1"] * sw), int(msg["y1"] * sh))
                pyautogui.dragTo(int(msg["x2"] * sw), int(msg["y2"] * sh), duration=0.12, button="left")
            elif t == "scroll":
                pyautogui.scroll(int(msg.get("dy", 0)))
            elif t == "key":
                key = str(msg.get("key", "")).lower()
                keymap = {"enter": "enter", "backspace": "backspace", "esc": "esc", "tab": "tab", "win": "win", "space": "space"}
                if key in keymap:
                    pyautogui.press(keymap[key])
                elif len(key) == 1:
                    pyautogui.press(key)
            elif t == "text":
                txt = str(msg.get("text", ""))
                if txt:
                    pyautogui.write(txt, interval=0.01)
        except Exception:
            pass

    def start_control(self):
        tid = self.ent_target_id.get().strip()
        tpw = self.ent_target_pw.get().strip()
        if not tid or not tpw:
            messagebox.showwarning("Thiếu thông tin", "Vui lòng nhập ID đối tác và Mật khẩu.")
            return
        threading.Thread(target=self._viewer_loop, args=(tid, tpw), daemon=True).start()

    def _viewer_loop(self, tid: str, tpw: str):
        ws = websocket.WebSocketApp(
            self.server_url,
            on_open=lambda w: w.send(json.dumps({"type": "connect", "targetId": tid, "password": tpw})),
            on_message=self._on_viewer_message,
            on_error=lambda w, e: self.root.after(0, lambda: messagebox.showerror("Lỗi", str(e))),
            on_close=lambda w, c, m: self.root.after(0, self._close_remote_window),
        )
        self.viewer_ws = ws
        ws.run_forever()

    def _on_viewer_message(self, ws, message):
        if isinstance(message, (bytes, bytearray)):
            try:
                img = Image.open(io.BytesIO(message))
                self.root.after(0, lambda im=img: self._render_remote_frame(im))
            except Exception:
                pass
            return
        try:
            msg = json.loads(message)
        except Exception:
            return
        t = msg.get("type")
        if t == "connected":
            self.root.after(0, lambda: self._open_remote_window(msg.get("targetId", "")))
        elif t == "error":
            err = msg.get("message", "Kết nối thất bại")
            self.root.after(0, lambda: messagebox.showerror("Không thể kết nối", err))
        elif t == "host-disconnected":
            self.root.after(0, lambda: (
                messagebox.showinfo("Thông báo", "Máy đối tác đã ngắt kết nối."),
                self._close_remote_window()
            ))

    def _open_remote_window(self, tid: str):
        if self.remote_win and self.remote_win.winfo_exists():
            return
        win = tk.Toplevel(self.root)
        win.title(f"Đang điều khiển PC: {tid}")
        win.geometry("1024x640")
        canvas = tk.Canvas(win, bg="black", cursor="cross")
        canvas.pack(fill="both", expand=True)

        drag_start = {"x": None, "y": None}

        def to_norm(ev):
            cw = max(canvas.winfo_width(), 1)
            ch = max(canvas.winfo_height(), 1)
            return max(0.0, min(1.0, ev.x / cw)), max(0.0, min(1.0, ev.y / ch))

        def on_press(ev):
            nx, ny = to_norm(ev)
            drag_start["x"], drag_start["y"] = nx, ny

        def on_release(ev):
            nx, ny = to_norm(ev)
            sx, sy = drag_start["x"], drag_start["y"]
            drag_start["x"], drag_start["y"] = None, None
            if sx is not None and (abs(nx - sx) > 0.015 or abs(ny - sy) > 0.015):
                self._send_viewer({"type": "drag", "x1": sx, "y1": sy, "x2": nx, "y2": ny})
            else:
                self._send_viewer({"type": "click", "x": nx, "y": ny})

        def on_right(ev):
            nx, ny = to_norm(ev)
            self._send_viewer({"type": "rightclick", "x": nx, "y": ny})

        def on_double(ev):
            nx, ny = to_norm(ev)
            self._send_viewer({"type": "dblclick", "x": nx, "y": ny})

        def on_wheel(ev):
            dy = 3 if ev.delta > 0 else -3
            self._send_viewer({"type": "scroll", "dy": dy})

        def on_key(ev):
            if ev.keysym in ("Return", "BackSpace", "Escape", "Tab", "space"):
                k = {"Return": "enter", "BackSpace": "backspace", "Escape": "esc", "Tab": "tab", "space": "space"}[ev.keysym]
                self._send_viewer({"type": "key", "key": k})
            elif ev.char and len(ev.char) == 1:
                self._send_viewer({"type": "text", "text": ev.char})

        canvas.bind("<ButtonPress-1>", on_press)
        canvas.bind("<ButtonRelease-1>", on_release)
        canvas.bind("<Button-3>", on_right)
        canvas.bind("<Double-Button-1>", on_double)
        canvas.bind("<MouseWheel>", on_wheel)
        win.bind("<Key>", on_key)
        win.protocol("WM_DELETE_WINDOW", self._close_remote_window)

        self.remote_win = win
        self.remote_canvas = canvas

    def _render_remote_frame(self, img: Image.Image):
        if not self.remote_canvas or not self.remote_canvas.winfo_exists():
            return
        cw = max(self.remote_canvas.winfo_width(), 2)
        ch = max(self.remote_canvas.winfo_height(), 2)
        resized = img.resize((cw, ch), Image.BILINEAR)
        self.remote_photo = ImageTk.PhotoImage(resized)
        self.remote_canvas.delete("all")
        self.remote_canvas.create_image(0, 0, anchor="nw", image=self.remote_photo)

    def _send_viewer(self, payload: dict):
        if self.viewer_ws and self.viewer_ws.sock and self.viewer_ws.sock.connected:
            try:
                self.viewer_ws.send(json.dumps(payload))
            except Exception:
                pass

    def _close_remote_window(self):
        if self.viewer_ws:
            try:
                self.viewer_ws.close()
            except Exception:
                pass
            self.viewer_ws = None
        if self.remote_win and self.remote_win.winfo_exists():
            self.remote_win.destroy()
        self.remote_win = None
        self.remote_canvas = None


if __name__ == "__main__":
    root = tk.Tk()
    app = UltraViewerPC(root)
    root.mainloop()
