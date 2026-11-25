import ctypes, json, time
from pathlib import Path
import sys
sys.path.insert(0,r'C:\Users\tnguy\gf_tools')
import ai_evidence_runtime as h

OUT=Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw'); OUT.mkdir(parents=True,exist_ok=True)
LOG={'checks':{},'errors':[]}

def rec(k,v):
    LOG['checks'][k]=v
    print(k,json.dumps(v)[:1800] if isinstance(v,(dict,list)) else v,flush=True)

def pj(s):
    try:return json.loads(s)
    except Exception:return {'raw':s}

def arr(v):
    if isinstance(v,list): return v
    if isinstance(v,dict):
        return [v[k] for k in sorted(v.keys(),key=lambda x:int(x) if str(x).isdigit() else str(x))]
    return []

def focus():
    try:
        import win32gui
        wins=[]
        def cb(hwnd,extra):
            if win32gui.IsWindowVisible(hwnd) and 'Playtest1 - Roblox Studio' in win32gui.GetWindowText(hwnd): wins.append(hwnd)
        win32gui.EnumWindows(cb,None)
        if wins:
            try: win32gui.SetForegroundWindow(wins[0])
            except Exception: pass
    except Exception: pass
    ctypes.windll.user32.SetCursorPos(960,520)
    ctypes.windll.user32.mouse_event(2,0,0,0,0); time.sleep(.035); ctypes.windll.user32.mouse_event(4,0,0,0,0)
    time.sleep(.22)

def fire_burst(m,ms):
    # Studio MCP input injection is more reliable than OS mouse_event here. Coordinates are viewport
    # coordinates; (960,520) was experimentally confirmed to reach gameplay rather than a UI/Studio surface.
    from studio_mcp import StudioMCP
    actions=[
        {'action':'moveTo','x':960,'y':520},
        {'action':'mouseButtonDown','mouse_button':'left'},
        {'action':'wait','wait_time_ms':ms},
        {'action':'mouseButtonUp','mouse_button':'left'},
    ]
    StudioMCP.content_text(m.call('user_mouse_input',{'studio_id':h.STUDIO_ID,'datamodel_type':'Client','actions':actions},timeout=20))
    time.sleep(.28)

def counters(m):
    code=r'''
local folder=game:GetService('SoundService'):FindFirstChild('GFAudioVoices')
local sounds={}
for _,x in ipairs(workspace:GetDescendants()) do
 if x:IsA('Sound') and string.find(x:GetFullName(),'GFAudioAnchor') then
  table.insert(sounds,{path=x:GetFullName(),id=x.SoundId,playing=x.IsPlaying,vol=x.Volume,pitch=x.PlaybackSpeed})
 end
end
local rt=game:GetService('Players').LocalPlayer:FindFirstChild('PlayerScripts') and game:GetService('Players').LocalPlayer.PlayerScripts:FindFirstChild('GFAudioRuntime')
return {hit=folder and folder:GetAttribute('count_hit_flesh') or 0,surface=folder and folder:GetAttribute('count_hit_surface') or 0,death=folder and folder:GetAttribute('count_enemy_death') or 0,hurt=folder and folder:GetAttribute('count_player_hurt') or 0,removed=rt and rt:GetAttribute('gf_stock_death_sounds_removed') or 0,sounds=sounds}
'''
    return pj(h.exec_client(m,code))

def combatdbg(m):
    return pj(h.exec_server(m,r'''local d=workspace:FindFirstChild('GFDebug') return {accepted=d and d:GetAttribute('Accepted') or 0,hits=d and d:GetAttribute('Hits') or 0,rejected=d and d:GetAttribute('Rejected') or 0,lastReject=tostring(d and d:GetAttribute('LastReject'))}'''))

def target_row(data,eid):
    rows=[x for x in data.get('actors',[]) if x.get('id')==eid]
    return rows[0] if rows else None

