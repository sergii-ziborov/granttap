#!/usr/bin/env bash
set -euo pipefail

web_root="$(cd "$(dirname "$0")" && pwd)"
generated="$web_root/build"
repo_lens="${REPO_LENS_ROOT:-$(cd "$web_root/../../../../repo-lens" && pwd)}"
source_root="$repo_lens/renderer"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

cp -R "$source_root/js/cyberboard" "$scratch/cyberboard"
# Unknown health is not a failing score. Keep the Repo Lens scene but paint
# evidence-free segments neutrally and show an unknown dossier value.
python3 - "$scratch/cyberboard" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
core = root / "cb-core.js"
source = core.read_text()
source = source.replace("d.innerHTML=text;", "d.textContent=text;")
old = "dead?new THREE.Color(0xff1b4d):healthColor(meth.health)"
new = "dead?new THREE.Color(0xff1b4d):meth.health==null?new THREE.Color(COL.doc):healthColor(meth.health)"
assert old in source
core.write_text(source.replace(old, new))
focus = root / "cb-focus.js"
source = focus.read_text()
source = source.replace("lab.innerHTML=labelTxt;", "lab.textContent=labelTxt;")
source = source.replace("d.innerHTML=`<i>${i+1}</i> ${n.name}`;",
                        "const marker=document.createElement('i'); marker.textContent=String(i+1); d.append(marker, document.createTextNode(' '+n.name));")
source = source.replace('gauge(4,n,11.4, ah,                      healthColor(ah).getHex(), `HEALTH ${Math.round(ah*100)}%`);',
                        'gauge(4,n,11.4, it.length?ah:0, it.length?healthColor(ah).getHex():COL.doc, it.length?`HEALTH ${Math.round(ah*100)}%`:`HEALTH n/a`);')
source = source.replace("$('#d-loc').textContent=it.reduce((s,t)=>s+t.val,0); $('#d-meth').textContent=it.length;",
                        "$('#d-loc').textContent=it.length?it.reduce((s,t)=>s+t.val,0):'—'; $('#d-meth').textContent=it.length||'—';")
source = source.replace("const hb=$('#d-healthbar'); hb.style.width=Math.round(ah*100)+'%'; hb.style.background=",
                        "const hb=$('#d-healthbar'); hb.style.width=it.length?Math.round(ah*100)+'%':'0%'; hb.style.background=", 1)
source = source.replace('const ah=avgHealth(f);', 'const ah=f.unknownHealth?0.5:avgHealth(f);')
source = source.replace('`LOC ${f.loc}`', 'f.loc==null?`LOC n/a`:`LOC ${f.loc}`')
source = source.replace('`METHODS ${f.methods.length}`', 'f.symbolsUnavailable?`METHODS n/a`:`METHODS ${f.methods.length}`')
source = source.replace('gauge(4,n,11.4, ah,                                    healthColor(ah).getHex(), `HEALTH ${Math.round(ah*100)}%`);',
                        'gauge(4,n,11.4, f.unknownHealth?0:ah, f.unknownHealth?COL.doc:healthColor(ah).getHex(), f.unknownHealth?`HEALTH n/a`:`HEALTH ${Math.round(ah*100)}%`);')
source = source.replace("$('#d-loc').textContent=f.loc; $('#d-meth').textContent=f.methods.length;",
                        "$('#d-loc').textContent=f.loc==null?'—':f.loc; $('#d-meth').textContent=f.symbolsUnavailable?'—':f.methods.length;")
source = source.replace("hb.style.width=Math.round(ah*100)+'%';\n    hb.style.background", "hb.style.width=f.unknownHealth?'0%':Math.round(ah*100)+'%';\n    hb.style.background")
old = "$('#d-health').textContent='●'.repeat(pips)+'○'.repeat(5-pips);"
new = "$('#d-health').textContent=(f.isExternal&&!(f.items||[]).length)||f.methods?.every(m=>m.health==null)?'—':'●'.repeat(pips)+'○'.repeat(5-pips);"
assert old in source
focus.write_text(source.replace(old, new))
elevation = root / "cb-elevation.js"
source = elevation.read_text()
old = 'el.innerHTML=`<b style="color:#${it.hc}">${it.nm}</b>${it.sub?` ${it.sub}`:\'\'}`;'
assert old in source
new = "const name=document.createElement('b'); name.style.color='#'+it.hc; name.textContent=it.nm; el.append(name, document.createTextNode(it.sub?' '+it.sub:''));"
elevation.write_text(source.replace(old, new))
palette = root / "cb-palette.js"
source = palette.read_text()
old = "import: COL.edgeImport, call: COL.edgeCall"
assert old in source
palette.write_text(source.replace(old, "import: COL.edgeImport, relation: COL.edgeImport, call: COL.edgeCall"))
template = root / "cb-template.js"
source = template.read_text()
needle = '<button type="button" class="row edge-toggle on" data-edge-type="io">'
assert needle in source
source = source.replace(needle, '<button type="button" class="row edge-toggle on" data-edge-type="relation"><span class="sw" style="color:var(--violet);background:var(--violet)"></span> OTHER RELATION</button>\\n    ' + needle)
template.write_text(source)
PY

mkdir -p "$generated/three/addons/controls" "$generated/three/addons/renderers"
bun build "$scratch/cyberboard/cb-core.js" --target browser --external three \
  --external 'three/*' --outfile "$generated/cb-core.js" >/dev/null
cp "$source_root/vendor/three/three.module.js" "$generated/three/three.module.js"
cp "$source_root/vendor/three/addons/controls/OrbitControls.js" "$generated/three/addons/controls/OrbitControls.js"
cp "$source_root/vendor/three/addons/renderers/CSS2DRenderer.js" "$generated/three/addons/renderers/CSS2DRenderer.js"
cp "$source_root/styles/features/cyberboard/scene.css" "$generated/scene.css"
git -C "$repo_lens" rev-parse HEAD > "$web_root/REPO_LENS_COMMIT"
