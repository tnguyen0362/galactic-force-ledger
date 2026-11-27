# Targeted client startup race/class-parity deploy for the mission place.
# Deploys only the client scripts involved in sibling-require startup failures,
# and recreates them when their Studio class drifted from the intended class.
# NEVER saves the place.
import subprocess, json, os, time, io
import threading

ROOT = r"C:\Users\tnguy\galactic-force\game-mirror\playtest1_current"
TARGET_PLACE_ID = 13785118418  # Missions: mission gameplay place

FILES = {
    "StarterPlayer/StarterPlayerScripts/CameraController.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/CameraCtl.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/Controller.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/GFAudio.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/GFAudioRuntime.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/GFClient.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/GrenadeClient.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/HUD.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/LootFeed.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/Minimap.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/MovementDiagnostics.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/PlayerController.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/SquadBrowser.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/StationArmoryUI.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/StationUI.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/StatusStrip.luau": "LocalScript",
    "StarterPlayer/StarterPlayerScripts/VFX.luau": "ModuleScript",
    "StarterPlayer/StarterPlayerScripts/Weapon.luau": "ModuleScript",
}

la = os.environ.get("LOCALAPPDATA", "")
bat = os.path.join(la, "Roblox", "mcp.bat")
print("bridge:", bat, "exists:", os.path.exists(bat))

p = subprocess.Popen(["cmd.exe", "/c", "cd /d %s\\Roblox && .\\mcp.bat" % la],
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                     cwd=os.path.join(la, "Roblox"))

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
          "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "gf-client-racefix", "version": "1"}}})
    waitid(1)
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    studios = json.loads(text(call("list_roblox_studios", {})))["studios"]
    print("studios:", [(s["name"], s.get("placeId")) for s in studios])
    studio = next((s for s in studios if s.get("placeId") == TARGET_PLACE_ID), None)
    if not studio:
        raise RuntimeError("Missions studio placeId %s not connected" % TARGET_PLACE_ID)
    sid = studio["id"]
    print("target studio:", studio["name"], sid)

    okcount = 0
    fails = []
    for rel, desired_class in FILES.items():
        src = io.open(os.path.join(ROOT, rel.replace("/", os.sep)), encoding="utf-8").read()
        mod = rel[:-5]
        if "]==]" in src:
            print(" FAIL", rel, "delimiter collision")
            fails.append(rel)
            continue
        code = (
            "local segs = string.split('" + mod + "', '/') "
            "local node = game "
            "for i = 1, #segs - 1 do "
            "  local nxt = node:FindFirstChild(segs[i]) "
            "  if not nxt then nxt = Instance.new('Folder') nxt.Name = segs[i] nxt.Parent = node end "
            "  node = nxt "
            "end "
            "local leaf = segs[#segs] "
            "local desiredClass = '" + desired_class + "' "
            "local source = [==[" + src + "]==] "
            "local cf, ce = loadstring(source, leaf) "
            "if ce then return 'ERR:' .. tostring(ce) end "
            "local target = node:FindFirstChild(leaf) "
            "local converted = false "
            "if target and target.ClassName ~= desiredClass then "
            "  local old = target "
            "  target = Instance.new(desiredClass) "
            "  target.Name = leaf "
            "  for key, value in pairs(old:GetAttributes()) do target:SetAttribute(key, value) end "
            "  target.Source = source "
            "  target.Parent = node "
            "  old:Destroy() "
            "  converted = true "
            "elseif not target then "
            "  target = Instance.new(desiredClass) "
            "  target.Name = leaf "
            "  target.Source = source "
            "  target.Parent = node "
            "else "
            "  target.Source = source "
            "end "
            "return converted and 'ok-converted' or 'ok'"
        )
        r = text(call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
        status = r.strip()
        if status in ("ok", "ok-converted"):
            okcount += 1
            print(" ok ", rel.split("/")[-1], status)
        else:
            fails.append(rel)
            print(" FAIL", rel.split("/")[-1], status[:180])
    print("deployed ok:", okcount, "/", len(FILES), "fails:", len(fails))
    for f in fails:
        print("  FAILED:", f)
finally:
    p.kill()
