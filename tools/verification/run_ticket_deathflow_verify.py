import json
import re
import time
from pathlib import Path
import sys

sys.path.insert(0, r"C:\Users\tnguy\gf_tools")
from studio_mcp import write_capture_response
import ai_evidence_runtime as h

OUT = Path(r"C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw")
OUT.mkdir(parents=True, exist_ok=True)
LOG = {"checks": [], "captures": {}, "errors": []}


def record(name, value):
    LOG[name] = value
    print(name, value, flush=True)


def check(name, value):
    LOG["checks"].append({"t": round(time.time(), 3), "name": name, "value": value})
    print(f"{name}: {value}", flush=True)


def server_sample(mcp):
    code = r'''
local p=game:GetService('Players'):GetPlayers()[1]
local c=p and p.Character
local root=c and c:FindFirstChild('HumanoidRootPart')
local hum=c and c:FindFirstChildOfClass('Humanoid')
local pos=root and root.Position or Vector3.zero
return 'inMission='..tostring(workspace:GetAttribute('GF_InMission'))
..' endReason='..tostring(workspace:GetAttribute('GF_MissionEndReason'))
..' pending='..tostring(workspace:GetAttribute('GF_RedeployPendingFor'))
..' countdown='..tostring(workspace:GetAttribute('GF_RedeployCountdown'))
..' fall='..tostring(workspace:GetAttribute('GF_LastFallDamage'))
..' downedAttr='..tostring(c and c:GetAttribute('GFDowned'))
..' health='..tostring(hum and hum.Health)
..' pos='..string.format('%.1f,%.1f,%.1f',pos.X,pos.Y,pos.Z)
..' tickets='..tostring(workspace:GetAttribute('GF_ReinforcementTickets'))
..' lz='..tostring(workspace:GetAttribute('GF_LZ'))
..' trace='..tostring(workspace:GetAttribute('GF_LastDeathTrace'))
..' ddebug='..tostring(workspace:GetAttribute('GF_DownedDebug'))
'''
    return h.exec_server(mcp, code)


def client_sample(mcp):
    code = r'''
local Players=game:GetService('Players')
local p=Players.LocalPlayer
local gui=p.PlayerGui:FindFirstChild('GF_HUD')
local downed=gui and gui:FindFirstChild('Downed',true)
local loadingGui=p.PlayerGui:FindFirstChild('GFLoadingScreen')
local loading=loadingGui and loadingGui:FindFirstChildOfClass('Frame')
local squad=false
local downedText=''
local debriefBody=''
for _,x in ipairs(p.PlayerGui:GetDescendants()) do
 if x:IsA('TextLabel') then
  if string.find(x.Text,'SQUAD ELIMINATED') then squad=true end
  if x.Text=='DOWNED' or x.Text=='K.I.A.' then downedText=x.Text end
  if string.find(x.Text,'Automatic redeploys exhausted') then debriefBody=x.Text end
 end
end
return 'downedVisible='..tostring(downed and downed.Visible)
..' downedText='..tostring(downedText)
..' loading='..tostring(loading and loading.Visible)
..' squadText='..tostring(squad)
..' debriefBody='..tostring(debriefBody ~= '')
..' mouse='..tostring(game:GetService('UserInputService').MouseBehavior)
'''
    return h.exec_client(mcp, code)


def cap(mcp, stem):
    try:
        paths = write_capture_response(mcp.capture(h.STUDIO_ID, stem), OUT, stem)
        LOG["captures"][stem] = paths
        print("capture", stem, paths, flush=True)
    except Exception as e:
        LOG["errors"].append(f"capture {stem}: {type(e).__name__}: {e}")
        print("capture-error", stem, type(e).__name__, e, flush=True)


def wait_for(mcp, predicate, timeout, interval=0.5, label="condition"):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = predicate()
        if last and last.get("ok"):
            return last
        time.sleep(interval)
    return {"ok": False, "timeout": label, "last": last}


def sample_pair_ok(mcp, server_pred=None, client_pred=None):
    ss = server_sample(mcp)
    cs = client_sample(mcp)
    ok = True
    if server_pred:
        ok = ok and server_pred(ss)
    if client_pred:
        ok = ok and client_pred(cs)
    return {"ok": ok, "server": ss, "client": cs}


