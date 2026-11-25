import json
import shutil
import time
from pathlib import Path
import sys

sys.path.insert(0, r"C:\Users\tnguy\gf_tools")
from studio_mcp import StudioMCP, write_capture_response

STUDIO_ID = "0d5d4409-fdc9-49ad-ad7d-512c7af56ae2"
EVIDENCE_DIR = Path(r"C:\Users\tnguy\galactic-force\evidence\v684-ai-conformance-runtime-20261125")
RAW_DIR = EVIDENCE_DIR / "raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)


def connect():
    return StudioMCP()


def text(response):
    return StudioMCP.content_text(response)


def exec_server(mcp, code, timeout=20):
    return text(mcp.execute(STUDIO_ID, "Server", code, timeout=timeout))


def exec_client(mcp, code, timeout=20):
    return text(mcp.execute(STUDIO_ID, "Client", code, timeout=timeout))


def server_json(mcp, code, timeout=20):
    s = exec_server(mcp, code, timeout)
    try:
        return json.loads(s)
    except Exception:
        return {"_parse_error": s[:1000], "_raw": s}


SUMMARY_CODE = r'''
local Players=game:GetService('Players')
local HttpService=game:GetService('HttpService')
local p=Players:GetPlayers()[1]
local root=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local folder=workspace:FindFirstChild('ActiveActors')
local actors={}
if folder then
 for _,m in ipairs(folder:GetChildren()) do
  if m:IsA('Model') and m:GetAttribute('GFEnemy') then
   local pos=m.PrimaryPart and m.PrimaryPart.Position or Vector3.zero
   table.insert(actors,{
    name=m.Name,
    id=tostring(m:GetAttribute('EnemyId')),
    state=tostring(m:GetAttribute('GFState')),
    health=m:GetAttribute('Health'),
    shield=m:GetAttribute('Shield'),
    dead=m:GetAttribute('Dead'),
    perception=m:GetAttribute('PerceptionConfidence'),
    charging=m:GetAttribute('ChargingUntil'),
    transmission=m:GetAttribute('TransmissionUntil'),
    sweep=m:GetAttribute('SweepTelegraphUntil'),
    x=pos.x,y=pos.y,z=pos.z
   })
  end
 end
end
return HttpService:JSONEncode({
 clock=os.clock(),
 player=p and p.Name or nil,
 playerPos=root and {x=root.Position.x,y=root.Position.y,z=root.Position.z} or nil,
 playerHealth=(p and p.Character and p.Character:FindFirstChildOfClass('Humanoid') and p.Character:FindFirstChildOfClass('Humanoid').Health) or nil,
 inMission=workspace:GetAttribute('GF_InMission'),
 template=workspace:GetAttribute('GF_OperationTemplate'),
 difficulty=workspace:GetAttribute('GF_OperationDifficulty'),
 channels=workspace:GetAttribute('GF_BeaconChannels') or 0,
 completions=workspace:GetAttribute('GF_BeaconCompletions') or 0,
 cancels=workspace:GetAttribute('GF_BeaconCancels') or 0,
 sweeps=workspace:GetAttribute('GF_OfficerSweeps') or 0,
 sweepHits=workspace:GetAttribute('GF_SweepHits') or 0,
 fireSlots=workspace:GetAttribute('GF_FireSlotsHeld') or 0,
 enemyHits=workspace:GetAttribute('GF_EnemyHits') or 0,
 enemyMisses=workspace:GetAttribute('GF_EnemyMisses') or 0,
 lastCharge=tostring(workspace:GetAttribute('GF_LastCharge')),
 lastAttack=tostring(workspace:GetAttribute('GF_LastAttackAttempt')),
 actors=actors
})
'''


def summary(mcp):
    return server_json(mcp, SUMMARY_CODE)


def deploy_until_scout(mcp, attempts=8):
    fire = r'''
local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes')
remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'})
return 'deploy-requested'
'''
    rows = []
    for attempt in range(1, attempts + 1):
        exec_client(mcp, fire)
        time.sleep(2.0)
        data = summary(mcp)
        ids = [a.get('id') for a in data.get('actors', [])]
        rows.append({"attempt": attempt, "ids": ids, "accepted": data.get('inMission')})
        if 'Scout' in ids and 'Marksman' in ids and 'Officer' in ids:
            return True, rows, data
    return False, rows, summary(mcp)


def teleport_player(mcp, x, y, z, look_x=None, look_y=None, look_z=None):
    if look_x is None:
        code = f"""
local p=game:GetService('Players'):GetPlayers()[1]
local c=p and p.Character
if c then c:PivotTo(CFrame.new(Vector3.new({x},{y},{z}))) end
return 'teleported'
"""
    else:
        code = f"""
local p=game:GetService('Players'):GetPlayers()[1]
local c=p and p.Character
if c then c:PivotTo(CFrame.lookAt(Vector3.new({x},{y},{z}),Vector3.new({look_x},{look_y},{look_z}))) end
return 'teleported-facing'
"""
    return exec_server(mcp, code)


def force_no_spread(mcp):
    return exec_server(mcp, "workspace:SetAttribute('GF_ForceNoSpread',true) return 'spread-disabled-for-hit-repro'")


