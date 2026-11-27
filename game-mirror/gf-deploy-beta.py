# beta deploy: visible UI overhaul + war/matchmaking vertical slice, both places.
# derived from gf-deploy-win.py — same bridge mechanics, per-file Studio loadstring validation.
# usage: python gf-deploy-beta.py
# NEVER saves the place — owner/claude publish; we only stream sources into Edit DM.
import subprocess, json, os, time, sys, io
import threading

ROOT = r"C:\Users\tnguy\galactic-force\game-mirror\playtest1_current"

# surgical set: beta-owned session changes. alpha/claude files (EnemyService, TroopVisuals,
# VegetationService, EncounterDirector) are deliberately NOT in this list — their lanes,
# their deploy timing. DeployContract is alpha's but idempotent and required by my chain.
FILES = [
    # shared: design system + war model + contracts
    "ReplicatedStorage/GF/Shared/UI/Tokens.luau",
    "ReplicatedStorage/GF/Shared/UI/Components.luau",
    "ReplicatedStorage/GF/Shared/UI/MenuShell.luau",
    "ReplicatedStorage/GF/Shared/UI/MenuController.luau",
    "ReplicatedStorage/GF/Shared/WarModel.luau",
    "ReplicatedStorage/GF/Shared/Configs/WarOperations.luau",
    "ReplicatedStorage/GF/Shared/Configs/Missions.luau",
    "ReplicatedStorage/GF/Shared/Types.luau",
    "ReplicatedStorage/GF/Shared/DeployContract.luau",
    # client: the visible overhaul
    "StarterPlayer/StarterPlayerScripts/HUD.luau",
    "StarterPlayer/StarterPlayerScripts/StatusStrip.luau",
    "StarterPlayer/StarterPlayerScripts/Minimap.luau",
    "StarterPlayer/StarterPlayerScripts/Input.luau",
    "StarterPlayer/StarterPlayerScripts/Controller.luau",
    "StarterPlayer/StarterPlayerScripts/StationUI.luau",
    "StarterPlayer/StarterPlayerScripts/StationArmoryUI.luau",
    "StarterPlayer/StarterPlayerScripts/SquadBrowser.luau",
    # server: the systems the client surfaces depend on
    "ServerScriptService/GF/Main.luau",
    "ServerScriptService/GF/Mission.luau",
    "ServerScriptService/GF/Services/WarStateService.luau",
    "ServerScriptService/GF/Services/MatchmakingService.luau",
    "ServerScriptService/GF/Services/DispatchService.luau",
    "ServerScriptService/GF/Services/SquadService.luau",
    "ServerScriptService/GF/Services/StationService.luau",
    "ServerScriptService/GF/Services/GalacticWarService.luau",
    "ServerScriptService/GF/Services/ProfileService.luau",
    "ServerScriptService/GF/Services/ArmoryService.luau",
    "ServerScriptService/GF/Services/AbilityService.luau",
    "ServerScriptService/GF/Services/OptionalService.luau",
    "ServerScriptService/GF/Services/ObjectiveService.luau",
]

# TouchControls was deleted in the mirror — must die in both places or the duplicate layer returns
DELETES = ["StarterPlayer/StarterPlayerScripts/TouchControls.luau"]

la = os.environ.get("LOCALAPPDATA", "")
print("bridge exists:", os.path.exists(os.path.join(la, "Roblox", "mcp.bat")))

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
          "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "betadeploy", "version": "1"}}})
    waitid(1)
    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})
    studios = json.loads(text(call("list_roblox_studios", {})))["studios"]
    print("studios:", [(s["name"], s["placeId"]) for s in studios])

    for studio in studios:
        sid = studio["id"]
        print("\n=== deploying to", studio["name"], "===")
        okcount = 0
        fails = []
        for rel in FILES:
            src = io.open(os.path.join(ROOT, rel.replace("/", os.sep)), encoding="utf-8").read()
            mod = rel[:-5]
            if "]==]" in src:
                print("SKIP (delimiter collision):", rel)
                fails.append(rel)
                continue
            # find-or-create intermediate folders AND the leaf — UI folder doesn't exist yet live
            code = (
                "local segs = string.split('" + mod + "', '/') "
                "local node = game "
                "for i = 1, #segs - 1 do "
                "  local nxt = node:FindFirstChild(segs[i]) "
                "  if not nxt then nxt = Instance.new('Folder') nxt.Name = segs[i] nxt.Parent = node end "
                "  node = nxt "
                "end "
                "local leaf = segs[#segs] "
                "local target = node:FindFirstChild(leaf) "
                "if not target then target = Instance.new('ModuleScript') target.Name = leaf target.Parent = node end "
                "target.Source = [==[" + src + "]==] "
                "local f, e = loadstring(target.Source, leaf) "
                "return e and ('ERR:' .. tostring(e)) or 'ok'"
            )
            r = text(call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
            if r.strip() == "ok":
                okcount += 1
                print(" ok ", rel.split("/")[-1])
            else:
                fails.append(rel)
                print(" FAIL", rel.split("/")[-1], r[:160])
        for rel in DELETES:
            mod = rel[:-5]
            code = (
                "local segs = string.split('" + mod + "', '/') "
                "local node = game "
                "for i = 1, #segs - 1 do node = node:FindFirstChild(segs[i]) if not node then return 'NAVFAIL' end end "
                "local target = node:FindFirstChild(segs[#segs]) "
                "if target then target:Destroy() return 'deleted' else return 'absent' end"
            )
            r = text(call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
            print(" delete TouchControls:", r.strip())
        print("deployed ok:", okcount, "/", len(FILES), "fails:", len(fails))
        for f in fails:
            print("  FAILED:", f)
finally:
    p.kill()
