/// Saytlarda pult bilan odatiy tanlash (televizordagidek): ↑↓←→ — keyingi
/// havola yoki tugma ajratiladi, OK — bosiladi. Sichqoncha kursori yo‘q.
///
/// Skript har chaqiruvda qo‘shiladi (sahifa almashsa ham ishlayveradi) va
/// `window.__z3nav` ni bir marta yaratadi:
/// * `move('up'|'down'|'left'|'right')` → `moved` | `scrolled` | `top` | `none`
///   (`top` — sahifa eng tepada, yuqorida tanlanadigan narsa yo‘q).
/// * `ok(native)` → `input:<matn>` | `click:<fx>,<fy>` (native — bosishni
///   ilova o‘zi yuboradi) | `done` | `moved` | `none`.
library;

const _navScript = r'''
(function(){
if(window.__z3nav&&window.__z3nav.v===2)return;
var SEL='a[href],button,input:not([type=hidden]),select,textarea,summary,video,iframe,'+
 '[role=button],[role=link],[role=tab],[role=menuitem],[role=option],[role=checkbox],[role=radio],[role=switch],'+
 '[onclick],[tabindex]:not([tabindex="-1"]),[contenteditable="true"],[contenteditable=""]';
var OUTER='a[href],button,[role=button],[role=link],[role=tab],[role=menuitem],[role=option],summary';
var SKIP={submit:1,button:1,checkbox:1,radio:1,range:1,file:1,image:1,reset:1,color:1};
var cur=null;
function css(){
 if(document.getElementById('__z3nav_css'))return;
 var s=document.createElement('style');s.id='__z3nav_css';
 s.textContent='.__z3f{outline:4px solid #5AC8FA!important;outline-offset:-2px!important;'+
  'box-shadow:0 0 0 2px rgba(0,0,0,.6),0 0 24px rgba(90,200,250,.7)!important}';
 (document.head||document.documentElement).appendChild(s);
}
function textOf(e){
 var t=e.closest('input,textarea,[contenteditable="true"],[contenteditable=""]');
 if(!t||(t.tagName==='INPUT'&&SKIP[t.type]))return null;
 return t;
}
function scrollsX(e){
 for(var p=e.parentElement,i=0;p&&i<12;p=p.parentElement,i++){
  if(p.scrollWidth>p.clientWidth+2){var o=getComputedStyle(p).overflowX;if(o==='auto'||o==='scroll')return true}
 }
 return document.documentElement.scrollWidth>innerWidth+2;
}
function rectOf(e){
 var r=e.getBoundingClientRect(),W=innerWidth,H=innerHeight;
 if(r.width<3||r.height<3)return null;
 if(r.bottom<-3*H||r.top>4*H)return null;
 // Butun sahifani o‘rab olgan konteyner (tabindex / onclick) tanlanmaydi.
 if(r.width*r.height>W*H*0.45&&!e.matches('a[href],button,video,iframe,input,textarea,select'))return null;
 if(!(r.right>0&&r.left<W)&&!scrollsX(e))return null;
 if(e.disabled)return null;
 var cs=getComputedStyle(e);
 if(cs.visibility==='hidden'||cs.pointerEvents==='none'||parseFloat(cs.opacity)<0.05)return null;
 return r;
}
// Element o‘zini o‘rab turgan (overflow) konteyner chegarasidan butunlay
// tashqarida bo‘lsa (masalan, karuselning ko‘rinmayotgan qismi) — o‘sha
// konteyner; [partial] — qisman kesilgan bo‘lsa ham.
function clipBox(e,r,partial,cache){
 for(var p=e.parentElement;p&&p!==document.body&&p!==document.documentElement;p=p.parentElement){
  var c=cache&&cache.get(p);
  if(!c){
   var cs=getComputedStyle(p),clip=cs.overflowX!=='visible'||cs.overflowY!=='visible';
   c={clip:clip,r:clip?p.getBoundingClientRect():null};
   if(cache)cache.set(p,c);
  }
  if(!c.clip)continue;
  var b=c.r,out=r.right<=b.left+1||r.left>=b.right-1||r.bottom<=b.top+1||r.top>=b.bottom-1;
  if(out||(partial&&(r.left<b.left-1||r.right>b.right+1||r.top<b.top-1||r.bottom>b.bottom+1)))return p;
 }
 return null;
}
function list(){
 var all=document.querySelectorAll(SEL),out=[],cache=new Map();
 for(var i=0;i<all.length&&out.length<1500;i++){
  var e=all[i],p=e.parentElement&&e.parentElement.closest(OUTER);
  if(p)continue; // ichma-ich: tashqisi (masalan, butun karta) tanlanadi
  var r=rectOf(e);if(r)out.push({e:e,r:r,box:clipBox(e,r,false,cache)});
 }
 return out;
}
function scroller(e){
 for(var p=e;p&&p!==document.body&&p!==document.documentElement;p=p.parentElement){
  if(p.scrollHeight>p.clientHeight+2){var o=getComputedStyle(p).overflowY;if(o==='auto'||o==='scroll')return p}
 }
 return document.scrollingElement||document.documentElement;
}
function scroll(dir,from){
 var W=innerWidth,H=innerHeight;
 var s=scroller(from||document.elementFromPoint(W/2,H/2)||document.body);
 if(dir==='up'&&s.scrollTop<=0)return 'top';
 if(dir==='down'&&s.scrollTop+s.clientHeight>=s.scrollHeight-2)return 'none';
 if((dir==='left'||dir==='right')&&s.scrollWidth<=s.clientWidth+2)return 'none';
 var dy=dir==='down'?H*0.6:dir==='up'?-H*0.6:0,dx=dir==='right'?W*0.5:dir==='left'?-W*0.5:0;
 s.scrollBy({top:dy,left:dx,behavior:'smooth'});
 return 'scrolled';
}
function set(e){
 if(cur&&cur!==e){
  cur.classList.remove('__z3f');
  try{cur.dispatchEvent(new MouseEvent('mouseout',{bubbles:true}))}catch(_){}
 }
 cur=e;e.classList.add('__z3f');
 try{e.dispatchEvent(new MouseEvent('mouseover',{bubbles:true}))}catch(_){}
 // Matn maydoni faqat OK bilan ochiladi (klaviatura o‘zi chiqib qolmasin).
 if(!textOf(e)){try{e.focus({preventScroll:true})}catch(_){}}
 var r=e.getBoundingClientRect(),W=innerWidth,H=innerHeight,m=Math.min(110,H*0.15);
 if(r.top<m||r.bottom>H-m||r.left<0||r.right>W||clipBox(e,r,true,null)){
  e.scrollIntoView({block:r.height>H-2*m?'start':'center',inline:'nearest',behavior:'smooth'});
 }
}
function pick(from,dir,items){
 var fx=(from.left+from.right)/2,fy=(from.top+from.bottom)/2,best=null,bs=Infinity;
 for(var pass=0;pass<2&&!best;pass++){
  for(var i=0;i<items.length;i++){
   var c=items[i],r=c.r;
   if(cur&&(c.e===cur||c.e.contains(cur)||cur.contains(c.e)))continue;
   // Karusel ichidagi yashirin qism — faqat o‘sha karusel ichidan yuriladi.
   if(c.box&&!(cur&&c.box.contains(cur)))continue;
   var cx=(r.left+r.right)/2,cy=(r.top+r.bottom)/2,major,ov,off;
   if(dir==='down'){
    if(pass?cy<=fy+2:r.top<from.bottom-4)continue;
    major=Math.max(0,r.top-from.bottom);ov=Math.min(r.right,from.right)-Math.max(r.left,from.left);off=Math.abs(cx-fx);
   }else if(dir==='up'){
    if(pass?cy>=fy-2:r.bottom>from.top+4)continue;
    major=Math.max(0,from.top-r.bottom);ov=Math.min(r.right,from.right)-Math.max(r.left,from.left);off=Math.abs(cx-fx);
   }else if(dir==='right'){
    if(pass?cx<=fx+2:r.left<from.right-4)continue;
    major=Math.max(0,r.left-from.right);ov=Math.min(r.bottom,from.bottom)-Math.max(r.top,from.top);off=Math.abs(cy-fy);
   }else{
    if(pass?cx>=fx-2:r.right>from.left+4)continue;
    major=Math.max(0,from.left-r.right);ov=Math.min(r.bottom,from.bottom)-Math.max(r.top,from.top);off=Math.abs(cy-fy);
   }
   var s=major+(ov>0?0:-ov*3+40)+off*0.2;
   if(s<bs){bs=s;best=c}
  }
 }
 return best;
}
function visible(r){return r.bottom>0&&r.top<innerHeight&&r.right>0&&r.left<innerWidth}
function move(dir){
 css();
 var H=innerHeight,items=list();
 if(cur&&(!document.contains(cur)||!cur.getClientRects().length)){cur.classList.remove('__z3f');cur=null}
 var from=cur&&cur.getBoundingClientRect();
 if(!from||!visible(from)){
  // Hali hech narsa tanlanmagan yoki tanlangani ekrandan chiqib ketgan:
  // ekrandagi birinchi (yuqoriga bosilganda — eng pastki) narsa.
  var shown=items.filter(function(x){return !x.box&&x.r.bottom>8&&x.r.top<H-8&&x.r.right>0&&x.r.left<innerWidth});
  if(shown.length){
   shown.sort(function(a,b){
    return dir==='up'?(b.r.bottom-a.r.bottom)||(a.r.left-b.r.left):(a.r.top-b.r.top)||(a.r.left-b.r.left);
   });
   set(shown[0].e);return 'moved';
  }
  return scroll(dir,cur);
 }
 var b=pick(from,dir,items);
 if(b){
  // Keyingi narsa juda uzoqda (uzun matn) — sakramasdan sahifani suramiz.
  var far=dir==='down'?b.r.top-H:dir==='up'?-b.r.bottom:0;
  if(far>H*0.25){var sc=scroll(dir,cur);if(sc==='scrolled')return sc}
  set(b.e);return 'moved';
 }
 return scroll(dir,cur);
}
function ok(native){
 css();
 var e=cur;
 if(!e||!document.contains(e))return move('down')==='moved'?'moved':'none';
 var r=e.getBoundingClientRect(),W=innerWidth,H=innerHeight;
 if(!visible(r)){set(e);return 'moved'}
 var t=textOf(e);
 if(t){t.focus();return 'input:'+(t.value!==undefined?t.value:(t.innerText||''))}
 if(e.tagName==='VIDEO'){if(e.paused)e.play();else e.pause();return 'done'}
 var x=Math.max(1,Math.min(W-1,(Math.max(r.left,0)+Math.min(r.right,W))/2)),
     y=Math.max(1,Math.min(H-1,(Math.max(r.top,0)+Math.min(r.bottom,H))/2));
 if(native)return 'click:'+(x/W)+','+(y/H);
 ['pointerdown','mousedown','pointerup','mouseup'].forEach(function(n){
  try{e.dispatchEvent(new MouseEvent(n,{bubbles:true,cancelable:true,clientX:x,clientY:y,view:window}))}catch(_){}
 });
 e.click();
 return 'done';
}
window.__z3nav={v:2,move:move,ok:ok};
})();
''';

