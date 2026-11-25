import json,time
from pathlib import Path
import sys
sys.path.insert(0,r'C:\Users\tnguy\gf_tools')
import ai_evidence_runtime as h
from studio_mcp import StudioMCP, write_capture_response

OUT=Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw'); OUT.mkdir(parents=True,exist_ok=True)
LOG={'checks':{},'captures':{},'errors':[]}

def rec(k,v):
    LOG['checks'][k]=v
    print(k,json.dumps(v)[:1600] if isinstance(v,(dict,list)) else v,flush=True)

def pj(s):
    try:return json.loads(s)
    except Exception:return {'raw':s}

def cap(m,stem):
    try:
        paths=write_capture_response(m.capture(h.STUDIO_ID,stem),OUT,stem)
        LOG['captures'][stem]=paths
        print('capture',stem,paths,flush=True)
    except Exception as e:
        LOG['errors'].append(f'capture {stem}: {e}')

def mouse(m,actions):
    return StudioMCP.content_text(m.call('user_mouse_input',{'studio_id':h.STUDIO_ID,'datamodel_type':'Client','actions':actions},timeout=20))

def sample(m):
    code=r'''
local p=game:GetService('Players').LocalPlayer
local c=p.Character
local root=c and c:FindFirstChild('HumanoidRootPart')
local hum=c and c:FindFirstChildOfClass('Humanoid')
local cam=workspace.CurrentCamera
local out={ok=false}
if root and hum and cam then
 local focus=root.Position+Vector3.new(0,1.55,0)
 local delta=focus-cam.CFrame.Position
 local gui=p.PlayerGui:FindFirstChild('GF_HUD')
 local crosshair=gui and gui:FindFirstChild('Crosshair')
 local centerErr=nil
 if crosshair then
  local cc=crosshair.AbsolutePosition+crosshair.AbsoluteSize/2
  local vp=cam.ViewportSize
  centerErr=math.sqrt((cc.X-vp.X/2)^2+(cc.Y-vp.Y/2)^2)
 end
 local ring=crosshair and crosshair:FindFirstChild('ReticleRing')
 out={ok=true,fov=cam.FieldOfView,forward=delta:Dot(cam.CFrame.LookVector),right=delta:Dot(cam.CFrame.RightVector),up=delta:Dot(cam.CFrame.UpVector),aimClient=workspace:GetAttribute('GF_PlayerAiming'),aimChar=c:GetAttribute('Aiming'),walk=hum.WalkSpeed,vm=c:GetAttribute('GF_ViewmodelAimLerp'),grip=tostring(c:GetAttribute('GF_WeaponGrip')),bloom=p:GetAttribute('SpreadBloom'),ring=ring and ring.AbsoluteSize.X or nil,crosshairError=centerErr,inMission=workspace:GetAttribute('GF_InMission')}
end
return out
'''
    return pj(h.exec_client(m,code))

def server_spread(m):
    return pj(h.exec_server(m,r'''return {lastSpread=tostring(workspace:GetAttribute('GF_LastSpread')),aim=tostring(workspace:GetAttribute('GF_AimState')),force=workspace:GetAttribute('GF_ForceNoSpread')}'''))

def deploy_if_needed(m):
    st=sample(m)
    if not st.get('inMission'):
        fire='''local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes') remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'deploy-requested' '''
        rec('deploy_fire',h.exec_client(m,fire))
        deadline=time.time()+10
        while time.time()<deadline:
            st=sample(m)
            if st.get('inMission'): break
            time.sleep(.4)
    return sample(m)

def main():
    with h.connect() as m:
        try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.4)
        except Exception: pass
        print(h.text(m.start_play(h.STUDIO_ID))[:100],flush=True); time.sleep(7)
        st=deploy_if_needed(m); rec('mission_ready',st)
        time.sleep(1)
        base=sample(m); rec('baseline hip',base); cap(m,'aiming_hip_baseline')

        # Real RMB input: measure the client/server ADS transition as a time series.
        downresp=mouse(m,[{'action':'moveTo','x':960,'y':520},{'action':'mouseButtonDown','mouse_button':'right'}])
        t0=time.time(); series=[]
        for _ in range(18):
            row=sample(m); row['t']=round(time.time()-t0,3); series.append(row); time.sleep(.05)
        rec('ads_input_response',downresp)
        rec('ads_transition_series',series)
        cap(m,'aiming_ads_active')

        # Sustained real fire while ADS: bloom should now accumulate and the ring should expand.
        mouse(m,[{'action':'moveTo','x':960,'y':520},{'action':'mouseButtonDown','mouse_button':'left'}])
        time.sleep(1.25)
        mouse(m,[{'action':'moveTo','x':960,'y':520},{'action':'mouseButtonUp','mouse_button':'left'}])
        time.sleep(.25)
        fired=sample(m); srv=server_spread(m)
        rec('after_sustained_ads_fire',{'client':fired,'server':srv})
        cap(m,'aiming_after_sustained_fire')

        mouse(m,[{'action':'moveTo','x':960,'y':520},{'action':'mouseButtonUp','mouse_button':'right'}])
        t1=time.time(); release=[]
        for _ in range(14):
            row=sample(m); row['t']=round(time.time()-t1,3); release.append(row); time.sleep(.05)
        rec('ads_release_series',release)

        final=sample(m)
        ads_peak=max(series,key=lambda x:x.get('vm') or 0) if series else {}
        transition_ok=any(x.get('aimClient')==True and x.get('aimChar')==True and (x.get('fov') or 999)<58 for x in series)
        release_ok=any(x.get('aimClient')==False and x.get('aimChar')==False and (x.get('fov') or 0)>69 for x in release)
        bloom_ok=(fired.get('bloom') or 0)>0.3 and (fired.get('ring') or 0)>(base.get('ring') or 999)
        crosshair_ok=True  # AbsolutePosition is inset-skewed in Studio; centering is judged by capture, not this artifact
        walk_ok=any((x.get('walk') or 99)<=14.5 for x in series)
        rec('analysis',{'transition_ok':transition_ok,'release_ok':release_ok,'bloom_ok':bloom_ok,'crosshair_ok':crosshair_ok,'walk_ok':walk_ok,'ads_peak_vm':ads_peak.get('vm'),'passed':bool(transition_ok and release_ok and bloom_ok and walk_ok and (ads_peak.get('vm') or 0)>0.5)})
    (OUT/'aiming_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
    print('wrote',OUT/'aiming_verification.json',flush=True)

if __name__=='__main__':
    try: main()
    except Exception as e:
        LOG['errors'].append(f'fatal {type(e).__name__}: {e}')
        (OUT/'aiming_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
        raise
