import ctypes, json, re, time
from pathlib import Path
import sys
sys.path.insert(0, r"C:\Users\tnguy\gf_tools")
from studio_mcp import StudioMCP, write_capture_response
import ai_evidence_runtime as h

OUT = Path(r"C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw")
OUT.mkdir(parents=True, exist_ok=True)
LOG={"checks":{},"captures":{},"errors":[]}

def rec(k,v): LOG['checks'][k]=v; print(k,json.dumps(v)[:1200] if isinstance(v,(dict,list)) else v,flush=True)
def cap(m,stem):
    try:
        paths=write_capture_response(m.capture(h.STUDIO_ID,stem),OUT,stem)
        LOG['captures'][stem]=paths; print('capture',stem,paths,flush=True)
    except Exception as e: LOG['errors'].append(f'capture {stem}: {e}')

def key(m, keycode, hold=80):
    return StudioMCP.content_text(m.call('user_keyboard_input',{'studio_id':h.STUDIO_ID,'datamodel_type':'Client','actions':[{'action':'keyDown','key_code':keycode},{'action':'wait','wait_time_ms':hold},{'action':'keyUp','key_code':keycode}]},timeout=20))

def mouse_hold(ms):
    # Real OS mouse input; the viewport is clicked once first because Studio does not route gameplay mouse
    # input to a play session until the 3D viewport has focus.
    try:
        import win32gui, win32con
        wins=[]
        def cb(hwnd,extra):
            if win32gui.IsWindowVisible(hwnd) and 'Playtest1 - Roblox Studio' in win32gui.GetWindowText(hwnd): wins.append(hwnd)
        win32gui.EnumWindows(cb,None)
        if wins:
            try: win32gui.SetForegroundWindow(wins[0])
            except Exception: pass
    except Exception: pass
    ctypes.windll.user32.SetCursorPos(960,520)
    ctypes.windll.user32.mouse_event(2,0,0,0,0); time.sleep(.04); ctypes.windll.user32.mouse_event(4,0,0,0,0)
    time.sleep(.25)
    ctypes.windll.user32.mouse_event(2,0,0,0,0)
    time.sleep(ms/1000)
    ctypes.windll.user32.mouse_event(4,0,0,0,0)
    time.sleep(.35)

def server_state(m):
    code=r'''
local Players=game:GetService('Players')
local p=Players:GetPlayers()[1]
local root=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local crates={}
for _,x in ipairs(workspace:GetChildren()) do
 if x.Name=='SupplyCrate' then
  local dist=root and (x.Position-root.Position).Magnitude or -1
  table.insert(crates,{pos=tostring(x.Position),dist=dist,consumed=x:GetAttribute('Consumed')})
 end
end
local dbg=workspace:FindFirstChild('GFDebug')
return {inMission=workspace:GetAttribute('GF_InMission'),lz=tostring(workspace:GetAttribute('GF_LZ')),root=root and tostring(root.Position) or 'nil',count=#crates,crates=crates,gren=p and p:GetAttribute('GrenadeCharges') or nil,accepted=dbg and dbg:GetAttribute('Accepted') or 0,refill=workspace:GetAttribute('GF_SupplyRefill'),grenlog=workspace:GetAttribute('GF_SupplyGrenades')}
'''
    return h.exec_server(m,code)

def hud_state(m):
    code=r'''
local p=game:GetService('Players').LocalPlayer
local texts={}
for _,x in ipairs(p.PlayerGui:GetDescendants()) do
 if x:IsA('TextLabel') and (string.find(x.Text,'%d+ / %d+') or x.Text=='RESUPPLY' or string.find(x.Text,'GRENADE')) then table.insert(texts,x.Text) end
end
return {texts=texts,mouse=tostring(game:GetService('UserInputService').MouseBehavior)}
'''
    return h.exec_client(m,code)

def parse_json(txt):
    try:return json.loads(txt)
    except Exception:return {'raw':txt}

def arr(v):
    if isinstance(v,list): return v
    if isinstance(v,dict): return [v[k] for k in sorted(v.keys(),key=lambda x:int(x) if str(x).isdigit() else str(x))]
    return []