/// ↑↓←→ — keyingi havola/tugmani tanlash.
String webNavMove(String dir) => "${_navScript}window.__z3nav.move('$dir')";

/// OK — tanlanganini bosish. [native] — bosishni ilova o‘zi yuboradi
/// (Linux: haqiqiy sichqoncha bosishi, video pleyer va iframe ichida ham).
String webNavOk({required bool native}) =>
    '${_navScript}window.__z3nav.ok($native)';

/// Klaviatura tugmasi sahifaga (YouTube TV): tizim tugma yubora olmaydigan
/// joyda (Android, iPhone) JavaScript orqali.
String webKeyScript(String key) {
  final (name, code) = switch (key) {
    'up' => ('ArrowUp', 38),
    'down' => ('ArrowDown', 40),
    'left' => ('ArrowLeft', 37),
    'right' => ('ArrowRight', 39),
    'enter' => ('Enter', 13),
    'escape' => ('Escape', 27),
    'space' => (' ', 32),
    _ => ('', 0),
  };
  if (code == 0) return '';
  return '''
(function(){
var t=document.activeElement||document.body||document.documentElement;
['keydown','keyup'].forEach(function(n){
 var e=new KeyboardEvent(n,{key:'$name',code:'${name == ' ' ? 'Space' : name}',bubbles:true,cancelable:true});
 try{Object.defineProperty(e,'keyCode',{get:function(){return $code}});
  Object.defineProperty(e,'which',{get:function(){return $code}});}catch(_){}
 t.dispatchEvent(e);
});
})()''';
}
