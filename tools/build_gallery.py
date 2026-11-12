#!/usr/bin/env python3
"""Builds the UI gallery page from the UI check's pictures and manifest (see tools/ui_overlap_check.gd: shots=<dir> manifest=<file>).

  python3 tools/build_gallery.py --pictures <dir> --manifest <file> --out <dir> --stamp <commit> --time "<date>"

The page (index.html + the pictures under img/<size>/<id>.jpg) goes into the Pages deploy only: it is never committed and is not part of the game export.
Every state has a short id, a one-line description, its group, and a badge when the checker had a warning for it; the sizes switch from the top; a tap opens a state
full screen and a swipe steps through the states in order; pictures load lazily."""
import argparse, json, os, shutil, html

SIZE_LABELS = {"320x568": "320×568", "375x667": "375×667", "390x844": "390×844", "430x932": "430×932", "768x1024": "iPad", "1280x720": "Landscape"}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pictures", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--stamp", default="dev")
    ap.add_argument("--time", default="")
    a = ap.parse_args()
    m = json.load(open(a.manifest))
    os.makedirs(os.path.join(a.out, "img"), exist_ok=True)
    states = []
    for s in m["states"]:
        have = {}
        for sz in m["sizes"]:
            src = os.path.join(a.pictures, sz["name"], s["id"] + ".jpg")
            if os.path.exists(src):
                dst_dir = os.path.join(a.out, "img", sz["name"])
                os.makedirs(dst_dir, exist_ok=True)
                shutil.copy(src, os.path.join(dst_dir, s["id"] + ".jpg"))
                have[sz["name"]] = True
        warn = {k: v for k, v in s.get("warn", {}).items() if v}
        states.append({"id": s["id"], "group": s["group"], "desc": s["desc"], "sizes": sorted(have), "warn": warn})
    sizes = [{"name": z["name"], "label": SIZE_LABELS.get(z["name"], z["name"])} for z in m["sizes"]]
    data = {"states": states, "sizes": sizes, "groups": m["groups"], "stamp": a.stamp, "time": a.time}
    page = PAGE.replace("__DATA__", json.dumps(data).replace("</", "<\\/")).replace("__STAMP__", html.escape(a.stamp)).replace("__TIME__", html.escape(a.time))
    open(os.path.join(a.out, "index.html"), "w").write(page)
    total_warn = sum(1 for s in states if s["warn"])
    print("gallery: %d states, %d sizes, %d with warnings -> %s" % (len(states), len(sizes), total_warn, a.out))

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Pattern Work UI gallery</title>
<style>
:root{--bg:#fff2dc;--card:#fffaf0;--ink:#3a2f26;--soft:#7a6a58;--edge:#e3d3b4;--accent:#e8833a;--bad:#d9402f;color-scheme:light dark}
@media (prefers-color-scheme:dark){:root{--bg:#262019;--card:#332b22;--ink:#f6ead6;--soft:#bba98f;--edge:#4a3f31}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.35 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;padding:0 16px 60px}
header{position:sticky;top:0;background:var(--bg);padding:12px 0 8px;z-index:5;border-bottom:1px solid var(--edge)}
h1{font-size:19px;margin:0 0 2px}.stamp{color:var(--soft);font-size:13px}
.sizes{display:flex;gap:6px;overflow-x:auto;padding:8px 0 2px}.sizes button{flex:0 0 auto;border:1px solid var(--edge);background:var(--card);color:var(--ink);border-radius:999px;padding:7px 13px;font:inherit;cursor:pointer}
.sizes button[aria-pressed=true]{background:var(--accent);color:#fff;border-color:var(--accent)}
nav.groups{display:flex;gap:6px;overflow-x:auto;padding:6px 0}nav.groups a{flex:0 0 auto;color:var(--soft);text-decoration:none;font-size:13px;border-bottom:2px solid transparent;padding:2px 4px}
h2{font-size:16px;margin:22px 0 8px;scroll-margin-top:130px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(170px,1fr));gap:12px}
.tile{background:var(--card);border:1px solid var(--edge);border-radius:14px;overflow:hidden;cursor:pointer;position:relative}
.tile img{display:block;width:100%;height:auto;background:var(--edge);min-height:120px}
.tile .cap{padding:7px 9px 9px}.tile code{font-size:12px;color:var(--accent);word-break:break-all}.tile .d{font-size:12.5px;color:var(--soft)}
.badge{position:absolute;top:6px;right:6px;background:var(--bad);color:#fff;border-radius:999px;font-size:12px;padding:2px 8px;font-weight:600}
#full{position:fixed;inset:0;background:rgba(20,15,10,.94);display:none;flex-direction:column;z-index:20;touch-action:pan-y}
#full.on{display:flex}#full .top{display:flex;justify-content:space-between;gap:10px;align-items:center;padding:10px 14px;color:#fff;font-size:13px}
#full .top b{font-size:14px}#full .top button{background:#fff2;border:0;color:#fff;border-radius:999px;padding:8px 14px;font:inherit}
#full .pic{flex:1;display:flex;align-items:center;justify-content:center;min-height:0;padding:0 8px}#full img{max-width:100%;max-height:100%;object-fit:contain;border-radius:10px}
#full .warn{color:#ffb4a8;font-size:12px;padding:6px 14px 14px;max-height:20vh;overflow:auto}
#full .hint{color:#fff8;text-align:center;font-size:12px;padding:0 0 10px}
</style></head><body>
<header><h1>Pattern Work &middot; UI gallery</h1><div class="stamp">Build <b>__STAMP__</b> &middot; __TIME__ &middot; <span id="count"></span></div>
<div class="sizes" id="sizes"></div><nav class="groups" id="nav"></nav></header>
<main id="main"></main>
<div id="full"><div class="top"><div><b id="fid"></b><div id="fdesc"></div></div><button id="fclose">Close</button></div><div class="pic"><img id="fimg" alt=""></div><div class="warn" id="fwarn"></div><div class="hint">Swipe left or right for the next state</div></div>
<script>
const D=__DATA__;
let size=(function(){try{return localStorage.getItem("gsize")||"390x844"}catch(e){return "390x844"}})();
if(!D.sizes.some(s=>s.name===size))size="390x844";
const main=document.getElementById("main"),sizesEl=document.getElementById("sizes"),nav=document.getElementById("nav");
document.getElementById("count").textContent=D.states.length+" states";
function src(s){return "img/"+size+"/"+s.id+".jpg"}
function tile(s,i){
  const t=document.createElement("div");t.className="tile";t.dataset.i=i;t.id="s-"+s.id;
  const w=s.warn[size]&&s.warn[size].length;
  t.innerHTML='<img loading="lazy" decoding="async" alt="'+s.id+'" src="'+src(s)+'">'+(w?'<span class="badge">'+w+' warning'+(w>1?'s':'')+'</span>':'')+'<div class="cap"><code>'+s.id+'</code><div class="d"></div></div>';
  t.querySelector(".d").textContent=s.desc;
  t.addEventListener("click",()=>openFull(i));
  return t;
}
function render(){
  main.innerHTML="";nav.innerHTML="";
  D.groups.forEach(g=>{
    const items=D.states.map((s,i)=>[s,i]).filter(x=>x[0].group===g);
    if(!items.length)return;
    const a=document.createElement("a");a.href="#g-"+g.replace(/\W+/g,"_");a.textContent=g;nav.appendChild(a);
    const h=document.createElement("h2");h.id="g-"+g.replace(/\W+/g,"_");h.textContent=g+" ("+items.length+")";main.appendChild(h);
    const grid=document.createElement("div");grid.className="grid";items.forEach(x=>grid.appendChild(tile(x[0],x[1])));main.appendChild(grid);
  });
}
D.sizes.forEach(z=>{const b=document.createElement("button");b.textContent=z.label;b.setAttribute("aria-pressed",z.name===size);b.onclick=()=>{size=z.name;try{localStorage.setItem("gsize",size)}catch(e){}[...sizesEl.children].forEach(c=>c.setAttribute("aria-pressed",c===b));render();if(cur>=0)showFull()};sizesEl.appendChild(b)});
let cur=-1;const full=document.getElementById("full");
function showFull(){const s=D.states[cur];document.getElementById("fid").textContent=s.id;document.getElementById("fdesc").textContent=s.desc+" · "+size+" · "+(cur+1)+"/"+D.states.length;
  document.getElementById("fimg").src=src(s);const w=s.warn[size]||[];document.getElementById("fwarn").textContent=w.length?"Checker: "+w.join(" | "):"";history.replaceState(null,"","#"+s.id)}
function openFull(i){cur=i;full.classList.add("on");showFull()}
function step(d){cur=(cur+d+D.states.length)%D.states.length;showFull()}
document.getElementById("fclose").onclick=()=>{full.classList.remove("on");cur=-1;history.replaceState(null,"","#")};
let x0=null;full.addEventListener("touchstart",e=>{x0=e.touches[0].clientX},{passive:true});
full.addEventListener("touchend",e=>{if(x0===null)return;const dx=e.changedTouches[0].clientX-x0;x0=null;if(Math.abs(dx)>50)step(dx<0?1:-1)});
document.addEventListener("keydown",e=>{if(cur<0)return;if(e.key==="ArrowRight")step(1);else if(e.key==="ArrowLeft")step(-1);else if(e.key==="Escape")document.getElementById("fclose").click()});
render();
const h=location.hash.slice(1);if(h){const i=D.states.findIndex(s=>s.id===h);if(i>=0)openFull(i)}
</script></body></html>
"""

if __name__ == "__main__":
    main()