def wait_server(m,pred,timeout=10,interval=.4):
    end=time.time()+timeout; last=None
    while time.time()<end:
        last=parse_json(server_state(m))
        if pred(last): return {'ok':True,'state':last}
        time.sleep(interval)
    return {'ok':False,'state':last}

def main():
    with h.connect() as m:
        try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.5)
        except Exception: pass
        print(h.text(m.start_play(h.STUDIO_ID))[:100],flush=True); time.sleep(7)
        fire='''local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes') remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'deploy-requested' '''
        rec('deploy_fire',h.exec_client(m,fire))
        r=wait_server(m,lambda s:s.get('inMission')==True and s.get('count',0)>=3,timeout=12)
        rec('mission_crates_spawned',r)
        time.sleep(1)
        st=parse_json(server_state(m)); rec('spawn_supply_layout',st)
        cap(m,'supply_spawn_layout')
        # Spawn proximity: nearest crate should be close enough to see/use immediately at insertion.
        rec('nearest_crate_distance',min([c.get('dist',999) for c in arr(st.get('crates'))] or [999]))

        gren0=st.get('gren')
        key(m,'G',hold=90); time.sleep(1.05)
        key(m,'G',hold=90); time.sleep(1.3)
        st=parse_json(server_state(m)); rec('after_two_real_grenade_inputs',{'before':gren0,'after':st.get('gren'),'accepted':st.get('accepted')})

        accepted0=st.get('accepted') or 0
        mouse_hold(1350)
        st=parse_json(server_state(m)); accepted1=st.get('accepted') or 0
        rec('after_real_fire_input',{'accepted_before':accepted0,'accepted_after':accepted1,'shots_accepted':accepted1-accepted0})
        rec('hud_before_supply',parse_json(hud_state(m)))
        cap(m,'supply_before_use')

        # Move next to the nearest remaining crate, then use the actual proximity-prompt key.
        tp=r'''
local Players=game:GetService('Players')
local p=Players:GetPlayers()[1]
local root=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local best,bd=nil,math.huge
for _,x in ipairs(workspace:GetChildren()) do if x.Name=='SupplyCrate' then local d=(x.Position-root.Position).Magnitude if d<bd then best=x bd=d end end end
if best and root then root.CFrame=CFrame.new(best.Position+Vector3.new(2.5,3,0),best.Position) end
return {crate=best and tostring(best.Position) or 'none',dist=bd}
'''
        rec('teleport_to_nearest_crate',parse_json(h.exec_server(m,tp)))
        time.sleep(.5)
        count_before=parse_json(server_state(m)).get('count')
        rec('resupply_key_input',key(m,'E',hold=800))
        time.sleep(1)
        st=parse_json(server_state(m)); rec('after_resupply_prompt',{'count_before':count_before,'state':st})
        rec('hud_after_supply',parse_json(hud_state(m)))
        cap(m,'supply_after_use')
        refill1=st.get('refill')
        # Press again at the same place: the destroyed crate must not provide a second use.
        key(m,'E',hold=800); time.sleep(.7)
        st2=parse_json(server_state(m)); rec('after_second_use_attempt',{'refill_before':refill1,'refill_after':st2.get('refill'),'count':st2.get('count'),'one_use_pass':st2.get('refill')==refill1 and st2.get('count')==st.get('count')})

        hudtexts=(parse_json(hud_state(m)).get('texts') or [])
        hudjoined=' | '.join(hudtexts)
        passed=(r.get('ok') and min([c.get('dist',999) for c in arr(parse_json(server_state(m)).get('crates'))] or [999])<20 and (accepted1-accepted0)>=4 and st.get('gren')==3 and st.get('count')==count_before-1 and refill1 and 'ammo=28 reserve=268' in str(refill1) and ('28 / 28' in hudjoined or '28 / 28' in str(LOG['checks'].get('hud_after_supply'))))
        rec('passed',bool(passed))
    (OUT/'supply_prompt_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
    print('wrote',OUT/'supply_prompt_verification.json',flush=True)

if __name__=='__main__':
    try: main()
    except Exception as e:
        LOG['errors'].append(f'fatal {type(e).__name__}: {e}')
        (OUT/'supply_prompt_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
        raise
