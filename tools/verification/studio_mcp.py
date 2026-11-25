import json
import queue
import subprocess
import threading
import time
from pathlib import Path

STUDIO_MCP_EXE = r"C:\Users\tnguy\AppData\Local\Roblox\Versions\version-8d7a1009c17e4ff8\StudioMCP.exe"


class StudioMCP:
    def __init__(self, exe_path=STUDIO_MCP_EXE, verbose=False):
        args = [exe_path, "--stdio"]
        if verbose:
            args.append("--verbose")
        self.proc = subprocess.Popen(
            args,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self._messages = queue.Queue()
        self._stderr_parts = []
        self._next_id = 1
        self._closed = False
        threading.Thread(target=self._stdout_reader, daemon=True).start()
        threading.Thread(target=self._stderr_reader, daemon=True).start()
        self.initialize()

    def _stdout_reader(self):
        while True:
            line = self.proc.stdout.readline()
            if not line:
                return
            text = line.decode("utf-8", "replace").strip()
            if not text:
                continue
            try:
                self._messages.put(json.loads(text))
            except Exception:
                self._messages.put({"nonjson": text})

    def _stderr_reader(self):
        while True:
            chunk = self.proc.stderr.readline()
            if not chunk:
                return
            self._stderr_parts.append(chunk.decode("utf-8", "replace"))

    @property
    def stderr(self):
        return "".join(self._stderr_parts)

    def _send(self, obj):
        payload = (json.dumps(obj, separators=(",", ":")) + "\n").encode("utf-8")
        self.proc.stdin.write(payload)
        self.proc.stdin.flush()

    def _wait_response(self, request_id, timeout=30):
        deadline = time.time() + timeout
        miscellaneous = []
        while time.time() < deadline:
            remaining = max(0.1, deadline - time.time())
            try:
                msg = self._messages.get(timeout=min(1.0, remaining))
            except queue.Empty:
                continue
            if msg.get("id") == request_id:
                return msg
            miscellaneous.append(msg)
        raise TimeoutError(f"Timed out waiting for MCP response id {request_id}; misc={miscellaneous!r}; stderr_tail={self.stderr[-1000:]}")

    def request(self, method, params=None, timeout=30):
        request_id = self._next_id
        self._next_id += 1
        self._send({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params or {}})
        return self._wait_response(request_id, timeout)

    def notify(self, method, params=None):
        self._send({"jsonrpc": "2.0", "method": method, "params": params or {}})

    def initialize(self):
        response = self.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "devin-galactic-force-windows", "version": "0.1"},
            },
            timeout=15,
        )
        self.notify("notifications/initialized", {})
        return response

    def call(self, tool, arguments=None, timeout=30):
        return self.request("tools/call", {"name": tool, "arguments": arguments or {}}, timeout=timeout)

    @staticmethod
    def content_text(response):
        try:
            parts = response["result"]["content"]
            return "\n".join(part.get("text", "") for part in parts if part.get("type") == "text")
        except Exception:
            return ""

    @staticmethod
    def content_json(response):
        text = StudioMCP.content_text(response)
        try:
            return json.loads(text)
        except Exception:
            return None

    def list_studios(self):
        response = self.call("list_roblox_studios", {})
        data = self.content_json(response) or {}
        return data.get("studios", []), response

    def wait_for_studio(self, timeout=45, require_place_id=None):
        deadline = time.time() + timeout
        last_response = None
        while time.time() < deadline:
            studios, response = self.list_studios()
            last_response = response
            for studio in studios:
                if require_place_id is None or studio.get("placeId") == require_place_id:
                    return studio
            time.sleep(3)
        raise TimeoutError(f"No matching Roblox Studio connected; last={json.dumps(last_response)[:1000]}; stderr_tail={self.stderr[-1000:]}")

    def studio_state(self, studio_id):
        return self.call("get_studio_state", {"studio_id": studio_id})

    def execute(self, studio_id, datamodel, code, timeout=30):
        return self.call(
            "execute_luau",
            {"studio_id": studio_id, "datamodel_type": datamodel, "code": code},
            timeout=timeout,
        )

    def start_play(self, studio_id):
        return self.call("start_stop_play", {"studio_id": studio_id, "is_start": True}, timeout=30)

    def stop_play(self, studio_id):
        return self.call("start_stop_play", {"studio_id": studio_id, "is_start": False}, timeout=30)

    def console(self, studio_id):
        return self.call("get_console_output", {"studio_id": studio_id}, timeout=30)

    def capture(self, studio_id, capture_id, camera_position=None, look_at_position=None, timeout=45):
        args = {"studio_id": studio_id, "capture_id": capture_id}
        if camera_position is not None:
            args["camera_position"] = camera_position
        if look_at_position is not None:
            args["look_at_position"] = look_at_position
        return self.call("screen_capture", args, timeout=timeout)

    def close(self):
        if self._closed:
            return
        self._closed = True
        try:
            self.proc.terminate()
            self.proc.wait(timeout=3)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()


def write_capture_response(response, output_dir, stem):
    """Write any image/data payloads from an MCP capture response. Returns file paths."""
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    written = []
    try:
        parts = response["result"]["content"]
    except Exception:
        return written
    for index, part in enumerate(parts):
        if part.get("type") == "image" and part.get("data"):
            import base64
            mime = part.get("mimeType", "image/png")
            ext = "png" if "png" in mime else "jpg" if ("jpeg" in mime or "jpg" in mime) else "bin"
            path = out / f"{stem}_{index}.{ext}"
            path.write_bytes(base64.b64decode(part["data"]))
            written.append(str(path))
        elif part.get("type") == "resource" and part.get("resource", {}).get("blob"):
            import base64
            resource = part["resource"]
            uri = resource.get("uri", "capture")
            ext = ".png" if "png" in uri else ".jpg" if ("jpg" in uri or "jpeg" in uri) else ".bin"
            path = out / f"{stem}_{index}{ext}"
            path.write_bytes(base64.b64decode(resource["blob"]))
            written.append(str(path))
    return written
