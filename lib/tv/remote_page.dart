/// Boshqa telefon brauzerida ochiladigan pult (ilova o‘rnatmasdan).
/// QR kod `http://IP:8765/?k=PIN` manziliga olib keladi.
const remotePageHtml = r'''<!doctype html>
<html lang="uz"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" content="#0d0e12">
<title>Telefon TV pult</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none;-webkit-user-select:none}
html,body{margin:0;height:100%;background:radial-gradient(120% 80% at 50% 0%,#23263a,#0d0e12 70%);color:#eef;font:16px/1.3 system-ui,-apple-system,Roboto,sans-serif}
main{max-width:420px;margin:0 auto;min-height:100%;display:flex;flex-direction:column;gap:18px;padding:max(16px,env(safe-area-inset-top)) 16px max(16px,env(safe-area-inset-bottom))}
header{display:flex;justify-content:space-between;align-items:center}
h1{font-size:18px;margin:0}
#st{font-size:13px;padding:4px 10px;border-radius:99px;background:#3a2a10;color:#fbbf24}
#st.ok{background:#0f2e1c;color:#4ade80}
#now{min-height:20px;color:#9aa3c7;font-size:14px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#pad{position:relative;width:min(84vw,330px);aspect-ratio:1;margin:0 auto;border-radius:50%;
 background:radial-gradient(circle at 50% 35%,#3a3d4a,#1c1e26);box-shadow:inset 0 2px 0 #ffffff14,0 20px 40px #0008;touch-action:none}
#pad::after{content:"";position:absolute;inset:31%;border-radius:50%;background:radial-gradient(circle at 50% 30%,#4a4e5e,#262934);box-shadow:inset 0 1px 0 #ffffff1c}
.ar{position:absolute;color:#ffffff70;font-size:22px;pointer-events:none}
.ar.u{top:7%;left:50%;transform:translateX(-50%)}.ar.d{bottom:7%;left:50%;transform:translateX(-50%)}
.ar.l{left:8%;top:50%;transform:translateY(-50%)}.ar.r{right:8%;top:50%;transform:translateY(-50%)}
.row{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}
button{border:0;border-radius:18px;background:#22252f;color:#eef;font-size:22px;height:58px;box-shadow:inset 0 1px 0 #ffffff12}
button:active{background:#343847}
button small{display:block;font-size:11px;color:#9aa3c7}
form{display:flex;gap:8px}
input{flex:1;min-width:0;border:0;border-radius:14px;background:#22252f;color:#fff;font-size:16px;padding:14px;user-select:text;-webkit-user-select:text}
form button{width:72px;font-size:15px;background:#3b6cff}
.up{display:block;text-align:center;border-radius:16px;background:#1d3a8a;padding:16px;font-size:16px;font-weight:600}
.up:active{background:#2a4db0}
#upst{min-height:18px;text-align:center;color:#9aa3c7;font-size:14px}
#bar{height:6px;border-radius:3px;background:#22252f;overflow:hidden}#bar i{display:block;height:100%;width:0;background:#4ade80}
</style></head><body><main>
<header><h1>📺 Telefon TV</h1><span id="st">Ulanmoqda…</span></header>
<div id="now"></div>
<div id="pad"><span class="ar u">▲</span><span class="ar d">▼</span><span class="ar l">◀</span><span class="ar r">▶</span></div>
<div class="row">
 <button data-c="back">‹<small>Orqaga</small></button>
 <button data-c="home">⌂<small>Bosh</small></button>
 <button data-c="playPause">⏯<small>Pauza</small></button>
 <button data-c="mute">🔇<small>Ovoz</small></button>
 <button data-c="prev">⏮<small>Oldingi</small></button>
 <button data-c="volDown">−<small>Ovoz</small></button>
 <button data-c="volUp">+<small>Ovoz</small></button>
 <button data-c="next">⏭<small>Keyingi</small></button>
</div>
<label class="up">⬆ Telefondan video / rasm / musiqa yuborish<input id="fl" type="file" multiple accept="video/*,audio/*,image/*" hidden></label>
<div id="bar"><i id="bari"></i></div><div id="upst"></div>
<form id="f"><input id="txt" placeholder="Matn yozish (qidiruv, manzil…)" autocomplete="off"><button>Yuborish</button></form>
</main><script>
const key=new URLSearchParams(location.search).get('k')||'';
const st=document.getElementById('st');let ws,opened=false;
function connect(){
 ws=new WebSocket('ws://'+location.host+'/ws?k='+encodeURIComponent(key));
 ws.onopen=()=>{opened=true;st.textContent='Ulangan';st.className='ok'};
 ws.onclose=()=>{st.className='';st.textContent=opened?'Ulanmoqda…':'PIN noto‘g‘ri yoki TV o‘chiq';setTimeout(connect,1500)};
 ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch(_){return}
  if(m.t==='state')document.getElementById('now').textContent=m.title?('▶ '+m.title):'';
  if(m.t==='textFocus'){const i=document.getElementById('txt');i.value=m.value||'';i.placeholder=m.hint||'Matn';i.focus()}};
}
function send(c){if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:'cmd',c:c}));if(navigator.vibrate)navigator.vibrate(8)}
document.querySelectorAll('[data-c]').forEach(b=>b.addEventListener('click',()=>send(b.dataset.c)));
document.getElementById('f').addEventListener('submit',e=>{e.preventDefault();const i=document.getElementById('txt');
 if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:'text',v:i.value}));i.blur()});
const pad=document.getElementById('pad');let sx=0,sy=0,ox=0,oy=0,moved=false;
pad.addEventListener('pointerdown',e=>{sx=ox=e.clientX;sy=oy=e.clientY;moved=false;pad.setPointerCapture(e.pointerId)});
pad.addEventListener('pointermove',e=>{if(!pad.hasPointerCapture(e.pointerId))return;const dx=e.clientX-ox,dy=e.clientY-oy;
 if(Math.abs(dx)>42||Math.abs(dy)>42){moved=true;send(Math.abs(dx)>Math.abs(dy)?(dx>0?'right':'left'):(dy>0?'down':'up'));ox=e.clientX;oy=e.clientY}});
pad.addEventListener('pointerup',e=>{if(moved)return;const r=pad.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2,
 dx=e.clientX-cx,dy=e.clientY-cy;if(Math.hypot(dx,dy)<r.width*.19){send('ok');return}
 send(Math.abs(dx)>Math.abs(dy)?(dx>0?'right':'left'):(dy>0?'down':'up'))});
const upst=document.getElementById('upst'),bari=document.getElementById('bari');
function up(f,i,n){return new Promise(done=>{const x=new XMLHttpRequest();
 x.open('POST','/upload?k='+encodeURIComponent(key)+'&name='+encodeURIComponent(f.name)+'&index='+i+'&count='+n);
 x.upload.onprogress=e=>{if(e.lengthComputable){const p=Math.round(e.loaded/e.total*100);bari.style.width=p+'%';upst.textContent=(n>1?(i+1)+'/'+n+': ':'')+f.name+' — '+p+'%'}};
 x.onload=()=>{let m={};try{m=JSON.parse(x.responseText)}catch(_){}upst.textContent=x.status==200?'✓ '+f.name+' yuborildi':'✗ '+(m.error||('xato '+x.status));done()};
 x.onerror=()=>{upst.textContent='✗ Aloqa uzildi';done()};x.send(f)})}
document.getElementById('fl').addEventListener('change',async e=>{const fs=[...e.target.files];
 for(let i=0;i<fs.length;i++){bari.style.width='0';await up(fs[i],i,fs.length)}e.target.value=''});
connect();
</script></body></html>''';