def main():
    with h.connect() as m:
        try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.4)
        except Exception: pass
        print(h.text(m.start_play(h.STUDIO_ID))[:100],flush=True); time.sleep(7)
        rec('initial_counters',counters(m))
        fire='''local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes') remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'deploy-requested' '''
        rec('deploy',h.exec_client(m,fire)); time.sleep(5)
        rec('force_no_spread',h.force_no_spread(m))
        data=h.summary(m)
        actors=[a for a in data.get('actors',[]) if not a.get('dead') and a.get('id') in ('Marksman','Rifleman','Scout')]
        if not actors: raise RuntimeError('no suitable enemy')
        a=actors[0]; eid=a['id']; rec('chosen_enemy',a)
        place=f'''
local Players=game:GetService('Players') local p=Players:GetPlayers()[1] local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local folder=workspace:FindFirstChild('ActiveActors') local target=nil
for _,x in ipairs(folder:GetChildren()) do if tostring(x:GetAttribute('EnemyId'))=='{eid}' then target=x break end end
if root and target then target:PivotTo(CFrame.new(root.Position+root.CFrame.LookVector*10+Vector3.new(0,1,0),root.Position)) end
return {{target=target and target.Name or 'none'}}
'''
        rec('place_enemy',pj(h.exec_server(m,place)))
        rec('camera_track',h.camera_track_actor(m,eid,seconds=12,distance=11,height=2))
        focus()
        dead=False
        for burst in range(1,9):
            precur=h.summary(m); prerow=target_row(precur,eid) or {}
            # Use a short final burst once the target is nearly dead so the positional death voice is not
            # immediately overwritten by the pooled voices of unnecessary follow-up shots.
            burst_ms=140 if (prerow.get('health') or 999)<45 else 560
            fire_burst(m,burst_ms)
            cur=h.summary(m); row=target_row(cur,eid); dbg=combatdbg(m)
            rec('burst_'+str(burst),{'target':row,'combat':dbg,'audio':{k:v for k,v in counters(m).items() if k!='sounds'}})
            if row and row.get('dead')==True:
                dead=True; break
        rec('enemy_dead_observed',dead)
        time.sleep(.8)
        afterkill=counters(m); rec('after_kill_audio',afterkill)

        # Now hold the evidence camera on open terrain and fire real input. Surface impacts must use hit_surface,
        # not the organic hit_flesh cue.
        camcode=r'''
local RunService=game:GetService('RunService') local cam=workspace.CurrentCamera local p=game:GetService('Players').LocalPlayer local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local key='GF_AudioTerrainCam' local start=os.clock()
RunService:BindToRenderStep(key,Enum.RenderPriority.Camera.Value+1,function()
 if root then cam.CFrame=CFrame.lookAt(root.Position+Vector3.new(0,4,-5),root.Position+Vector3.new(0,-2,-18)) end
 if os.clock()-start>4 then RunService:UnbindFromRenderStep(key) end
end)
return 'terrain-camera'
'''
        rec('terrain_camera',h.exec_client(m,camcode))
        pre=counters(m)
        focus(); fire_burst(m,700)
        post=counters(m)
        rec('terrain_surface_comparison',{'before':{k:v for k,v in pre.items() if k!='sounds'},'after':{k:v for k,v in post.items() if k!='sounds'},'surface_delta':post.get('surface',0)-pre.get('surface',0),'flesh_delta':post.get('hit',0)-pre.get('hit',0)})
        finaldbg=combatdbg(m); rec('final_combat_debug',finaldbg)
        sounds=arr(post.get('sounds'))
        deathpitch=[s for s in sounds if isinstance(s,dict) and s.get('id')=='rbxasset://sounds/metal.ogg' and (s.get('pitch') or 9)<1.0]
        rec('low_pitch_death_voice_observed',len(deathpitch)>0)
        passed=bool(dead and afterkill.get('death',0)>=1 and post.get('surface',0)>pre.get('surface',0) and post.get('hit',0)==pre.get('hit',0))
        rec('passed',passed)
    (OUT/'audio_combat_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
    print('wrote',OUT/'audio_combat_verification.json',flush=True)

if __name__=='__main__':
    try: main()
    except Exception as e:
        LOG['errors'].append(f'fatal {type(e).__name__}: {e}')
        (OUT/'audio_combat_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
        raise
