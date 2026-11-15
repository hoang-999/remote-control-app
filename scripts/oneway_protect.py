import argparse
import ast
import base64
import hashlib
import lzma
import marshal
import os
import secrets
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _keystream(seed: bytes, length: int) -> bytes:
    out = bytearray()
    ctr = 0
    while len(out) < length:
        out.extend(hashlib.sha256(seed + ctr.to_bytes(4, "big")).digest())
        ctr += 1
    return bytes(out[:length])


def protect_pc():
    src_path = ROOT / "pc" / "ultraviewer_pc.py"
    out_path = ROOT / "pc" / "ultraviewer_protected.py"
    src = src_path.read_text(encoding="utf-8")

    # Strip comments & AST-normalize before compiling with optimize=2
    tree = ast.parse(src)
    clean_src = ast.unparse(tree)
    code_obj = compile(clean_src, "<protected>", "exec", optimize=2)
    marshaled = marshal.dumps(code_obj)
    compressed = lzma.compress(marshaled, preset=9)

    salt = secrets.token_bytes(32)
    digest = hashlib.sha256(compressed).digest()
    ks = _keystream(salt, len(compressed))
    cipher = bytes(a ^ b for a, b in zip(compressed, ks))

    b64_cipher = base64.b85encode(cipher).decode("ascii")
    b64_salt = base64.b85encode(salt).decode("ascii")
    hex_digest = digest.hex()

    # Keep explicit imports visible to PyInstaller static analyzer
    stub = f'''import base64, ctypes, hashlib, io, json, lzma, marshal, os, random, threading, time, tkinter
from tkinter import messagebox, simpledialog
import mss, pyautogui, websocket
from PIL import Image, ImageTk

_S = base64.b85decode({b64_salt!r})
_C = base64.b85decode({b64_cipher!r})
_D = {hex_digest!r}

def _run():
    out = bytearray()
    ctr = 0
    while len(out) < len(_C):
        out.extend(hashlib.sha256(_S + ctr.to_bytes(4, "big")).digest())
        ctr += 1
    raw = bytes(a ^ b for a, b in zip(_C, out[:len(_C)]))
    if hashlib.sha256(raw).hexdigest() != _D:
        raise SystemExit(1)
    exec(marshal.loads(lzma.decompress(raw)), {{"__name__": "__main__"}})

if __name__ == "__main__":
    _run()
'''
    out_path.write_text(stub, encoding="utf-8")
    print(f"Protected PC stub written to {out_path} ({len(stub)} bytes)")


def _swift_xor_expr(s: str, key: int) -> str:
    arr = ", ".join(str(b ^ key) for b in s.encode("utf-8"))
    return f'_d([{arr}], {key})'


def protect_ios():
    helper = (
        "\n@inline(__always) private func _d(_ b: [UInt8], _ k: UInt8) -> String {\n"
        "    String(bytes: b.map { $0 ^ k }, encoding: .utf8) ?? \"\"\n"
        "}\n"
    )
    targets = [
        (ROOT / "ios" / "Sources" / "App.swift", [
            '"ws://168.144.36.51:8081"',
            '"Copyright DucFabulous Co,ltd"',
        ]),
        (ROOT / "ios" / "Sources" / "RemoteClient.swift", [
            '"Sẵn sàng kết nối"',
            '"Đang kết nối tới \\(tid)..."',
        ]),
    ]
    for path, literals in targets:
        text = path.read_text(encoding="utf-8")
        if "private func _d(" not in text:
            text += helper
        for lit in literals:
            raw = lit[1:-1]
            if "\\" in raw:
                continue
            key = secrets.randbelow(200) + 23
            if lit in text:
                text = text.replace(lit, _swift_xor_expr(raw, key))
        path.write_text(text, encoding="utf-8")
        print(f"Protected iOS Swift strings in {path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--pc", action="store_true")
    p.add_argument("--ios", action="store_true")
    args = p.parse_args()
    if args.pc:
        protect_pc()
    if args.ios:
        protect_ios()
