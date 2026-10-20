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
source = core.read_text().replace('seg.userData.fileId=f.id;',
    'seg.userData.fileId=f.id; seg.userData.methodIndex=f.segMats.length;')
needle = 'return { destroy, pause, resume, getScene:'
assert needle in source
source = source.replace(needle, '''function focusNode(id) {
    if (!nodeById[id]) return false;
    focusApi.lockTarget(id);
    return true;
  }
  function focusSection(id, index) {
    const file = nodeById[id];
    if (!file || !Number.isInteger(index) || !file.methods?.[index]) return false;
    focusApi.enterElevation(id);
    focusApi.selectMethod(index);
    return true;
  }
  function stopCameraFlight() {
    tween = null;
    controls.enabled = true;
  }
  return { getControls: () => controls, focusNode, focusSection, stopCameraFlight, destroy, pause, resume, getScene:''')
core.write_text(source)
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
source = source.replace('`METHODS ${f.methods.length}`', 'f.symbolsUnavailable?`METHODS n/a`:`METHODS ${f.reportedSectionCount??f.methods.length}`')
source = source.replace('gauge(4,n,11.4, ah,                                    healthColor(ah).getHex(), `HEALTH ${Math.round(ah*100)}%`);',
                        'gauge(4,n,11.4, f.unknownHealth?0:ah, f.unknownHealth?COL.doc:healthColor(ah).getHex(), f.unknownHealth?`HEALTH n/a`:`HEALTH ${Math.round(ah*100)}%`);')
source = source.replace("$('#d-loc').textContent=f.loc; $('#d-meth').textContent=f.methods.length;",
                        "$('#d-loc').textContent=f.loc==null?'—':f.loc; $('#d-meth').textContent=f.symbolsUnavailable?'—':(f.reportedSectionCount??f.methods.length);")
source = source.replace("hb.style.width=Math.round(ah*100)+'%';\n    hb.style.background", "hb.style.width=f.unknownHealth?'0%':Math.round(ah*100)+'%';\n    hb.style.background")
old = "$('#d-health').textContent='●'.repeat(pips)+'○'.repeat(5-pips);"
new = "$('#d-health').textContent=(f.isExternal&&!(f.items||[]).length)||f.methods?.every(m=>m.health==null)?'—':'●'.repeat(pips)+'○'.repeat(5-pips);"
assert old in source
focus.write_text(source.replace(old, new))
source = focus.read_text()
needle = 'focusId=id; const f=nodeById[id];'
assert needle in source
source = source.replace(needle, needle + "\n    opts.onFileSelect?.({id:f.id});")
focus.write_text(source)
elevation = root / "cb-elevation.js"
source = elevation.read_text()
old = 'el.innerHTML=`<b style="color:#${it.hc}">${it.nm}</b>${it.sub?` ${it.sub}`:\'\'}`;'
assert old in source
new = "const name=document.createElement('b'); name.style.color='#'+it.hc; name.textContent=it.nm; el.append(name, document.createTextNode(it.sub?' '+it.sub:''));"
elevation.write_text(source.replace(old, new))
source = elevation.read_text()
source = source.replace("hc:(m.dead?'ff1b4d':healthColor(m.health).getHexString())",
    "hc:(m.dead?'ff1b4d':m.health==null?new THREE.Color(COL.doc).getHexString():healthColor(m.health).getHexString())")
source = source.replace("${m.loc} loc &middot; ${Math.round((m.health||0)*100)}%",
    "${m.kind||'section'} · L${m.line??'—'} · ${m.loc} LOC${m.health==null?'':' · '+Math.round(m.health*100)+'%'}")
elevation.write_text(source)
needle = 'path:f._path, fileId:f._fileId||null, file:f.name, name:m.name'
assert needle in source
elevation.write_text(source.replace(needle,
    'id:f.id, repositoryId:f.repositoryId, symbolId:m.id, path:f._path, fileId:f._fileId||null, file:f.name, name:m.name'))
interaction = root / "cb-input.js"
source = interaction.read_text()
needle = 'if (ph.length) { focusApi.lockTarget(ph[0].object.userData.fileId); return; }'
assert needle in source
source = source.replace(needle, '''if (ph.length) {
      const hit = ph[0].object.userData;
      focusApi.lockTarget(hit.fileId);
      if (Number.isInteger(hit.methodIndex)) {
        focusApi.enterElevation(hit.fileId);
        focusApi.selectMethod(hit.methodIndex);
      }
      return;
    }''')
interaction.write_text(source)
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
template.write_text(source.replace("DEAD · NO INBOUND", "NO INBOUND LINKS"))
PY

mkdir -p "$generated/three/addons/controls" "$generated/three/addons/renderers"
bun build "$scratch/cyberboard/cb-core.js" --target browser --external three \
  --external 'three/*' --outfile "$generated/cb-core.js" >/dev/null
python3 - "$generated/cb-core.js" <<'PY'
from pathlib import Path
import re, sys
path = Path(sys.argv[1])
path.write_text(re.sub(r'^// .*?/cyberboard/([^/\n]+)$', r'// Repo Lens cyberboard/\1',
                       path.read_text(), flags=re.MULTILINE))
PY
cp "$source_root/vendor/three/three.module.js" "$generated/three/three.module.js"
python3 - "$generated/three/three.module.js" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_bytes(path.read_bytes().replace(b' \t', b'\t'))
PY
cp "$source_root/vendor/three/addons/controls/OrbitControls.js" "$generated/three/addons/controls/OrbitControls.js"
cp "$source_root/vendor/three/addons/renderers/CSS2DRenderer.js" "$generated/three/addons/renderers/CSS2DRenderer.js"
cp "$source_root/styles/features/cyberboard/scene.css" "$generated/scene.css"
git -C "$repo_lens" rev-parse HEAD > "$web_root/REPO_LENS_COMMIT"
bash "$web_root/bundle-viewer.sh"