def fire_at(mcp, tx, ty, tz, weapon="AR01"):
    # Client remote fire using a server-valid origin beside the character root.
    code = f'''
local Players=game:GetService('Players')
local p=Players.LocalPlayer
local c=p and p.Character
local root=c and c:FindFirstChild('HumanoidRootPart')
if not root then return 'no-root' end
local origin=root.Position+Vector3.new(0,1.4,0)
local target=Vector3.new({tx},{ty},{tz})
local dir=(target-origin).Unit
local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes')
local shot=math.floor(os.clock()*1000000)
remotes.FireWeapon:FireServer({{weaponId='{weapon}',shotId=shot,origin=origin,direction=dir}})
return 'fired:'..tostring(shot)
'''
    return exec_client(mcp, code)


def camera_track_actor(mcp, enemy_name, seconds=8, distance=14, height=5, child_part=None):
    # Use the Controller's official GF_CamPos/GF_CamLook override. RenderStepped camera writes lose
    # against the custom controller; the attribute override is the supported harness/cinematic path.
    part_expr = "m.PrimaryPart"
    if child_part:
        part_expr = f"(m:FindFirstChild('{child_part}') or m.PrimaryPart)"
    code = f'''
local RunService=game:GetService('RunService')
local Players=game:GetService('Players')
local pname='{enemy_name}'
local seconds={seconds}
local started=os.clock()
local conn
conn=RunService.Heartbeat:Connect(function()
 local folder=workspace:FindFirstChild('ActiveActors')
 local m=folder and folder:FindFirstChild(pname)
 if not m then
  for _,x in ipairs(folder and folder:GetChildren() or {{}}) do if x:IsA('Model') and x:GetAttribute('EnemyId')==pname then m=x break end end
 end
 local player=Players.LocalPlayer
 local root=player and player.Character and player.Character:FindFirstChild('HumanoidRootPart')
 local part=m and {part_expr}
 if root and part then
  workspace:SetAttribute('GF_CamPos',root.Position+Vector3.new(0,2,6))
  workspace:SetAttribute('GF_CamLook',part.Position)
 end
 if os.clock()-started>seconds then
  conn:Disconnect()
  workspace:SetAttribute('GF_CamPos',nil)
  workspace:SetAttribute('GF_CamLook',nil)
 end
end)
return 'official-camera-track-started'
'''
    return exec_client(mcp, code)


def camera_at(mcp, pos, target, seconds=6):
    code = f'''
local RunService=game:GetService('RunService')
local cam=workspace.CurrentCamera
local started=os.clock()
local key='GF_EvidenceCamFixed_'..tostring(math.floor(os.clock()*1000))
RunService:BindToRenderStep(key,Enum.RenderPriority.Camera.Value+1,function()
 cam.CFrame=CFrame.lookAt(Vector3.new({pos[0]},{pos[1]},{pos[2]}),Vector3.new({target[0]},{target[1]},{target[2]}))
 if os.clock()-started>{seconds} then RunService:UnbindFromRenderStep(key) end
end)
return 'fixed-camera-started'
'''
    return exec_client(mcp, code)


def video_start(mcp):
    return text(mcp.call('video_capture', {'studio_id': STUDIO_ID, 'datamodel_type': 'Client', 'is_start': True}, timeout=20))


def video_stop(mcp, name):
    response = mcp.call('video_capture', {'studio_id': STUDIO_ID, 'datamodel_type': 'Client', 'is_start': False}, timeout=30)
    raw = text(response)
    try:
        data = json.loads(raw)
    except Exception:
        data = {"_raw": raw}
    copied = {}
    artifacts = data.get('artifacts') or {}
    for key, src in artifacts.items():
        srcp = Path(src)
        if srcp.exists():
            dest = RAW_DIR / f"{name}_{key}{srcp.suffix}"
            shutil.copy2(srcp, dest)
            copied[key] = str(dest)
    data['copied_artifacts'] = copied
    (RAW_DIR / f"{name}_video_result.json").write_text(json.dumps(data, indent=2), encoding='utf-8')
    return data


def write_json(name, data):
    path = RAW_DIR / name
    path.write_text(json.dumps(data, indent=2), encoding='utf-8')
    return str(path)



def client_visual_probe(mcp):
    code = r"""
local HttpService=game:GetService('HttpService')
local beams={}
local tracers={}
for _,x in ipairs(workspace:GetDescendants()) do
 if x.Name=='TelegraphBeam' then table.insert(beams,{transparency=x.Transparency,size=tostring(x.Size),pos=tostring(x.Position)}) end
 if x.Name=='EnemyTracer' then table.insert(tracers,{transparency=x.Transparency,pos=tostring(x.Position)}) end
end
return HttpService:JSONEncode({beamCount=#beams,tracerCount=#tracers,beams=beams,tracers=tracers})
"""
    s = exec_client(mcp, code, timeout=8)
    try:
        return json.loads(s)
    except Exception:
        return {"_parse_error": s[:500]}


def sample_series(mcp, seconds, interval=0.2, include_client=False):
    samples=[]
    start=time.time()
    while time.time()-start < seconds:
        row={'t':round(time.time()-start,3),'server':summary(mcp)}
        if include_client:
            row['client']=client_visual_probe(mcp)
        samples.append(row)
        time.sleep(interval)
    return samples
