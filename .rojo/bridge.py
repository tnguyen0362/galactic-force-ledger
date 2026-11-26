#!/usr/bin/env python3
"""Receive Roblox Studio script sources and write them into src/ as Rojo-compatible files.

Studio cannot write to disk, and pulling 866 KB of Luau through an agent's context is wasteful, so
Studio POSTs each script here instead. Binds localhost only and requires the shared token.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN = os.environ.get("GF_BRIDGE_TOKEN", "")
OUT = Path(__file__).resolve().parent.parent / "src"
SERVICE_DIRS = {
    "ServerScriptService": "src/server",
    "ReplicatedStorage": "src/shared",
    "StarterPlayer": "src/client",
    "ServerStorage": "src/server_storage",
    "StarterGui": "src/startergui",
}
SUFFIX = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}
written = 0


def safe_parts(parts):
    for p in parts:
        if p in (".", "..") or "/" in p or "\\" in p:
            raise ValueError(f"unsafe path segment: {p!r}")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _deny(self, code, msg):
        self.send_response(code)
        self.end_headers()
        self.wfile.write(msg.encode())

    def do_POST(self):
        global written
        if os.environ.get("GF_BRIDGE_TOKEN") and self.headers.get("X-GF-Token") != TOKEN:
            return self._deny(403, "bad token")
        length = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception as exc:  # noqa: BLE001
            return self._deny(400, f"bad json: {exc}")
        if self.path == "/script":
            try:
                service = body["service"]
                parts = list(body.get("path") or [])
                name = body["name"]
                klass = body["class"]
                source = body["source"]
                safe_parts(parts + [name])
                if service not in SERVICE_DIRS:
                    return self._deny(400, f"unknown service {service}")
                target = OUT / SERVICE_DIRS[service].split("/", 1)[1] / Path(*parts) / (name + SUFFIX.get(klass, ".luau"))
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(source, encoding="utf-8")
                written += 1
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
            except Exception as exc:  # noqa: BLE001
                return self._deny(500, str(exc))
        elif self.path == "/done":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(f"written={written}".encode())
            print(f"transfer complete: {written} files", flush=True)
        else:
            self._deny(404, "no such endpoint")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8745
    OUT.mkdir(parents=True, exist_ok=True)
    print(f"bridge listening on 127.0.0.1:{port} -> {OUT}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
