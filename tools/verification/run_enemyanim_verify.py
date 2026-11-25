import json,time,sys
from pathlib import Path
sys.path.insert(0,r'C:\Users\tnguy\gf_tools')
import ai_evidence_runtime as h
OUT=Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw'); OUT.mkdir(parents=True,exist_ok=True)
def rows(v):
    if isinstance(v,list): return v
    if isinstance(v,dict):
        try: return [v[k] for k in sorted(v.keys(),key=lambda x:int(x))]
        except Exception: return []
    return []
def pj(s):
    try:return json.loads(s)
    except Exception:return {'raw':s}
SAMPLE=r'''
local folder=workspace:FindFirstChild('ActiveActors')
local out={}
if folder then
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA('Model') and model:GetAttribute('HasRig') then
   local rig=nil
   for _,c in ipairs(model:GetChildren()) do
    if c:IsA('Model') and c:GetAttribute('GFEnemyRig') then rig=c break end
   end
   if rig then
    local rec={id=model.Name,state=tostring(model:GetAttribute('GFState')),hips={}}
    for _,d in ipairs(rig:GetDescendants()) do
     if d:IsA('Motor6D') then
      local x,y,z=d.C0:ToEulerAnglesXYZ()
      rec.hips[d.Name]=string.format('%.3f',x)
     end
    end
    table.insert(out,rec)
   end
  end
 end
end
return out
'''
PIVOT=r'''
local p=game:GetService('Players'):FindFirstChildOfClass('Player')
if not (p and p.Character) then return 'no-char' end
local hrp=p.Character:FindFirstChild('HumanoidRootPart')
if not hrp then return 'no-hrp' end
local hum=p.Character:FindFirstChildOfClass('Humanoid')
if not hum or hum.Health<=0 then return 'player-dead' end
local folder=workspace:FindFirstChild('ActiveActors')
local moved=0
if folder then
 for _,model in ipairs(folder:GetChildren()) do
  if model:IsA('Model') and model:GetAttribute('HasRig') and model:GetAttribute('Dead')~=true then
   local angle=moved*1.256
   local offset=Vector3.new(math.sin(angle)*9,0.5,math.cos(angle)*9)
   model:PivotTo(CFrame.new(hrp.Position+offset,hrp.Position))
   moved+=1
  end
 end
end
return 'pivoted:'..moved
'''
def main():
    log={}
    with h.connect() as m:
        try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.5)
        except Exception: pass
        print(h.text(m.start_play(h.STUDIO_ID))[:80],flush=True); time.sleep(7.5)
        h.exec_client(m,"local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes') remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'ok'")
        time.sleep(7)
        tp=h.exec_server(m,PIVOT)
        log['teleport']=tp.strip()
        print('pivot',tp.strip(),flush=True)
        time.sleep(4)
        s1=rows(pj(h.exec_client(m,SAMPLE)))
        time.sleep(1.5)
        s2=rows(pj(h.exec_client(m,SAMPLE)))
        ssrv=rows(pj(h.exec_server(m,SAMPLE)))
        moved=False; details=[]
        if len(s1)==len(s2) and s1:
            for i in range(len(s1)):
                diffs=[k for k,v in s1[i].get('hips',{}).items() if s2[i].get('hips',{}).get(k)!=v]
                if diffs: moved=True
                details.append({'id':s1[i].get('id'),'state':s2[i].get('state') if i<len(s2) else '?','changed':diffs[:6]})
        server_static=True
        for row in ssrv:
            for name,val in row.get('hips',{}).items():
                try:
                    if abs(float(val))>0.06: server_static=False
                except Exception: pass
        time.sleep(2.5)
        dbg=pj(h.exec_server(m,r'''local d=workspace:FindFirstChild('GFDebug') return {accepted=d and d:GetAttribute('Accepted'),hits=d and d:GetAttribute('Hits'),enemyHits=workspace:GetAttribute('GF_EnemyHits'),attempt=tostring(workspace:GetAttribute('GF_LastAttackAttempt')),flag=tostring(workspace:GetAttribute('GF_DebugCombat'))}'''))
        h.exec_server(m,r'''workspace:SetAttribute('GF_DebugCombat',true) workspace:SetAttribute('GF_DebugEnemy',true) return 'on' ''')
        time.sleep(4)
        dbg2=pj(h.exec_server(m,r'''local d=workspace:FindFirstChild('GFDebug') return {accepted=d and d:GetAttribute('Accepted'),attempt=tostring(workspace:GetAttribute('GF_LastAttackAttempt'))}'''))
        states=[r.get('state') for r in s2]
        log.update({'states':states,'client_anim_moving':moved,'server_joints_static':server_static,'details':details,'gated':dbg,'optin':dbg2,'client_rows':len(s1),'server_rows':len(ssrv)})
        aggroed=any(st not in ('Idle','nil') for st in states)
        gate_ok=(dbg.get('attempt') in (None,'nil'))
        optin_ok=dbg2.get('attempt') not in (None,'nil')
        log['aggroed']=aggroed; log['gate_ok']=gate_ok; log['optin_ok']=optin_ok
        log['passed']=bool(moved and server_static and aggroed)
        (OUT/'enemyanim_v716.json').write_text(json.dumps(log,indent=2))
        print(json.dumps({k:log[k] for k in ['aggroed','client_anim_moving','server_joints_static','gate_ok','optin_ok','passed']},indent=1))
        print('details',json.dumps(details)[:700])
if __name__=='__main__': main()
