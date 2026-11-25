# usage: python3 gf_deploy.py <tgz> <probe.lua or -> <marker> [save=1]
import subprocess,json,os,select,time,tarfile,sys
tgz,probe,marker=sys.argv[1],sys.argv[2],sys.argv[3]
files={}
if tgz!='-':
 t=tarfile.open(tgz,'r:gz')
 files={m.name.replace('playtest1_current/',''):t.extractfile(m).read().decode() for m in t.getmembers() if m.isfile()}
p=subprocess.Popen(['/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL);buf=b''
def send(o):p.stdin.write((json.dumps(o)+'\n').encode());p.stdin.flush()
def read(t):
 global buf
 fd=p.stdout.fileno();end=time.time()+t
 while time.time()<end:
  if b'\n' in buf:
   line,buf=buf.split(b'\n',1)
   if line.strip():return json.loads(line)
  r,_,_=select.select([fd],[],[],0.3)
  if r:buf+=os.read(fd,65536)
 raise TimeoutError('read')
def waitid(i,t=50):
 end=time.time()+t
 while time.time()<end:
  m=read(end-time.time())
  if m.get('id')==i:return m
 raise TimeoutError('waitid')
N=[10]
def call(n,args,t=50):
 N[0]+=1;send({'jsonrpc':'2.0','id':N[0],'method':'tools/call','params':{'name':n,'arguments':args}});return waitid(N[0],t)
def text(m):return ''.join(c.get('text','') for c in m.get('result',{}).get('content',[]))
try:
 send({'jsonrpc':'2.0','id':1,'method':'initialize','params':{'protocolVersion':'2024-11-05','capabilities':{},'clientInfo':{'name':'x','version':'1'}}});waitid(1);send({'jsonrpc':'2.0','method':'notifications/initialized','params':{}})
 sid=json.loads(text(call('list_roblox_studios',{})))['studios'][0]['id']
 for path,src in files.items():
  dot='game.'+'.'.join(x for x in path[:-5].split('/'))
  code='local target='+dot+' target.Source=[=['+src+']=] local f,e=loadstring(target.Source,target:GetFullName()) return e and ("ERR:"..tostring(e)) or "ok"'
  print(path,text(call('execute_luau',{'studio_id':sid,'datamodel_type':'Edit','code':code}))[:300])
 if files and os.environ.get('NOSAVE')!='1':print('save',text(call('save_place',{'studio_id':sid},60))[:120])
 if probe!='-':
  src=open(probe).read()
  print('create',text(call('execute_luau',{'studio_id':sid,'datamodel_type':'Edit','code':'local s=Instance.new("Script") s.Name="GF_TMP_PROBE" s.Source=[=['+src+']=] s.Parent=game.ServerScriptService return "created"'})))
  print('start',text(call('start_stop_play',{'studio_id':sid,'is_start':True}))[:40])
  time.sleep(13);con=''
  for _ in range(int(os.environ.get('POLLS','6'))):
   con=text(call('get_console_output',{'studio_id':sid},25))
   if marker+'_DONE' in con or marker+'] FAIL' in con:break
   time.sleep(3)
  print('\n'.join(l for l in con.splitlines() if marker in l or 'config check' in l or 'error' in l.lower() or 'GF_TMP_PROBE' in l or 'gf_tmp' in l.lower())[-2500:])
  print('stop',text(call('start_stop_play',{'studio_id':sid,'is_start':False}))[:40]);time.sleep(2)
  print('cleanup',text(call('execute_luau',{'studio_id':sid,'datamodel_type':'Edit','code':'local s=game.ServerScriptService:FindFirstChild("GF_TMP_PROBE") if s then s:Destroy() return "removed" end return "missing"'})))
finally:p.kill()
