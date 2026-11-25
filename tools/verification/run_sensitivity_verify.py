import ctypes, json, time
from pathlib import Path
from studio_mcp import StudioMCP
import win32gui, win32con

OUT = Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw')

ANGLE_CODE = r'''
local camera = workspace.CurrentCamera
if not camera then return {ok=false,error='no camera'} end
local l = camera.CFrame.LookVector
return {ok=true,yaw=math.deg(math.atan2(l.X,l.Z)),behavior=tostring(game:GetService('UserInputService').MouseBehavior),sens=game:GetService('Players').LocalPlayer:GetAttribute('GF_Setting_AimSensitivity')}
'''
CURSOR_CODE = r'''
local uis=game:GetService('UserInputService')
local player=game:GetService('Players').LocalPlayer
local gui=player and player:FindFirstChild('PlayerGui')
local settings=gui and gui:FindFirstChild('GF_Settings')
return {ok=true,behavior=tostring(uis.MouseBehavior),settingsEnabled=settings and settings.Enabled or false,uiOpen=workspace:GetAttribute('GF_UIOpen')}
'''
class POINT(ctypes.Structure):
    _fields_=[('x',ctypes.c_long),('y',ctypes.c_long)]

def cursor_pos():
    p=POINT(); ctypes.windll.user32.GetCursorPos(ctypes.byref(p)); return p.x,p.y

def focus_studio():
    wins=[]
    def cb(h,extra):
        if win32gui.IsWindowVisible(h) and 'Playtest1 - Roblox Studio' in win32gui.GetWindowText(h):
            wins.append(h)
    win32gui.EnumWindows(cb,None)
    if not wins: raise RuntimeError('Playtest1 Studio window not found')
    h=wins[0]
    win32gui.ShowWindow(h,win32con.SW_RESTORE)
    try:
        win32gui.SetForegroundWindow(h)
    except Exception:
        pass
    time.sleep(.25)
    # The 3D viewport does not receive real mouse deltas until it has been clicked/focused once.
    ctypes.windll.user32.SetCursorPos(960,520)
    ctypes.windll.user32.mouse_event(2,0,0,0,0); time.sleep(.04); ctypes.windll.user32.mouse_event(4,0,0,0,0)
    time.sleep(.55)

def rel_move(px,steps=20):
    step=max(1,int(abs(px)/steps)) * (1 if px>=0 else -1)
    moved=0
    while abs(moved)<abs(px):
        d=step if abs(moved+step)<=abs(px) else px-moved
        ctypes.windll.user32.mouse_event(1,d,0,0,0)
        moved+=d
        time.sleep(.008)
    time.sleep(.3)

def exe(mcp,sid,dm,code,timeout=30):
    r=mcp.execute(sid,dm,code,timeout=timeout)
    txt=StudioMCP.content_text(r)
    try:return json.loads(txt)
    except Exception:return {'raw':txt}

def norm_delta(a,b):
    return (b-a+180)%360-180

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    original_cursor=cursor_pos()
    mcp=StudioMCP(); studio=mcp.wait_for_studio(); sid=studio['id']
    state=StudioMCP.content_text(mcp.studio_state(sid))
    result={'studio':studio,'initial_state':state,'checks':{},'input_method':'real Windows mouse_event after focusing/clicking the 3D viewport'}
    if 'Current Studio Mode: Edit' in state:
        result['checks']['start_play']=StudioMCP.content_text(mcp.call('start_stop_play',{'studio_id':sid,'is_start':True},timeout=30))
        time.sleep(4)
    focus_studio()
    a={}
    for _ in range(20):
        a=exe(mcp,sid,'Client',ANGLE_CODE)
        if a.get('ok'): break
        time.sleep(0.5)
    result['initial_camera']=a
    time.sleep(0.5)

    before=exe(mcp,sid,'Client',ANGLE_CODE)
    rel_move(100)
    after=exe(mcp,sid,'Client',ANGLE_CODE)
    locked_delta=norm_delta(before.get('yaw',0),after.get('yaw',0)) if before.get('ok') and after.get('ok') else None
    expected=100*0.0009*180/3.141592653589793
    result['locked_100mickeys']={'before':before,'after':after,'delta_degrees':locked_delta,'absolute_delta_degrees':abs(locked_delta) if locked_delta is not None else None,'expected_degrees_at_sens1':expected,'pass':locked_delta is not None and abs(abs(locked_delta)-expected)<1.5}

    exe(mcp,sid,'Server',"workspace:SetAttribute('GF_SettingsOpen', true); return {ok=true}")
    time.sleep(0.8)
    cursor=exe(mcp,sid,'Client',CURSOR_CODE)
    before=exe(mcp,sid,'Client',ANGLE_CODE)
    rel_move(140)
    after=exe(mcp,sid,'Client',ANGLE_CODE)
    cursor_delta=norm_delta(before.get('yaw',0),after.get('yaw',0)) if before.get('ok') and after.get('ok') else None
    result['cursor_140mickeys']={'cursor_state':cursor,'before':before,'after':after,'delta_degrees':cursor_delta,'pass':cursor.get('behavior')=='Enum.MouseBehavior.Default' and cursor_delta is not None and abs(cursor_delta)<0.7}
    exe(mcp,sid,'Server',"workspace:SetAttribute('GF_SettingsOpen', false); return {ok=true}")
    time.sleep(0.5)
    result['after_close']=exe(mcp,sid,'Client',CURSOR_CODE)
    ctypes.windll.user32.SetCursorPos(*original_cursor)

    result['passed']=bool(result['locked_100mickeys']['pass'] and result['cursor_140mickeys']['pass'])
    (OUT/'sensitivity_cursor_verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2)[:5000])
    print('wrote',OUT/'sensitivity_cursor_verification.json')
    mcp.proc.kill()

if __name__=='__main__': main()
