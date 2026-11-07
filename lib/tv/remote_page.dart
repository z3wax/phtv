/// Boshqa telefon brauzerida ochiladigan pult (ilova o‘rnatmasdan).
/// QR kod `http://IP:8765/?k=PIN` manziliga olib keladi.
/// Ko‘rinishi — Apple TV pulti uslubida, to‘liq qora.
const remotePageHtml = r'''<!doctype html>
<html lang="uz"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover">
<meta name="theme-color" content="#000000">
<title>Telefon TV pult</title>
<style>
:root{color-scheme:dark;--ink:#f2f2f7;--line:#242427}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;user-select:none;-webkit-user-select:none}
html,body{margin:0;height:100%;background:#000;color:var(--ink);font:16px/1.3 -apple-system,system-ui,Roboto,sans-serif;overflow:hidden}
main{height:100%;display:flex;flex-direction:column;align-items:center;padding:max(10px,env(safe-area-inset-top)) 14px max(10px,env(safe-area-inset-bottom))}
header{width:100%;max-width:440px;display:flex;justify-content:space-between;align-items:center;gap:8px}
h1{font-size:17px;margin:0}
#st{font-size:12px;padding:4px 10px;border-radius:99px;border:1px solid #2c2c2e;color:#ffd60a}
#st.ok{color:#30d158}
#now{width:100%;max-width:440px;min-height:20px;margin:4px 0;color:#8e8e93;font-size:13px;text-align:center;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
#wrap{flex:1;min-height:0;width:100%;display:flex;align-items:center;justify-content:center}
.remote{--u:min(1px,calc((100vh - 120px)/700),calc((100vw - 40px)/250));width:calc(250*var(--u));padding:calc(18*var(--u)) calc(22*var(--u)) calc(26*var(--u));
 border-radius:calc(56*var(--u));background:linear-gradient(#1c1c1f,#0d0d0f 45%,#060607);border:1px solid #2a2a2e;
 box-shadow:0 -1px 0 #ffffff14,0 24px 40px #000;display:flex;flex-direction:column;align-items:center}
.top{position:relative;width:100%;height:calc(34*var(--u));display:flex;align-items:center;justify-content:center}
.slot{width:calc(18*var(--u));height:calc(6*var(--u));border-radius:3px;background:#2c2c2e;transition:.2s}
.slot.on{background:#5ac8fa;box-shadow:0 0 10px #5ac8faaa}
.key{border:1px solid var(--line);border-radius:50%;width:calc(70*var(--u));height:calc(70*var(--u));
 background:radial-gradient(circle at 35% 25%,#1b1b1e,#030303 70%);color:var(--ink);box-shadow:0 3px 6px #000;
 display:flex;align-items:center;justify-content:center;font-size:calc(24*var(--u));padding:0;transition:transform .08s}
.key:active{transform:scale(.93);background:radial-gradient(circle at 35% 25%,#2a2a2d,#0e0e10 70%)}
.key svg{width:44%;height:44%;fill:none;stroke:var(--ink);stroke-width:2.2;stroke-linecap:round;stroke-linejoin:round}
.power{position:absolute;right:0;width:calc(34*var(--u));height:calc(34*var(--u));background:none;border:1.4px solid #3a3a3c;box-shadow:none}
#pad{position:relative;margin-top:calc(14*var(--u));width:calc(206*var(--u));height:calc(206*var(--u));border-radius:50%;
 background:radial-gradient(circle at 50% 38%,#141416,#020202 75%);border:1.2px solid #26262a;box-shadow:0 10px 18px #000;touch-action:none}
#pad i{position:absolute;width:4.5px;height:4.5px;border-radius:50%;background:#ffffff88}
#pad .u{top:7.5%;left:50%;transform:translateX(-50%)}#pad .d{bottom:7.5%;left:50%;transform:translateX(-50%)}
#pad .l{left:7.5%;top:50%;transform:translateY(-50%)}#pad .r{right:7.5%;top:50%;transform:translateY(-50%)}
#pad b{position:absolute;inset:22%;border-radius:50%;background:radial-gradient(circle at 40% 30%,#111113,#000);border:1px solid #2a2a2d;transition:background .09s;display:flex;align-items:center;justify-content:center;color:#ffffff55;font-size:12px}
#pad.press b{background:radial-gradient(circle at 40% 30%,#2c2c30,#0c0c0e)}
#pad.ptr i{display:none}
.grid{display:flex;gap:calc(26*var(--u));margin-top:calc(24*var(--u))}
.col{display:flex;flex-direction:column;gap:calc(14*var(--u))}
.rocker{width:calc(70*var(--u));height:calc(154*var(--u));border-radius:calc(35*var(--u));overflow:hidden;border:1px solid var(--line);
 background:linear-gradient(135deg,#1b1b1e,#030303);box-shadow:0 3px 6px #000;display:flex;flex-direction:column}
.rocker button{flex:1;border:0;background:none;color:var(--ink);font-size:calc(30*var(--u));font-weight:300}
.rocker button:active{background:#ffffff22}
#siri{margin-top:calc(22*var(--u));width:calc(176*var(--u));height:calc(56*var(--u));border-radius:calc(28*var(--u));padding:1.4px;border:0;
 background:conic-gradient(#3a3a3c,#5e5ce6,#3a3a3c,#2c2c2e,#3a3a3c);box-shadow:0 3px 6px #000}
#siri span{display:flex;height:100%;border-radius:inherit;align-items:center;justify-content:center;gap:8px;
 background:linear-gradient(#151517,#020202);color:var(--ink);font-size:calc(15*var(--u));font-weight:600}
#siri.on{padding:2.2px;background:conic-gradient(from var(--a,0deg),#ff2d55,#af52de,#5ac8fa,#34c759,#ff2d55);box-shadow:0 0 22px #af52de88;animation:spin 3s linear infinite}
@property --a{syntax:'<angle>';inherits:false;initial-value:0deg}
@keyframes spin{to{--a:360deg}}
.small{display:flex;justify-content:space-between;width:calc(206*var(--u));margin-top:calc(18*var(--u))}
.small .key{width:calc(42*var(--u));height:calc(42*var(--u));font-size:calc(16*var(--u))}
.small .key svg{width:48%;height:48%}
#assist{position:fixed;left:12px;right:12px;top:calc(56px + env(safe-area-inset-top));max-width:440px;margin:0 auto;padding:1.2px;border-radius:22px;
 background:linear-gradient(90deg,#ff2d55,#af52de,#5ac8fa);display:none}
#assist>div{border-radius:21px;background:#0b0b0df2;padding:12px 16px 14px}
#aq{color:#aeaeb2;font-size:14px}#aa{margin-top:6px;font-weight:600;font-size:16px;line-height:1.3}
#aa.err{color:#fbbf24}
#up{position:fixed;left:20px;right:20px;bottom:calc(12px + env(safe-area-inset-bottom));max-width:420px;margin:0 auto;padding:10px 14px;border-radius:16px;
 background:#1c1c1ef2;border:1px solid #2c2c2e;font-size:13px;display:none}
#bar{height:4px;border-radius:2px;background:#2c2c2e;margin-top:6px;overflow:hidden}#bar i{display:block;height:100%;width:0;background:#34c759}
#sheet{position:fixed;inset:0;background:#0008;display:none;align-items:flex-end}
#sheet form{width:100%;background:#111113;border-radius:24px 24px 0 0;padding:16px 16px calc(16px + env(safe-area-inset-bottom))}
#txt{width:100%;border:0;border-radius:16px;background:#1c1c1e;color:#fff;font-size:17px;padding:16px;user-select:text;-webkit-user-select:text}
.btns{display:flex;gap:10px;margin-top:12px}
.btns button{flex:1;height:50px;border:0;border-radius:16px;background:#1c1c1e;color:#fff;font-size:15px;font-weight:600}
.btns button.pri{background:#fff;color:#000}
#hint{color:#8e8e93;font-size:13px;margin:0 4px 10px}
</style></head><body><main>
<header><h1>Telefon TV</h1><span id="st">Ulanmoqda…</span></header>
<div id="now"></div>
<div id="wrap"><div class="remote">
 <div class="top"><span class="slot" id="slot"></span>
  <button class="key power" data-c="power" aria-label="Yoqish"><svg viewBox="0 0 24 24"><path d="M12 3v8M6.3 6.3a8 8 0 1 0 11.4 0"/></svg></button></div>
 <div id="pad"><i class="u"></i><i class="d"></i><i class="l"></i><i class="r"></i><b id="padc"></b></div>
 <div class="grid">
  <div class="col">
   <button class="key" data-c="back" aria-label="Orqaga"><svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg></button>
   <button class="key" data-c="playPause" aria-label="Pauza"><svg viewBox="0 0 24 24"><path d="M4 6l7 6-7 6zM15 6v12M20 6v12"/></svg></button>
   <button class="key" data-c="mute" aria-label="Ovozsiz"><svg viewBox="0 0 24 24"><path d="M4 9h4l5-4v14l-5-4H4zM16 9l5 6M21 9l-5 6"/></svg></button>
  </div>
  <div class="col">
   <button class="key" data-c="home" aria-label="Bosh ekran"><svg viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="12" rx="2"/><path d="M8 20h8"/></svg></button>
   <div class="rocker"><button data-c="volUp" aria-label="Ovoz +">+</button><button data-c="volDown" aria-label="Ovoz −">−</button></div>
  </div>
 </div>
 <button id="siri" aria-label="Yordamchi"><span><svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="#f2f2f7" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg><em id="siril" style="font-style:normal">Yordamchi</em></span></button>
 <div class="small">
  <button class="key" data-c="prev" aria-label="Oldingi"><svg viewBox="0 0 24 24"><path d="M6 5v14M19 5l-9 7 9 7z"/></svg></button>
  <button class="key" data-c="next" aria-label="Keyingi"><svg viewBox="0 0 24 24"><path d="M18 5v14M5 5l9 7-9 7z"/></svg></button>
  <label class="key" aria-label="Fayl yuborish"><svg viewBox="0 0 24 24"><path d="M12 16V4M6 10l6-6 6 6M5 20h14"/></svg><input id="fl" type="file" multiple accept="video/*,audio/*,image/*" hidden></label>
  <button class="key" id="kb" aria-label="Klaviatura"><svg viewBox="0 0 24 24"><rect x="3" y="6" width="18" height="12" rx="2"/><path d="M7 10h1M11 10h1M15 10h1M8 14h8"/></svg></button>
 </div>
</div></div>
<div id="assist"><div><div id="aq"></div><div id="aa"></div></div></div>
<div id="up"><span id="upst"></span><div id="bar"><i id="bari"></i></div></div>
<div id="sheet"><form id="f"><p id="hint">Matn yozish (qidiruv, manzil…)</p>
 <input id="txt" type="text" inputmode="text" enterkeyhint="send" autocomplete="off" placeholder="Yozing…">
 <div class="btns"><button type="button" id="space">␣ Bo‘sh joy (Space)</button></div>
 <div class="btns"><button type="button" id="ask">✨ AI’dan so‘rash</button><button class="pri" id="sendb">Yuborish</button></div></form></div>
</main><script>
const key=new URLSearchParams(location.search).get('k')||'';
const $=id=>document.getElementById(id);
const st=$('st');let ws,opened=false,pointer=false,askMode=false;
function raw(o){if(ws&&ws.readyState===1)ws.send(JSON.stringify(o))}
function connect(){
 ws=new WebSocket('ws://'+location.host+'/ws?k='+encodeURIComponent(key));
 ws.onopen=()=>{opened=true;st.textContent='Ulangan';st.className='ok'};
 ws.onclose=()=>{st.className='';st.textContent=opened?'Ulanmoqda…':'PIN noto‘g‘ri yoki TV o‘chiq';setTimeout(connect,1500)};
 ws.onmessage=e=>{let m;try{m=JSON.parse(e.data)}catch(_){return}
  if(m.t==='state'){pointer=!!m.pointer;$('pad').classList.toggle('ptr',pointer);$('padc').textContent=pointer?'sichqoncha':'';
   $('now').textContent=pointer?'Brauzer: panelni suring — kursor, bosing — tanlash':(m.title?('Ekranda: '+m.title):'')}
  if(m.t==='textFocus')openSheet(false,m.hint||'Matn',m.value||'');
  if(m.t==='assist')showAssist(m.phase,m.q,m.a)};
}
function send(c){raw({t:'cmd',c:c});if(navigator.vibrate)navigator.vibrate(8)}
document.querySelectorAll('[data-c]').forEach(b=>b.addEventListener('click',()=>send(b.dataset.c)));
/* sensorli panel */
const pad=$('pad');let sx=0,sy=0,ox=0,oy=0,moved=false,acc=[0,0],raf=0;
function flush(){raf=0;if(acc[0]||acc[1])raw({t:'move',dx:acc[0],dy:acc[1]});acc=[0,0]}
pad.addEventListener('pointerdown',e=>{sx=ox=e.clientX;sy=oy=e.clientY;moved=false;pad.setPointerCapture(e.pointerId)});
pad.addEventListener('pointermove',e=>{if(!pad.hasPointerCapture(e.pointerId))return;const dx=e.clientX-ox,dy=e.clientY-oy;
 if(pointer){acc[0]+=dx;acc[1]+=dy;ox=e.clientX;oy=e.clientY;if(Math.hypot(e.clientX-sx,e.clientY-sy)>6)moved=true;if(!raf)raf=requestAnimationFrame(flush);return}
 if(Math.abs(dx)>40||Math.abs(dy)>40){moved=true;send(Math.abs(dx)>Math.abs(dy)?(dx>0?'right':'left'):(dy>0?'down':'up'));ox=e.clientX;oy=e.clientY}});
pad.addEventListener('pointerup',e=>{if(moved)return;const r=pad.getBoundingClientRect(),cx=r.left+r.width/2,cy=r.top+r.height/2,
 dx=e.clientX-cx,dy=e.clientY-cy;pad.classList.add('press');setTimeout(()=>pad.classList.remove('press'),140);
 if(pointer||Math.hypot(dx,dy)<r.width*.28){send('ok');return}
 send(Math.abs(dx)>Math.abs(dy)?(dx>0?'right':'left'):(dy>0?'down':'up'))});
/* yordamchi */
let hideT=0;
function showAssist(phase,q,a){const box=$('assist');clearTimeout(hideT);
 if(!phase||phase==='idle'){box.style.display='none';return}
 box.style.display='block';$('aq').textContent=q||(phase==='listening'?'Gapiring…':'');
 $('aa').textContent=phase==='thinking'?'O‘ylayapman…':(a||'');$('aa').className=phase==='error'?'err':'';
 if(phase==='done'||phase==='error')hideT=setTimeout(()=>box.style.display='none',15000)}
$('assist').addEventListener('click',()=>$('assist').style.display='none');
const SR=window.SpeechRecognition||window.webkitSpeechRecognition;let rec=null;
function listening(on){$('siri').classList.toggle('on',on);$('slot').classList.toggle('on',on);$('siril').textContent=on?'Tinglayapman…':'Yordamchi'}
$('siri').addEventListener('click',()=>{
 if(rec){rec.stop();return}
 if(!SR||!window.isSecureContext){openSheet(true,'Savol yoki buyruq — klaviaturadagi 🎤 bilan gapiring','');return}
 rec=new SR();rec.lang=navigator.language&&navigator.language.startsWith('ru')?'ru-RU':'uz-UZ';rec.interimResults=true;
 let last='';rec.onresult=e=>{last=[...e.results].map(r=>r[0].transcript).join('');raw({t:'listen',phase:'partial',v:last})};
 rec.onend=()=>{listening(false);rec=null;if(last.trim())raw({t:'ask',v:last.trim()});else raw({t:'listen',phase:'cancel'})};
 rec.onerror=()=>{};listening(true);raw({t:'listen',phase:'start'});rec.start()});
/* klaviatura */
const sheet=$('sheet'),txt=$('txt');
function openSheet(ask,hint,value){askMode=ask;$('hint').textContent=hint;txt.value=value;
 $('ask').className=ask?'pri':'';$('sendb').className=ask?'':'pri';sheet.style.display='flex';setTimeout(()=>txt.focus(),50)}
function closeSheet(){sheet.style.display='none';txt.blur()}
sheet.addEventListener('click',e=>{if(e.target===sheet)closeSheet()});
$('kb').addEventListener('click',()=>openSheet(false,'Matn yozish (qidiruv, manzil…)',''));
$('space').addEventListener('click',()=>{const start=txt.selectionStart??txt.value.length,end=txt.selectionEnd??start;
 txt.setRangeText(' ',start,end,'end');txt.focus();txt.dispatchEvent(new Event('input',{bubbles:true}))});
$('ask').addEventListener('click',()=>{if(txt.value.trim())raw({t:'ask',v:txt.value.trim()});closeSheet()});
$('f').addEventListener('submit',e=>{e.preventDefault();
 if(askMode){if(txt.value.trim())raw({t:'ask',v:txt.value.trim()})}else raw({t:'text',v:txt.value});closeSheet()});
/* fayl yuborish */
const upst=$('upst'),bari=$('bari'),upbox=$('up');let upT=0;
function up(f,i,n){return new Promise(done=>{const x=new XMLHttpRequest();upbox.style.display='block';clearTimeout(upT);
 x.open('POST','/upload?k='+encodeURIComponent(key)+'&name='+encodeURIComponent(f.name)+'&index='+i+'&count='+n);
 x.upload.onprogress=e=>{if(e.lengthComputable){const p=Math.round(e.loaded/e.total*100);bari.style.width=p+'%';upst.textContent=(n>1?(i+1)+'/'+n+': ':'')+f.name+' — '+p+'%'}};
 x.onload=()=>{let m={};try{m=JSON.parse(x.responseText)}catch(_){}upst.textContent=x.status==200?'✓ '+f.name+' yuborildi':'✗ '+(m.error||('xato '+x.status));done()};
 x.onerror=()=>{upst.textContent='✗ Aloqa uzildi';done()};x.send(f)})}
$('fl').addEventListener('change',async e=>{const fs=[...e.target.files];
 for(let i=0;i<fs.length;i++){bari.style.width='0';await up(fs[i],i,fs.length)}e.target.value='';upT=setTimeout(()=>upbox.style.display='none',5000)});
connect();
</script></body></html>''';
