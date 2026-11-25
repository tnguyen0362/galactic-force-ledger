import json,time,re
from pathlib import Path
import sys
sys.path.insert(0,r'C:\Users\tnguy\gf_tools')
import ai_evidence_runtime as h
from studio_mcp import write_capture_response
sys.path.insert(0,r'C:\Users\tnguy\galactic-force\tools\verification')
import run_ticket_deathflow_verify as base
OUT=Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw'); OUT.mkdir(parents=True,exist_ok=True)
LOG={}
with h.connect() as m:
    try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.5)
    except Exception: pass
    print(h.text(m.start_play(h.STUDIO_ID))[:80],flush=True); time.sleep(7)
    fire="""local r=game:GetService('ReplicatedStorage').GF.Remotes r.RequestDeploy:FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'fire'"""
    LOG['deploy']=h.exec_client(m,fire); time.sleep(5)
    LOG['fall']=base.induce_lethal_fall(m)
    deadline=time.time()+30; final=None; saw_down=False
    while time.time()<deadline:
        ss=base.server_sample(m)
        if 'downedAttr=true' in ss and not saw_down:
            saw_down=True
            h.exec_server(m,"local p=game:GetService('Players'):GetPlayers()[1] game:GetService('ReplicatedStorage').GF.Remotes.SprintChanged:Fire(p,true) game:GetService('ReplicatedStorage').GF.Remotes.AimChanged:Fire(p,true) return 'stance-forced'")
            time.sleep(.3)
            LOG['downed_stance']=h.exec_server(m,"local p=game:GetService('Players'):GetPlayers()[1] local c=p and p.Character local h=c and c:FindFirstChildOfClass('Humanoid') return {walk=h and h.WalkSpeed,jump=h and h.JumpPower,sprint=c and c:GetAttribute('Sprinting'),aim=c and c:GetAttribute('Aiming')}")
        if saw_down and 'pending=nil' in ss and 'downedAttr=nil' in ss and 'health=100' in ss:
            final=ss; break
        time.sleep(.5)
    q=h.exec_server(m,"local pods=0 local ff=false for _,x in ipairs(workspace:GetChildren()) do if x.Name=='GF_ReinforcementPod' then pods+=1 end end local p=game:GetService('Players'):GetPlayers()[1] ff=p and p.Character and p.Character:FindFirstChild('GF_RedeployProtection') ~= nil return {pods=pods,forcefield=ff,inMission=workspace:GetAttribute('GF_InMission'),tickets=workspace:GetAttribute('GF_ReinforcementTickets')}")
    LOG['redeploy_state']=final; LOG['pod_query']=q
    try:
        paths=write_capture_response(m.capture(h.STUDIO_ID,'redeploy_pod_visible'),OUT,'redeploy_pod_visible'); LOG['capture']=paths
    except Exception as e: LOG['capture_error']=str(e)
    try:
        qq=json.loads(q); stance=json.loads(LOG.get('downed_stance') or '{}')
        ok=bool(final and qq.get('pods',0)>=1 and qq.get('forcefield')==True and qq.get('tickets')==4 and stance.get('walk')==5 and stance.get('jump')==0 and stance.get('sprint') in (False,None) and stance.get('aim') in (False,None))
    except Exception: ok=False
    LOG['passed']=ok
    print(json.dumps(LOG),flush=True)
(OUT/'redeploy_pod_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