def induce_lethal_fall(mcp):
    code = r'''
local p=game:GetService('Players'):GetPlayers()[1]
local c=p and p.Character
local root=c and c:FindFirstChild('HumanoidRootPart')
if not root then return 'no-root' end
local pos=root.Position
c:PivotTo(CFrame.new(pos + Vector3.new(14,210,0)))
root.AssemblyLinearVelocity=Vector3.new(0,-175,0)
return 'fall-induced:'..tostring(root.Position)
'''
    return h.exec_server(mcp, code)


def main():
    with h.connect() as mcp:
        try:
            h.text(mcp.stop_play(h.STUDIO_ID))
            time.sleep(2)
        except Exception:
            pass
        print(h.text(mcp.start_play(h.STUDIO_ID))[:120], flush=True)
        time.sleep(8)

        fire = r'''
local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes')
remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'})
return 'deploy-requested'
'''
        check('deploy_fire', h.exec_client(mcp, fire))
        time.sleep(0.25)
        check('deploy_loading_immediate', client_sample(mcp))
        cap(mcp, 'ticketflow_deploy_loading')

        r = wait_for(mcp, lambda: sample_pair_ok(mcp, lambda s: 'inMission=true' in s), timeout=10, label='deploy-mission-active')
        check('mission_active', r)
        time.sleep(4.5)  # deploy grace expires; enemy/fall damage is then meaningful
        check('baseline_before_first_fall', sample_pair_ok(mcp))

        check('first_fall_induce', induce_lethal_fall(mcp))
        r = wait_for(mcp, lambda: sample_pair_ok(mcp, lambda s: 'downedAttr=true' in s), timeout=7, interval=0.35, label='first-down')
        check('first_down_detected', r)
        cap(mcp, 'ticketflow_first_downed')

        r = wait_for(mcp, lambda: sample_pair_ok(mcp, lambda s: 'pending=' in s and 'pending=nil' not in s), timeout=13, interval=0.5, label='first-redeploy-pending')
        check('first_redeploy_pending', r)
        cap(mcp, 'ticketflow_kia_countdown')

        def redeployed(s):
            m = re.search(r'health=([0-9.]+)', s)
            health = float(m.group(1)) if m else 0
            return 'pending=nil' in s and 'downedAttr=nil' in s and health > 50
        r = wait_for(mcp, lambda: sample_pair_ok(mcp, redeployed), timeout=14, interval=0.5, label='automatic-redeploy')
        check('automatic_redeploy_detected', r)
        check('ticket_count_after_first_redeploy', server_sample(mcp))
        cap(mcp, 'ticketflow_after_redeploy')
        time.sleep(1.5)

        # Exhaust the shared budget before the second death: the first death already proved ticket spend;
        # this makes the second permanent death exercise the no-ticket squad-failure branch in one test run.
        check('force_tickets_zero', h.exec_server(mcp, "local m=require(game.ServerScriptService.GF.Services.State).getMission() if m then m.tickets=0 end workspace:SetAttribute('GF_ReinforcementTickets',0) return 'tickets-zero'"))
        check('second_fall_induce', induce_lethal_fall(mcp))
        r = wait_for(mcp, lambda: sample_pair_ok(mcp, lambda s: 'downedAttr=true' in s), timeout=7, interval=0.35, label='second-down')
        check('second_down_detected', r)

        def eliminated_server(s):
            return 'endReason=squad_eliminated' in s
        def eliminated_client(c):
            return 'squadText=true' in c
        r = wait_for(mcp, lambda: sample_pair_ok(mcp, eliminated_server, eliminated_client), timeout=18, interval=0.5, label='squad-eliminated-debrief')
        check('squad_eliminated_debrief', r)
        cap(mcp, 'ticketflow_squad_eliminated_debrief')
        check('final_state', sample_pair_ok(mcp))

    outfile = OUT / 'ticketflow_ticket_verification.json'
    outfile.write_text(json.dumps(LOG, indent=2), encoding='utf-8')
    print('wrote', outfile, flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        LOG['errors'].append(f'fatal: {type(e).__name__}: {e}')
        (OUT / 'ticketflow_ticket_verification.json').write_text(json.dumps(LOG, indent=2), encoding='utf-8')
        raise
