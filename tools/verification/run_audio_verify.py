import json,time
from pathlib import Path
import sys
sys.path.insert(0,r'C:\Users\tnguy\gf_tools')
import ai_evidence_runtime as h
OUT=Path(r'C:\Users\tnguy\galactic-force\evidence\v685-fix-runtime-20261125\raw'); OUT.mkdir(parents=True,exist_ok=True)
LOG={}

def rec(k,v): LOG[k]=v; print(k,json.dumps(v)[:1600] if isinstance(v,(dict,list)) else v,flush=True)
def pj(s):
 try:return json.loads(s)
 except:return {'raw':s}

def scan_client(m):
 code=r'''
local out={sounds={},attrs={},counters={}}
local function scan(root,scope)
 for _,x in ipairs(root:GetDescendants()) do
  if x:IsA('Sound') then table.insert(out.sounds,{scope=scope,path=x:GetFullName(),id=x.SoundId,playing=x.IsPlaying,vol=x.Volume}) end
 end
end
scan(workspace,'workspace') scan(game:GetService('SoundService'),'soundservice')
local ps=game:GetService('Players').LocalPlayer:FindFirstChild('PlayerScripts')
local rt=ps and ps:FindFirstChild('GFAudioRuntime')
out.attrs.removed=rt and rt:GetAttribute('gf_stock_death_sounds_removed') or nil
local folder=game:GetService('SoundService'):FindFirstChild('GFAudioVoices')
if folder then
 out.counters.hit_flesh=folder:GetAttribute('count_hit_flesh') or 0
 out.counters.enemy_death=folder:GetAttribute('count_enemy_death') or 0
 out.counters.player_hurt=folder:GetAttribute('count_player_hurt') or 0
end
return out
'''
 return pj(h.exec_client(m,code))

def main():
 with h.connect() as m:
  try: h.text(m.stop_play(h.STUDIO_ID)); time.sleep(1.5)
  except Exception: pass
  print(h.text(m.start_play(h.STUDIO_ID))[:100],flush=True); time.sleep(7)
  rec('initial_audio_scan',scan_client(m))
  fire='''local remotes=game:GetService('ReplicatedStorage'):WaitForChild('GF'):WaitForChild('Remotes') remotes:WaitForChild('RequestDeploy'):FireServer({difficulty='Easy',template='SABOTAGE_RELAY'}) return 'deploy-requested' '''
  rec('deploy',h.exec_client(m,fire)); time.sleep(5)
  rec('force_no_spread',h.force_no_spread(m))
  data=h.summary(m); rec('actors_before',data)
  actors=[a for a in data.get('actors',[]) if not a.get('dead') and a.get('id') not in ('BastionWalker','HighMarshalVeyr')]
  if not actors: raise RuntimeError('no enemy actor')
  a=actors[0]
  # Move one enemy into a flat open line near the LZ for a controlled live-hit audio test.
  place=f'''
local Players=game:GetService('Players') local p=Players:GetPlayers()[1] local root=p.Character and p.Character:FindFirstChild('HumanoidRootPart')
local folder=workspace:FindFirstChild('ActiveActors') local target=nil
for _,x in ipairs(folder:GetChildren()) do if tostring(x:GetAttribute('EnemyId'))=='{a.get('id')}' then target=x break end end
if root and target then
 local pos=root.Position+root.CFrame.LookVector*10 target:PivotTo(CFrame.new(pos+Vector3.new(0,1,0),root.Position))
end
return {{target=target and target.Name or 'none',pos=target and target.PrimaryPart and tostring(target.PrimaryPart.Position) or 'nopart'}}
'''
  rec('place_enemy',pj(h.exec_server(m,place)))
  time.sleep(.4)
  before=h.summary(m); rec('target_before',{'id':a.get('id'),'health':[x for x in before.get('actors',[]) if x.get('id')==a.get('id')]})
  hits=[]
  for i in range(8):
   cur=h.summary(m); rows=[x for x in cur.get('actors',[]) if x.get('id')==a.get('id')]
   if not rows or rows[0].get('dead')==True: break
   x,y,z=rows[0]['x'],rows[0]['y'],rows[0]['z']
   hits.append(h.fire_at(m,x,y,z))
   time.sleep(.16)
  rec('fire_calls',hits)
  time.sleep(1.2)
  after=h.summary(m); rec('target_after',{'enemyHits':after.get('enemyHits'),'rows':[x for x in after.get('actors',[]) if x.get('id')==a.get('id')]})
  scan=scan_client(m); rec('final_audio_scan',scan)
  ids=[x.get('id','') for x in scan.get('sounds',[]) if isinstance(x,dict)]
  paths=[x.get('path','') for x in scan.get('sounds',[]) if isinstance(x,dict)]
  passed=(scan.get('attrs',{}).get('removed') or 0)>=1 and not any('uuhhh.mp3' in x for x in ids) and not any(x.endswith('.Died') for x in paths)
  rec('passed_static_oof_removal',passed)
  rec('event_counters',scan.get('counters'))
 (OUT/'audio_feedback_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
 print('wrote',OUT/'audio_feedback_verification.json',flush=True)

if __name__=='__main__':
 try: main()
 except Exception as e:
  LOG['fatal']=f'{type(e).__name__}: {e}'
  (OUT/'audio_feedback_verification.json').write_text(json.dumps(LOG,indent=2),encoding='utf-8')
  raise
