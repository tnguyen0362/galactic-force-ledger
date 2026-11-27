# Windows Studio MCP deploy: streams mirror files into Edit DM with per-file compile validation.
# usage: python gf-deploy-win.py
import subprocess, json, os, select, time, sys, io

ROOT = r"C:\Users\tnguy\galactic-force\game-mirror\playtest1_current"
FILES = [
    "ServerScriptService/GF/Services/ArtService.luau",
    "ServerScriptService/GF/Services/OutpostService.luau",
    "ServerScriptService/GF/Services/ObjectiveService.luau",
    "ServerScriptService/GF/Services/ZoneControlService.luau",
    "ServerScriptService/GF/Services/HackingService.luau",
    "ServerScriptService/GF/Services/MissionSites.luau",
    "ServerScriptService/GF/Services/EnvironmentDressing.luau",
    "ServerScriptService/GF/Services/Battlefield/CoverBuilder.luau",
    "ServerScriptService/GF/Services/Battlefield/ScatterBuilder.luau",
    "ServerScriptService/GF/Test/CheckRunner.luau",
    "ServerScriptService/GF/Services/EnemyService.luau",
    "StarterPlayer/StarterPlayerScripts/MissionHUD.luau",
    "StarterPlayer/StarterPlayerScripts/EnemyAnimClient.luau",
    "ReplicatedStorage/GF/Shared/Remotes.luau",
]

la = os.environ.get("LOCALAPPDATA", "")
bat = os.path.join(la, "Roblox", "mcp.bat")
print("bridge:", bat, "exists:", os.path.exists(bat))

p = subprocess.Popen(["cmd.exe", "/c", "cd /d %s\\Roblox && .\\mcp.bat" % la],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                     cwd=os.path.join(la, "Roblox"))

# windows: no select on pipes — use a reader thread
import threading
lines = []
lock = threading.Lock()
def reader():
    while True:
        line = p.stdout.readline()
        if not line:
            break
        with lock:
            lines.append(line)
t = threading.Thread(target=reader, daemon=True)
t.start()

def send(o):
    p.stdin.write((json.dumps(o) + "\n").encode())
    p.stdin.flush()

def waitid(i, timeout=50):
    end = time.time() + timeout
    while time.time() < end:
        with lock:
            for idx, raw in enumerate(lines):
                try:
                    m = json.loads(raw)
                except Exception:
                    continue
                if m.get("id") == i:
                    lines.pop(idx)
                    return m
        time.sleep(0.15)
    raise TimeoutError("waitid %s" % i)

N = [10]
def call(name, args, timeout=50):
    N[0] += 1
    send({"jsonrpc": "2.0", "id": N[0], "method": "tools/call", "params": {"name": name, "arguments": args}})
    return waitid(N[0], timeout)

def text(m):
    return "".join(c.get("text", "") for c in m.get("result", {}).get("content", []))

try:
    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "gfdeploy", "version": "1"}}})
    waitid(1)
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    sid = json.loads(text(call("list_roblox_studios", {})))["studios"][0]["id"]
    print("studio:", sid)
    okcount = 0
    for rel in FILES:
        src = io.open(os.path.join(ROOT, rel.replace("/", os.sep)), encoding="utf-8").read()
        mod = rel[:-5]
        assert "]==]" not in src, rel
        code = (
            "local segs = string.split('" + mod + "', '/') "
            "local node = game "
            "for i = 1, #segs - 1 do node = node:FindFirstChild(segs[i]) if not node then return 'NAVFAIL' end end "
            "local leaf = segs[#segs] "
            "local target = node:FindFirstChild(leaf) "
            "if not target then target = Instance.new('ModuleScript') target.Name = leaf target.Parent = node end "
            "target.Source = [==[" + src + "]==] "
            "local f, e = loadstring(target.Source, leaf) "
            "return e and ('ERR:' .. tostring(e)) or 'ok'"
        )
        r = text(call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
        status = "ok" if r.strip() == "ok" else r[:160]
        if r.strip() == "ok":
            okcount += 1
        print(rel.split("/")[-1], status)
    print("deployed ok:", okcount, "/", len(FILES))
finally:
    p.kill()
