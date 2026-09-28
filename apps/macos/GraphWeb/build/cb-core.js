// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-core.js
import * as THREE2 from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";
import { CSS2DRenderer, CSS2DObject as CSS2DObject3 } from "three/addons/renderers/CSS2DRenderer.js";

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-geometry.js
import * as THREE from "three";
var colorLuma = (hex) => {
  const c = new THREE.Color(hex);
  return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
};
function simplifyPath(p) {
  if (p.length < 3)
    return p;
  const out = [p[0]];
  for (let i = 1;i < p.length - 1; i++) {
    const a = out[out.length - 1], b = p[i], c = p[i + 1];
    if (Math.abs((b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)) < 0.001)
      continue;
    out.push(b);
  }
  out.push(p[p.length - 1]);
  return out;
}
function ribbonVerts(pts, hw) {
  const L = pts.length;
  if (L < 2)
    return [];
  const dir = (a, b) => {
    const dx = b.x - a.x, dz = b.z - a.z, l = Math.hypot(dx, dz) || 1;
    return [dx / l, dz / l];
  };
  const left = [], right = [];
  for (let i = 0;i < L; i++) {
    let nx, nz, ml;
    if (i === 0) {
      const [dx, dz] = dir(pts[0], pts[1]);
      nx = -dz;
      nz = dx;
      ml = hw;
    } else if (i === L - 1) {
      const [dx, dz] = dir(pts[L - 2], pts[L - 1]);
      nx = -dz;
      nz = dx;
      ml = hw;
    } else {
      const [a0, b0] = dir(pts[i - 1], pts[i]), [a1, b1] = dir(pts[i], pts[i + 1]);
      const n0x = -b0, n0z = a0, n1x = -b1, n1z = a1;
      let mx = n0x + n1x, mz = n0z + n1z;
      const ln = Math.hypot(mx, mz) || 1;
      mx /= ln;
      mz /= ln;
      ml = hw / Math.max(0.45, Math.abs(mx * n0x + mz * n0z));
      nx = mx;
      nz = mz;
    }
    left.push([pts[i].x + nx * ml, pts[i].y, pts[i].z + nz * ml]);
    right.push([pts[i].x - nx * ml, pts[i].y, pts[i].z - nz * ml]);
  }
  const v = [];
  for (let i = 0;i < L - 1; i++) {
    const lA = left[i], rA = right[i], lB = left[i + 1], rB = right[i + 1];
    v.push(lA[0], lA[1], lA[2], rA[0], rA[1], rA[2], lB[0], lB[1], lB[2], rA[0], rA[1], rA[2], rB[0], rB[1], rB[2], lB[0], lB[1], lB[2]);
  }
  return v;
}
function ribbonGeo(pts, hw) {
  const g = new THREE.BufferGeometry;
  g.setAttribute("position", new THREE.Float32BufferAttribute(ribbonVerts(pts, hw), 3));
  return g;
}
function multiRibbonGeo(paths, hw) {
  const v = [];
  paths.forEach((pts) => v.push(...ribbonVerts(pts, hw)));
  const g = new THREE.BufferGeometry;
  g.setAttribute("position", new THREE.Float32BufferAttribute(v, 3));
  return g;
}
function arclen(pts) {
  let len = 0;
  const cum = [0];
  for (let k = 1;k < pts.length; k++) {
    len += pts[k].distanceTo(pts[k - 1]);
    cum.push(len);
  }
  return { cum, len };
}
function overlapLen(a, b, c, d) {
  return Math.max(0, Math.min(b, d) - Math.max(a, c));
}
function findRoot(parent, i) {
  while (parent[i] !== i) {
    parent[i] = parent[parent[i]];
    i = parent[i];
  }
  return i;
}
function unionRoot(parent, a, b) {
  a = findRoot(parent, a);
  b = findRoot(parent, b);
  if (a !== b)
    parent[b] = a;
}
function distSqPointSeg2(px, py, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy;
  const t = l2 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0, x = ax + dx * t, y = ay + dy * t;
  return (px - x) * (px - x) + (py - y) * (py - y);
}
function nodeLooksEntry(n) {
  if (!n)
    return false;
  const name = String(n.name || "").toLowerCase(), mod = String(n.module || "").toLowerCase(), path = String(n._path || name).toLowerCase();
  return !!n.isEndpoint || mod === "(root)" || /(^|[\\/])(index|main|server|app|cli|cmd|bootstrap|entry|run|__main__|manage|wsgi|asgi)\.[a-z0-9]+$|(^|[\\/])(bin|cmd)[\\/]/i.test(path);
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-template.js
var CYBERBOARD_TEMPLATE = `<div class="cb-root">
  <div class="cb-app"></div>

  <div class="vignette"></div>
  <div class="scan"></div>
  <div class="frame"><i class="tl"></i><i class="tr"></i><i class="bl"></i><i class="br"></i></div>

  <div class="hud views">
    <button data-view="top">TOP</button>
    <button data-view="iso">ISO</button>
    <button data-view="reset" data-rel-recompute>RESET</button>
  </div>

  <div class="hud elev-scroll" id="elev-scroll" role="scrollbar" aria-hidden="true" aria-label="Method window" aria-orientation="vertical" aria-valuemin="0" aria-valuemax="0" aria-valuenow="0" title="Drag to scroll the open method tower">
    <div class="elev-scroll-track"><i id="elev-scroll-thumb"></i></div>
  </div>

  <div class="hud dossier panel" id="dossier">
    <div class="tag">&#9608; TARGET LOCKED</div>
    <div class="name" id="d-name">&mdash;</div>
    <div class="mod" id="d-mod">&mdash;</div>
    <div class="grid">
      <div><span>LOC</span><b id="d-loc">0</b></div>
      <div><span>METHODS</span><b id="d-meth">0</b></div>
      <div><span>FAN-IN</span><b id="d-fin">0</b></div>
      <div><span>FAN-OUT</span><b id="d-fout">0</b></div>
      <div><span>COVERAGE</span><b id="d-cov">0%</b></div>
      <div><span>HEALTH</span><b id="d-health">&mdash;</b></div>
    </div>
    <div class="hbar"><i id="d-healthbar"></i></div>
  </div>

  <div class="hud legend panel" id="cb-legend">
    <button type="button" class="cb-legend-toggle" data-cb-legend>LEGEND<span class="cb-caret">▾</span></button>
    <div class="cb-legend-body">
    <h4>EDGE TYPE <span class="cb-legend-hint">click to toggle</span></h4>
    <button type="button" class="row edge-toggle on" data-edge-type="inherit"><span class="sw" style="color:var(--cyan);background:var(--cyan)"></span> INHERIT</button>
    <button type="button" class="row edge-toggle on" data-edge-type="import"><span class="sw" style="color:var(--violet);background:var(--violet)"></span> IMPORT</button>
    <button type="button" class="row edge-toggle on" data-edge-type="call"><span class="sw" style="color:var(--amber);background:var(--amber)"></span> CALL</button>
    <button type="button" class="row edge-toggle on" data-edge-type="relation"><span class="sw" style="color:var(--violet);background:var(--violet)"></span> OTHER RELATION</button>
    <button type="button" class="row edge-toggle on" data-edge-type="io"><span class="sw" style="color:var(--cb-edge-io,#59d0a0);background:var(--cb-edge-io,#59d0a0)"></span> I/O · DB/CACHE/CLOUD</button>
    <button type="button" class="row edge-toggle on" data-edge-type="local"><span class="sw" style="color:var(--cb-edge-local,#ff6ec7);background:var(--cb-edge-local,#ff6ec7)"></span> IN-FOLDER · INTRA-MODULE</button>
    <h4>FLOW PACKET</h4>
    <div class="row"><span class="dot" style="color:var(--cb-packet-read,#6fe3ff)"></span> READ · REST · REQUEST</div>
    <div class="row"><span class="dot" style="color:var(--cb-packet-write,#4dff88)"></span> WRITE · CREATE · UPDATE</div>
    <div class="row"><span class="dot" style="color:var(--cb-packet-delete,#ff5470)"></span> DELETE</div>
    <div class="row"><span class="dot" style="color:var(--cb-packet-response,#ffc24a)"></span> RESPONSE BACK</div>
    <h4>PILLAR RING <span class="cb-legend-hint">click to toggle</span></h4>
    <button type="button" class="row marker-toggle on" data-marker-type="entry"><span class="dot" style="color:var(--good)"></span> ENTRY POINT</button>
    <button type="button" class="row marker-toggle on" data-marker-type="dead"><span class="dot" style="color:var(--bad)"></span> DEAD &middot; NO INBOUND</button>
    <h4>DOCS <span class="cb-legend-hint">click to toggle</span></h4>
    <button type="button" class="row docs-toggle" data-cb-docs><span class="dot" style="color:var(--cb-agent,#c38bff)"></span> DOCS &middot; AGENT</button>
    <h4>TRACE GAP</h4>
    <div class="ctl"><input id="gap" type="range" min="0.2" max="4" step="0.1" value="1.0"><span class="val" id="gapv">1.0</span></div>
    <div class="hint">daylight between adjacent traces</div>
    <button type="button" class="row merge-toggle" data-trace-merge><span class="sw merge-sw"></span> MERGE PARALLEL</button>
    </div>
  </div>

  <div class="hud help">
    <div><kbd>DRAG</kbd> orbit / tilt</div>
    <div><kbd>SCROLL</kbd> zoom</div>
    <div><kbd>CLICK</kbd> lock target</div>
    <div><kbd>CLICK LINE</kbd> trace call path</div>
    <div><kbd>DBL-CLICK</kbd> elevation (methods)</div>
    <div><kbd>ESC</kbd> / empty click = release</div>
  </div>

  <div class="boot" id="boot">INITIALIZING&nbsp;DATASCAPE&hellip;</div>
</div>`;

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-demo-data.js
function buildDemoData({ HEIGHT_PER_LOC, SEG_GAP, FILE_SPACING, TILE_SPACING, MOD_COLS, KCFG, showDocs }) {
  function mulberry32(a) {
    return function() {
      a |= 0;
      a = a + 1831565813 | 0;
      let t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  const rng = mulberry32(20260624);
  const ri = (a, b) => Math.floor(a + rng() * (b - a + 1));
  const pick = (arr) => arr[Math.floor(rng() * arr.length)];
  const MODULES = [
    { name: "src/widget", n: 7 },
    { name: "src/query", n: 6 },
    { name: "src/dashboard", n: 4 },
    { name: "src/shared", n: 5 },
    { name: "src/internal", n: 3 },
    { name: "src/clients", n: 4 }
  ];
  const PRE = ["user", "graph", "node", "edge", "query", "repo", "auth", "sync", "data", "meta", "flow", "task", "event", "config", "render", "layout", "schema", "token"];
  const NOUN = ["Service", "Store", "Model", "View", "Adapter", "Engine", "Parser", "Router", "Cache", "Mapper", "Worker", "Client", "Manager", "Registry", "Builder", "Handler"];
  const VERB = ["init", "load", "parse", "render", "update", "fetch", "sync", "build", "handle", "validate", "map", "dispose", "resolve", "commit", "emit", "query"];
  const files = [];
  let fid = 0;
  MODULES.forEach((mod, mi) => {
    const col = mi % MOD_COLS, row = Math.floor(mi / MOD_COLS);
    const cx = (col - (MOD_COLS - 1) / 2) * TILE_SPACING;
    const cz = (row - 0.5) * TILE_SPACING;
    const g = Math.ceil(Math.sqrt(mod.n));
    mod._cx = cx;
    mod._cz = cz;
    mod._half = g * FILE_SPACING / 2 + 4;
    mod._g = g;
    for (let j = 0;j < mod.n; j++) {
      const fx = cx + (j % g - (g - 1) / 2) * FILE_SPACING;
      const fz = cz + (Math.floor(j / g) - (g - 1) / 2) * FILE_SPACING;
      const mcount = ri(2, 5);
      const methods = [];
      for (let m = 0;m < mcount; m++) {
        let h = rng();
        if (rng() < 0.22)
          h = rng() * 0.35;
        methods.push({ name: pick(VERB) + "()", loc: ri(12, 140), health: h });
      }
      const loc = methods.reduce((s, m) => s + m.loc, 0);
      const height = methods.reduce((s, m) => s + m.loc * HEIGHT_PER_LOC + SEG_GAP, 0);
      files.push({
        id: fid++,
        name: pick(PRE) + pick(NOUN) + ".ts",
        module: mod.name,
        modIdx: mi,
        x: fx,
        z: fz,
        methods,
        loc,
        height,
        coverage: rng(),
        fanIn: 0,
        fanOut: 0
      });
    }
  });
  const edges = [];
  const TYPES = ["inherit", "import", "call"];
  files.forEach((f) => {
    const out = ri(1, 3);
    for (let k = 0;k < out; k++) {
      const t = files[ri(0, files.length - 1)];
      if (t.id === f.id)
        continue;
      edges.push({ a: f.id, b: t.id, type: pick(TYPES), trunk: f.module !== t.module, payload: ri(2, 80) });
      f.fanOut++;
      t.fanIn++;
    }
  });
  const EXTERNALS = [
    { name: "POSTGRES", kind: "db", color: 5231103, x: -150, z: -72 },
    { name: "S3 · CLOUD", kind: "cloud", color: 11561983, x: -150, z: -24 },
    { name: "FILESYSTEM", kind: "fs", color: 10135476, x: -150, z: 24 },
    { name: "KAFKA", kind: "queue", color: 16743129, x: -150, z: 72 },
    { name: "MONGO", kind: "db", color: 7332463, x: 150, z: -88 },
    { name: "REDIS", kind: "cache", color: 16739179, x: 150, z: -44 },
    { name: "INFLUXDB", kind: "ts", color: 16752975, x: 150, z: 0 },
    { name: "CLICKHOUSE", kind: "ts", color: 16769359, x: 150, z: 44 },
    { name: "LOGS", kind: "logs", color: 5886112, x: 150, z: 88 },
    { name: "STRIPE · API", kind: "api", color: 6742271, x: -150, z: 120 }
  ];
  let eid = 9000;
  const exts = EXTERNALS.map((x) => Object.assign({ id: eid++, isExternal: true, modIdx: -1, fanIn: 0, fanOut: 0, height: 7 }, x));
  const EPOOL = {
    db: ["users", "sessions", "events", "orders", "metrics", "audit", "tokens", "jobs", "docs", "blobs"],
    ts: ["cpu", "mem", "latency", "rps", "errors", "io", "gc", "qdepth"],
    cache: ["session:*", "user:*", "rate:*", "lock:*", "feed:*", "cfg:*"],
    cloud: ["avatar.png", "export.csv", "backup.zip", "report.pdf", "thumb.jpg", "data.json"],
    fs: ["app.log", "config.yml", "cache.db", "tmp.bin", "index.dat"],
    queue: ["orders", "emails", "webhooks", "sync", "events", "retries"],
    logs: ["app", "access", "error", "audit", "trace"],
    api: ["/charge", "/refund", "/users", "/auth", "/webhook", "/status"]
  };
  exts.forEach((x) => {
    const k = KCFG[x.kind];
    if (!k)
      return;
    const n = ri(3, 6);
    x.items = [];
    for (let i = 0;i < n; i++)
      x.items.push({ name: pick(EPOOL[x.kind] || EPOOL.db), val: ri(k.vr[0], k.vr[1]), health: rng() });
    x.itemLabel = k.label;
    x.unit = k.unit;
  });
  const ioFiles = files.filter((f) => /Client|Adapter|Store|Cache|Repo|Manager/.test(f.name));
  exts.forEach((x, i) => {
    const cf = ioFiles.length ? ioFiles[(i * 3 + 1) % ioFiles.length] : files[ri(0, files.length - 1)];
    if (cf) {
      edges.push({ a: cf.id, b: x.id, type: "io", io: true, trunk: true, payload: ri(24, 120) });
      cf.fanOut++;
      x.fanIn++;
    }
  });
  [...files].filter((f) => f.fanOut > 0).sort((a, b) => b.fanOut - b.fanIn - (a.fanOut - a.fanIn)).slice(0, 4).forEach((f) => f.isEndpoint = true);
  files.forEach((f) => {
    f.isDead = f.fanIn === 0 && !f.isEndpoint;
  });
  if (!showDocs)
    return { MODULES, files, edges, exts, agent: null };
  const docDefs = [{ name: "README.md", agent: true, loc: 180 }, { name: "CLAUDE.md", agent: true, loc: 90 }, { name: "AGENTS.md", agent: true, loc: 70 }, { name: "ARCHITECTURE.md", agent: false, loc: 140 }];
  const dg = Math.ceil(Math.sqrt(docDefs.length));
  const dcx = 0, dcz = -(TILE_SPACING * 1.5);
  MODULES.push({ name: "docs", n: docDefs.length, _cx: dcx, _cz: dcz, _half: dg * FILE_SPACING / 2 + 4, _g: dg });
  const docModIdx = MODULES.length - 1;
  const agentFileIds = [];
  docDefs.forEach((d, j) => {
    const fx = dcx + (j % dg - (dg - 1) / 2) * FILE_SPACING;
    const fz = dcz + (Math.floor(j / dg) - (dg - 1) / 2) * FILE_SPACING;
    const segLoc = Math.max(6, Math.min(44, Math.round(6 + Math.log2(d.loc + 1) * 4.5)));
    const id = fid++;
    files.push({
      id,
      name: d.name,
      module: "docs",
      modIdx: docModIdx,
      x: fx,
      z: fz,
      methods: [{ name: d.name, loc: segLoc, health: null, dead: false, doc: true }],
      loc: d.loc,
      height: segLoc * HEIGHT_PER_LOC + SEG_GAP,
      coverage: null,
      fanIn: 0,
      fanOut: 0,
      isDoc: true,
      isAgentDoc: d.agent
    });
    if (d.agent)
      agentFileIds.push(id);
  });
  const agent = agentFileIds.length ? { name: "CLAUDE CODE · CODEX", color: 12815359, fileIds: agentFileIds } : null;
  return { MODULES, files, edges, exts, agent };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-palette.js
function resolveCyberboardPalette({ THREE: THREE2, root, colorLuma: colorLuma2 }) {
  const probe = document.createElement("span");
  probe.style.cssText = "position:absolute;left:-9999px;top:-9999px;width:0;height:0;visibility:hidden";
  (root || document.body).appendChild(probe);
  const cssHex = (name, fb) => {
    try {
      probe.style.color = "";
      probe.style.color = "var(" + name + ", rgba(0,0,0,0))";
      const c = getComputedStyle(probe).color;
      return c && c !== "rgba(0, 0, 0, 0)" && c !== "transparent" ? new THREE2.Color(c).getHex() : fb;
    } catch {
      return fb;
    }
  };
  const cssNum = (name, fb) => {
    const raw = getComputedStyle(root).getPropertyValue(name).trim();
    const n = Number(raw);
    return Number.isFinite(n) ? n : fb;
  };
  const COL = {
    bg: cssHex("--cb-bg", 395792),
    grid: cssHex("--cb-grid", 1192518),
    cyan: cssHex("--accent", 2679039),
    amber: cssHex("--warn", 16757844),
    violet: cssHex("--accent-2", 11561983),
    good: cssHex("--good", 3139232),
    warn: cssHex("--warn", 16764749),
    bad: cssHex("--bad", 16726876),
    floor: cssHex("--cb-floor", 462100),
    tile: cssHex("--cb-tile", 794672),
    tileLine: cssHex("--cb-tile-line", 1856880),
    pillarDim: cssHex("--cb-pillar-dim", 2769493),
    ambient: cssHex("--cb-light-ambient", 8956620),
    key: cssHex("--cb-light-key", 12577279)
  };
  const lightScene = colorLuma2(COL.bg) > 0.58;
  COL.edgeInherit = cssHex("--cb-edge-inherit", COL.cyan);
  COL.edgeImport = cssHex("--cb-edge-import", COL.violet);
  COL.edgeCall = cssHex("--cb-edge-call", COL.amber);
  COL.edgeIo = cssHex("--cb-edge-io", 5886112);
  COL.edgeLocal = cssHex("--cb-edge-local", 16740039);
  COL.packetRead = cssHex("--cb-packet-read", 7332863);
  COL.packetWrite = cssHex("--cb-packet-write", 5111688);
  COL.packetDelete = cssHex("--cb-packet-delete", 16733296);
  COL.packetResponse = cssHex("--cb-packet-response", 16761418);
  COL.doc = cssHex("--cb-doc", 8162208);
  COL.agent = cssHex("--cb-agent", 12815359);
  if (probe.parentNode)
    probe.parentNode.removeChild(probe);
  const EDGE_OP = {
    local: cssNum("--cb-edge-local-opacity", lightScene ? 0.36 : 0.6),
    trunk: cssNum("--cb-edge-trunk-opacity", lightScene ? 0.54 : 0.9),
    io: cssNum("--cb-edge-io-opacity", lightScene ? 0.62 : 0.92)
  };
  if (!lightScene) {
    EDGE_OP.local = Math.max(EDGE_OP.local, 0.74);
    EDGE_OP.trunk = Math.max(EDGE_OP.trunk, 0.94);
    EDGE_OP.io = Math.max(EDGE_OP.io, 0.96);
  } else {
    EDGE_OP.local = Math.max(EDGE_OP.local, 0.62);
    EDGE_OP.trunk = Math.max(EDGE_OP.trunk, 0.82);
    EDGE_OP.io = Math.max(EDGE_OP.io, 0.85);
  }
  return {
    COL,
    lightScene,
    EDGE_OP,
    C_GOOD: new THREE2.Color(COL.good),
    C_WARN: new THREE2.Color(COL.warn),
    C_BAD: new THREE2.Color(COL.bad),
    EDGE_COL: { inherit: COL.edgeInherit, import: COL.edgeImport, relation: COL.edgeImport, call: COL.edgeCall, io: COL.edgeIo, local: COL.edgeLocal },
    REQ_COL: COL.packetRead,
    RES_COL: COL.packetResponse,
    WRITE_COL: COL.packetWrite,
    DEL_COL: COL.packetDelete
  };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-flow.js
function createCyberboardFlow(ctx) {
  const {
    THREE: THREE2,
    scene,
    files,
    exts,
    edges,
    nodeById,
    maxPayload,
    REQ_COL,
    RES_COL,
    WRITE_COL,
    DEL_COL,
    edgeScopeVisible
  } = ctx;
  const outEdges = {};
  [...files, ...exts].forEach((n) => {
    outEdges[n.id] = [];
  });
  edges.forEach((e) => outEdges[e.a].push(e));
  let entryFiles = [
    ...exts.filter((x) => x.kind === "api" && outEdges[x.id].length > 0),
    ...files.filter((f) => f.isEndpoint && outEdges[f.id].length > 0)
  ];
  if (!entryFiles.length) {
    entryFiles = files.filter((f) => outEdges[f.id].length > 0).sort((a, b) => b.fanOut - a.fanOut).slice(0, 4);
  }
  const poolGeometry = new THREE2.SphereGeometry(0.5, 16, 16);
  const pool = [];
  const freeSlots = [];
  for (let i = 0;i < 160; i++) {
    const m = new THREE2.Mesh(poolGeometry, new THREE2.MeshBasicMaterial({ color: 16777215 }));
    m.visible = false;
    m.userData = { active: false, slot: i };
    scene.add(m);
    pool.push(m);
    freeSlots.push(i);
  }
  const reqSize = (p) => 0.45 + p / maxPayload * 1.6;
  const opCol = (op) => op === "write" || op === "create" || op === "update" ? WRITE_COL : op === "delete" ? DEL_COL : REQ_COL;
  function opForEdge(edge) {
    const dst = nodeById[edge.b];
    if (edge.rest || dst && dst.kind === "api")
      return "rest";
    if (edge.io && dst && dst.isExternal) {
      const r = Math.random();
      return r < 0.5 ? "read" : r < 0.7 ? "write" : r < 0.82 ? "update" : r < 0.92 ? "create" : "delete";
    }
    return "read";
  }
  function spawnReq(file) {
    if (!freeSlots.length)
      return;
    const outs = outEdges[file.id];
    if (!outs.length)
      return;
    const edge = outs[Math.random() * outs.length | 0];
    const m = pool[freeSlots.pop()];
    const op = opForEdge(edge);
    const col = opCol(op);
    Object.assign(m.userData, { active: true, phase: "req", op, col, path: [edge], idx: 0, t: 0, resScale: reqSize(edge.payload) * (0.5 + Math.random() * 1.4) });
    m.material.color.setHex(col);
    m.scale.setScalar(reqSize(edge.payload));
    m.visible = true;
  }
  function killPacket(m) {
    m.userData.active = false;
    m.visible = false;
    freeSlots.push(m.userData.slot);
  }
  function sampleRoad(e, t) {
    const pts = e._flowPts || e.pts;
    const c = e._flowCum || e.cum;
    const len = e._flowLen != null ? e._flowLen : e.len;
    const d = t * len;
    for (let k = 1;k < c.length; k++) {
      if (d <= c[k]) {
        const f = (d - c[k - 1]) / (c[k] - c[k - 1] || 1);
        return pts[k - 1].clone().lerp(pts[k], f);
      }
    }
    return pts[pts.length - 1].clone();
  }
  let spawnAcc = 0;
  const SPAWN_DT = 0.7;
  const FLOW_SPEED = 9;
  const MAXHOPS = 5;
  function update(dt, { flowing, pathEdges }) {
    exts.forEach((x) => {
      if (x._pulse <= 0)
        return;
      x._pulse = Math.max(0, x._pulse - dt * 1.6);
      x.segMats.forEach((m) => {
        m.emissiveIntensity = 0.5 + x._pulse * 1.6;
        m.emissive.setHex(x._pulse > 0.05 && x._emHex ? x._emHex : m._baseEm ?? x.color);
      });
    });
    if (flowing) {
      spawnAcc += dt;
      if (spawnAcc >= SPAWN_DT) {
        spawnAcc = 0;
        entryFiles.forEach((f) => spawnReq(f));
      }
    }
    pool.forEach((m) => {
      const u = m.userData;
      if (!u.active)
        return;
      if (!flowing) {
        m.visible = false;
        return;
      }
      const e = u.path[u.idx];
      u.t += FLOW_SPEED * dt / ((e._flowLen != null ? e._flowLen : e.len) || 1);
      if (u.t >= 1)
        advancePacket(m, u, e);
      if (!u.active)
        return;
      const ce = u.path[u.idx];
      m.position.copy(u.phase === "req" ? sampleRoad(ce, Math.min(1, u.t)) : sampleRoad(ce, 1 - Math.min(1, u.t)));
      m.visible = (pathEdges === null || pathEdges.has(ce.idx)) && edgeScopeVisible(ce);
    });
  }
  function advancePacket(m, u, e) {
    if (u.phase !== "req") {
      u.idx--;
      if (u.idx < 0)
        killPacket(m);
      else
        u.t = 0;
      return;
    }
    const node = nodeById[e.b];
    const outs = outEdges[e.b];
    if (node.isExternal || !outs.length || u.path.length >= MAXHOPS) {
      u.phase = "res";
      u.t = 0;
      m.material.color.setHex(RES_COL);
      m.scale.setScalar(u.resScale);
      if (node.isExternal) {
        node._pulse = 1;
        node._emHex = u.op === "write" || u.op === "create" || u.op === "update" ? WRITE_COL : u.op === "delete" ? DEL_COL : null;
      }
      return;
    }
    const nx = outs[Math.random() * outs.length | 0];
    u.path.push(nx);
    u.idx++;
    u.t = 0;
    const nop = opForEdge(nx);
    if (nop !== u.op) {
      u.op = nop;
      u.col = opCol(nop);
      m.material.color.setHex(u.col);
    }
    if (outs.length > 1 && Math.random() < 0.22)
      spawnReq(node);
  }
  return { outEdges, sampleRoad, update };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-focus.js
import { CSS2DObject as CSS2DObject2 } from "three/addons/renderers/CSS2DRenderer.js";

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-elevation.js
import { CSS2DObject } from "three/addons/renderers/CSS2DRenderer.js";
function createCyberboardElevation(ctx) {
  const {
    THREE: THREE2,
    opts,
    root,
    $,
    W,
    H,
    on,
    scene,
    camera,
    controls,
    edges,
    nodeById,
    KCFG,
    PILLAR_W,
    COL,
    healthColor,
    markerRingColor,
    markerRingOpacity,
    syncTag,
    clearCameraViewOffset,
    setCameraViewOffsetPixels,
    getCameraViewOffset,
    tweenCam,
    isTweening,
    state,
    setHelp,
    clearPath,
    clearNeighbors,
    setExpand,
    applyFocus,
    removeRings,
    fillDossier,
    showName,
    getBoardTap
  } = ctx;
  let elevGroup = null;
  let _methodCallouts = [], _activeMethod = -1, _segFocusFile = null;
  const ELEV_OVERFLOW_AT = 25;
  const ELEV_SHORT_LEADER_MAX = 16;
  const ELEV_VISIBLE_MIN = 20, ELEV_VISIBLE_MAX = 34;
  let _elevScroll = 0, _elevOverflow = false, _elevCount = 0, _elevVisible = ELEV_VISIBLE_MIN, _elevCodePanelOpen = false;
  let _elevLastFrame = null;
  let _elevRailWorldBounds = null;
  const elevScrollEl = $("#elev-scroll"), elevScrollTrack = elevScrollEl && elevScrollEl.querySelector(".elev-scroll-track");
  let _elevTouchDrag = null, _elevRailDrag = null, _elevSuppressClickUntil = 0;
  const dossier = $("#dossier");
  const getElevationId = state.getElevationId;
  const setElevationId = state.setElevationId;
  const setFocusId = state.setFocusId;
  function enterElevation(id) {
    _elevCodePanelOpen = false;
    _elevRailWorldBounds = null;
    clearCameraViewOffset();
    clearPath();
    clearNeighbors();
    setFocusId(null);
    setElevationId(id);
    _elevScroll = 0;
    setHelp(false);
    const f = nodeById[id];
    if (typeof opts.onMethodClose === "function")
      opts.onMethodClose();
    setExpand(null);
    applyFocus(id);
    removeRings();
    edges.forEach((e) => {
      e.line.material.opacity = 0.04;
    });
    buildElevation(f);
    fillDossier(f);
    showName(f);
    frameElevationTower(f, Math.max(8, f.height * 0.5), false);
  }
  function frameElevationTower(f, cy, withCodePanel) {
    const panel = withCodePanel ? document.querySelector(".rel-method-panel") : null;
    const panelOn = !!(panel && panel.isConnected);
    const d = Math.max(38, f.height * (_elevCodePanelOpen ? 1.16 : 1.02));
    const off = new THREE2.Vector3(d * 0.54, d * 0.28, d * 0.84);
    const look = new THREE2.Vector3(f.x0, cy, f.z0);
    const pos = look.clone().add(off);
    _elevLastFrame = { fileId: f.id, cy, withCodePanel: panelOn };
    const relayout = panelOn ? fitElevationFrameToPanel(pos, look, f) : false;
    if (!panelOn)
      clearCameraViewOffset();
    tweenCam(pos, look);
    if (relayout)
      buildElevation(f);
  }
  function fitElevationFrameToPanel(pos, look, f) {
    const panel = _elevCodePanelOpen ? document.querySelector(".rel-method-panel") : null;
    if (!panel || !panel.isConnected)
      return;
    const rootBox = root.getBoundingClientRect(), panelBox = panel.getBoundingClientRect();
    if (!rootBox.width || !rootBox.height || panelBox.right <= rootBox.left || panelBox.left >= rootBox.right)
      return;
    const railPad = elevScrollEl && elevScrollEl.classList.contains("on") ? 46 : 18;
    const freeLeft = Math.max(rootBox.left, panelBox.right);
    const freeRight = rootBox.right - railPad;
    const freeW = freeRight - freeLeft;
    if (freeW < 120)
      return;
    const base = new THREE2.Vector3(f.x0, 0, f.z0);
    const p = projectForCamera(base, pos, look);
    if (!p)
      return;
    const desiredX = freeLeft + Math.max(42, Math.min(72, freeW * 0.11));
    const desiredY = Math.min(rootBox.bottom - 34, panelBox.bottom - 22);
    setCameraViewOffsetPixels(p.x - desiredX, p.y - desiredY);
    return fitElevationRailToPanel(f, pos, look, panelBox);
  }
  function projectForCamera(point, pos, look) {
    const cam = camera.clone();
    cam.position.copy(pos);
    cam.up.set(0, 1, 0);
    cam.lookAt(look);
    cam.clearViewOffset();
    cam.aspect = camera.aspect;
    cam.updateProjectionMatrix();
    cam.updateMatrixWorld();
    const ndc = point.clone().project(cam);
    if (!Number.isFinite(ndc.x) || !Number.isFinite(ndc.y))
      return null;
    const rootBox = root.getBoundingClientRect();
    return { x: rootBox.left + (ndc.x + 1) * 0.5 * rootBox.width, y: rootBox.top + (1 - ndc.y) * 0.5 * rootBox.height };
  }
  function projectForCameraWithOffset(point, pos, look) {
    const p = projectForCamera(point, pos, look);
    if (!p)
      return null;
    const viewOffset = typeof getCameraViewOffset === "function" ? getCameraViewOffset() : null;
    return { x: p.x - (viewOffset && viewOffset.x || 0) * W(), y: p.y - (viewOffset && viewOffset.y || 0) * H() };
  }
  function elevCalloutColumnX(f, n = null) {
    if (!f || !f.isExternal) {
      const byHeight2 = Math.min(34, Math.max(0, (Number(f && f.height) || 0) - 40) * 0.34);
      return (f && f.x0 || 0) + 15 + byHeight2;
    }
    const count = n == null ? (f.items || []).length : n;
    if (f.kind === "db" && /mongo/i.test(String(f.name || ""))) {
      return f.x0 + 18 + Math.min(3, Math.max(0, count - 4) * 0.25);
    }
    const byHeight = Math.min(13, Math.max(0, (Number(f.height) || 0) - 45) * 0.08);
    const byCount = Math.min(8, Math.max(0, count - 8) * 0.35);
    return f.x0 + 20 + byHeight + byCount;
  }
  function worldYForScreenY(f, pos, look, screenY) {
    const x = elevCalloutColumnX(f), z = f.z0;
    let lo = 0, hi = Math.max(2, f.height);
    for (let k = 0;k < 26; k++) {
      const mid = (lo + hi) * 0.5;
      const p = projectForCameraWithOffset(new THREE2.Vector3(x, mid, z), pos, look);
      if (!p)
        return null;
      if (p.y > screenY)
        lo = mid;
      else
        hi = mid;
    }
    return (lo + hi) * 0.5;
  }
  function fitElevationRailToPanel(f, pos, look, panelBox) {
    const topY = worldYForScreenY(f, pos, look, panelBox.top + 28);
    const bottomY = worldYForScreenY(f, pos, look, panelBox.bottom - 22);
    if (topY == null || bottomY == null)
      return false;
    const bottom = Math.max(0.8, Math.min(bottomY, topY - 2));
    const top = Math.min(Math.max(2, f.height), Math.max(topY, bottom + 2));
    const next = { fileId: f.id, bottom, top, span: Math.max(2, top - bottom) };
    const prev = _elevRailWorldBounds;
    _elevRailWorldBounds = next;
    return !prev || prev.fileId !== next.fileId || Math.abs(prev.bottom - next.bottom) > 0.25 || Math.abs(prev.top - next.top) > 0.25;
  }
  function elevRailBounds(f) {
    if (_elevCodePanelOpen && _elevRailWorldBounds && _elevRailWorldBounds.fileId === f.id) {
      return _elevRailWorldBounds;
    }
    const bottom = Math.max(1.2, f.height * 0.025);
    const top = Math.max(bottom + 2, f.height - Math.max(2.8, f.height * 0.045));
    return { bottom, top, span: Math.max(2, top - bottom) };
  }
  function elevVisibleCount(f, n) {
    if (n < ELEV_OVERFLOW_AT)
      return n;
    const rail = elevRailBounds(f);
    const step = Math.max(1.35, Math.min(1.75, rail.span / (ELEV_VISIBLE_MIN - 1)));
    const byHeight = Math.floor(rail.span / step) + 1;
    return Math.max(ELEV_VISIBLE_MIN, Math.min(n, ELEV_VISIBLE_MAX, byHeight));
  }
  function buildElevation(f) {
    const activeList = f.isExternal ? f.items : f.methods;
    const keepActive = _activeMethod >= 0 && activeList && activeList[_activeMethod] ? _activeMethod : -1;
    removeElevation();
    elevGroup = new THREE2.Group;
    scene.add(elevGroup);
    _methodCallouts = [];
    _activeMethod = keepActive;
    const { x0, z0 } = f, rad = f.isExternal ? 3.1 : PILLAR_W * 0.6;
    const pickMethods = !f.isExternal && !!f._path && typeof opts.onMethodOpen === "function";
    const pickItems = f.isExternal && typeof opts.onItemOpen === "function";
    const all = f.isExternal ? (f.items || []).map((t, i) => ({ idx: i, seg: f.segMid[i], item: t, hc: healthColor(t.health).getHexString(), nm: t.name, sub: `${Math.round(t.val)} ${f.unit || ""} &middot; ${Math.round(t.health * 100)}%${t.time ? " &middot; " + t.time : ""}` })) : f.methods.map((m, i) => ({
      idx: i,
      seg: f.segMid[i],
      dead: !!m.dead,
      hc: m.dead ? "ff1b4d" : healthColor(m.health).getHexString(),
      nm: m.name,
      sub: m.dead ? "" : `${m.loc} loc &middot; ${Math.round((m.health || 0) * 100)}%`
    }));
    const N = all.length, rail = _elevCodePanelOpen || N >= ELEV_OVERFLOW_AT, VIS = elevVisibleCount(f, N), overflow = rail && N > VIS;
    const colX = elevCalloutColumnX(f, N);
    _elevCount = N;
    _elevVisible = VIS;
    _elevOverflow = overflow;
    _elevScroll = overflow ? Math.max(0, Math.min(_elevScroll, N - VIS)) : 0;
    const lo = overflow ? _elevScroll : 0, hi = overflow ? _elevScroll + VIS : N;
    const win = all.slice(lo, hi);
    const moreUp = overflow ? N - hi : 0, moreDown = overflow ? lo : 0;
    const labelYs = layoutElevLabelYs(f, win, rail, moreUp > 0, moreDown > 0);
    win.forEach((it, j) => {
      const cy = it.seg, ly = labelYs[j] ?? cy;
      const shortenLeader = !f.isExternal && !overflow && N <= ELEV_SHORT_LEADER_MAX;
      const labelX = shortenLeader ? x0 + rad + (colX - (x0 + rad)) * 0.75 : colX;
      const leadStartX = x0 + rad + (f.isExternal ? 0.9 : 0);
      const leadStart = new THREE2.Vector3(leadStartX, cy, z0);
      const leadFull = rail ? new THREE2.Vector3(labelX - 1.2, ly, z0) : new THREE2.Vector3(labelX - 1.2, cy, z0);
      const pts = f.isExternal ? [leadStart, new THREE2.Vector3(Math.min(labelX - 2, leadStartX + 2.4), cy, z0), leadFull] : [leadStart, leadFull];
      const g = new THREE2.BufferGeometry().setFromPoints(pts);
      elevGroup.add(new THREE2.Line(g, new THREE2.LineBasicMaterial({ color: COL.cyan, transparent: true, opacity: 0.55 })));
      const el = document.createElement("div");
      el.className = "lbl callout" + (it.dead ? " callout-dead" : "");
      const name = document.createElement("b");
      name.style.color = "#" + it.hc;
      name.textContent = it.nm;
      el.append(name, document.createTextNode(it.sub ? " " + it.sub : ""));
      if (pickMethods || pickItems) {
        el.classList.toggle("active", it.idx === _activeMethod);
        el.classList.add(pickMethods ? "method-pick" : "item-pick");
        el.title = pickMethods ? "Click to inspect this method’s source" : "Click to inspect this external item";
        el.addEventListener("pointerdown", (ev) => {
          ev.stopPropagation();
        });
        el.addEventListener("click", (ev) => {
          ev.stopPropagation();
          pickMethods ? openMethod(f, it.idx) : openExternalItem(f, it.idx);
        });
        _methodCallouts[it.idx] = el;
      }
      const o = new CSS2DObject(el);
      o.position.set(labelX, ly, z0);
      fitElevCallout(o, rail);
      elevGroup.add(o);
    });
    if (overflow) {
      const page = VIS - 2;
      if (moreUp > 0)
        addElevMore(colX, labelYs[labelYs.length - 1] + 3.6, z0, `▲ ${moreUp} more`, () => scrollElev(f, page));
      if (moreDown > 0)
        addElevMore(colX, labelYs[0] - 3.6, z0, `▼ ${moreDown} more`, () => scrollElev(f, -page));
    }
    if (_activeMethod >= 0)
      setSegFocus(f, _activeMethod);
    updateElevScroller();
  }
  function layoutElevLabelYs(f, win, rail, hasMoreUp = false, hasMoreDown = false) {
    if (!rail || win.length < 2)
      return win.map((it) => it.seg);
    const bounds = elevRailBounds(f);
    const bottom = bounds.bottom + (hasMoreDown ? 3.8 : 0);
    const top = Math.max(bottom + 1.5, bounds.top - (hasMoreUp ? 3.8 : 0));
    const step = (top - bottom) / (win.length - 1);
    return win.map((_, i) => bottom + i * step);
  }
  function addElevMore(x, y, z, txt, onClick) {
    const el = document.createElement("div");
    el.className = "lbl callout method-pick elev-more";
    el.textContent = txt;
    el.title = "Scroll the method list (or use the mouse wheel)";
    el.addEventListener("click", (ev) => {
      ev.stopPropagation();
      onClick();
    });
    const o = new CSS2DObject(el);
    o.position.set(x, y, z);
    fitElevCallout(o, true);
    elevGroup.add(o);
  }
  function fitElevCallout(o, active) {
    if (active)
      o.onAfterRender = () => fitElevCalloutElement(o.element);
    return o;
  }
  function fitElevCalloutElement(el) {
    if (!el || el.style.display === "none")
      return;
    const rootBox = root.getBoundingClientRect();
    if (!rootBox.width || !rootBox.height)
      return;
    const panel = _elevCodePanelOpen ? document.querySelector(".rel-method-panel") : null;
    const panelBox = panel && panel.isConnected ? panel.getBoundingClientRect() : null;
    let left = rootBox.left + 10;
    if (panelBox && panelBox.right > rootBox.left && panelBox.left < rootBox.right)
      left = Math.min(rootBox.right - 160, Math.max(left, panelBox.right + 10));
    const right = rootBox.right - (elevScrollEl && elevScrollEl.classList.contains("on") ? 48 : 14);
    el.style.maxWidth = Math.max(140, Math.floor(right - left)) + "px";
    if (!panelBox)
      return;
    const rect = el.getBoundingClientRect();
    if (!rect.width || !rect.height)
      return;
    let dx = 0, dy = 0;
    if (rect.left < left)
      dx = left - rect.left;
    else if (rect.right > right)
      dx = right - rect.right;
    const top = rootBox.top + 54, bottom = rootBox.bottom - 24;
    if (rect.top < top)
      dy = top - rect.top;
    else if (rect.bottom > bottom)
      dy = bottom - rect.bottom;
    if (dx || dy)
      el.style.transform += ` translate(${Math.round(dx)}px,${Math.round(dy)}px)`;
  }
  function scrollElev(f, delta) {
    if (!f || getElevationId() == null || !_elevOverflow)
      return;
    const next = Math.max(0, Math.min(_elevScroll + delta, _elevCount - _elevVisible));
    if (next === _elevScroll)
      return;
    _elevScroll = next;
    if (_elevLastFrame && _elevLastFrame.fileId === f.id && _elevLastFrame.withCodePanel) {
      fitElevationFrameToPanel(camera.position.clone(), controls.target.clone(), f);
    }
    buildElevation(f);
  }
  function maxElevScroll() {
    return Math.max(0, _elevCount - _elevVisible);
  }
  function updateElevScroller() {
    if (!elevScrollEl)
      return;
    const max = maxElevScroll(), onNow = getElevationId() != null && _elevOverflow && _elevCount > _elevVisible && max > 0;
    elevScrollEl.classList.toggle("on", onNow);
    elevScrollEl.setAttribute("aria-hidden", onNow ? "false" : "true");
    if (!onNow) {
      elevScrollEl.style.removeProperty("--elev-thumb-height");
      elevScrollEl.style.removeProperty("--elev-thumb-top");
      elevScrollEl.setAttribute("aria-valuemax", "0");
      elevScrollEl.setAttribute("aria-valuenow", "0");
      elevScrollEl.removeAttribute("aria-valuetext");
      return;
    }
    const thumbPct = Math.max(12, Math.min(82, _elevVisible / _elevCount * 100));
    const topPct = (100 - thumbPct) * (1 - _elevScroll / max);
    elevScrollEl.style.setProperty("--elev-thumb-height", thumbPct.toFixed(2) + "%");
    elevScrollEl.style.setProperty("--elev-thumb-top", topPct.toFixed(2) + "%");
    elevScrollEl.setAttribute("aria-valuemax", String(max));
    elevScrollEl.setAttribute("aria-valuenow", String(_elevScroll));
    elevScrollEl.setAttribute("aria-valuetext", `${_elevScroll + 1}-${Math.min(_elevScroll + _elevVisible, _elevCount)} of ${_elevCount}`);
  }
  function setElevScrollFromClientY(clientY) {
    const f = nodeById[getElevationId()], max = maxElevScroll(), box = (elevScrollTrack || elevScrollEl).getBoundingClientRect();
    if (!f || !_elevOverflow || !box.height || max <= 0)
      return;
    const y = Math.max(0, Math.min(1, (clientY - box.top) / box.height));
    scrollElev(f, Math.round((1 - y) * max) - _elevScroll);
  }
  function endElevRailDrag(ev) {
    if (!_elevRailDrag || ev.pointerId !== _elevRailDrag.id)
      return;
    try {
      elevScrollEl.releasePointerCapture(ev.pointerId);
    } catch {}
    controls.enabled = _elevRailDrag.controlsWasOn && !isTweening();
    _elevRailDrag = null;
    ev.preventDefault();
    ev.stopPropagation();
  }
  if (elevScrollEl) {
    on(elevScrollEl, "pointerdown", (ev) => {
      if (getElevationId() == null || !_elevOverflow)
        return;
      _elevRailDrag = { id: ev.pointerId, controlsWasOn: controls.enabled };
      controls.enabled = false;
      try {
        elevScrollEl.setPointerCapture(ev.pointerId);
      } catch {}
      setElevScrollFromClientY(ev.clientY);
      ev.preventDefault();
      ev.stopPropagation();
    }, { passive: false });
    on(elevScrollEl, "pointermove", (ev) => {
      if (!_elevRailDrag || ev.pointerId !== _elevRailDrag.id)
        return;
      setElevScrollFromClientY(ev.clientY);
      ev.preventDefault();
      ev.stopPropagation();
    }, { passive: false });
    on(elevScrollEl, "pointerup", endElevRailDrag, { passive: false });
    on(elevScrollEl, "pointercancel", endElevRailDrag, { passive: false });
  }
  function beginElevTouchDrag(ev) {
    if (ev.pointerType === "mouse" || getElevationId() == null || !_elevOverflow || !nodeById[getElevationId()])
      return;
    if (ev.button && ev.button !== 0)
      return;
    if (elevScrollEl && elevScrollEl.contains(ev.target))
      return;
    const hud = ev.target.closest && ev.target.closest(".hud");
    if (hud)
      return;
    _elevTouchDrag = {
      id: ev.pointerId,
      x: ev.clientX,
      y: ev.clientY,
      lastY: ev.clientY,
      acc: 0,
      scrolling: false,
      controlsWasOn: controls.enabled,
      downTarget: ev.target
    };
    ev.stopPropagation();
  }
  function moveElevTouchDrag(ev) {
    if (!_elevTouchDrag || ev.pointerId !== _elevTouchDrag.id)
      return;
    const f = nodeById[getElevationId()];
    if (!f || !_elevOverflow)
      return;
    const dx = ev.clientX - _elevTouchDrag.x, dy = ev.clientY - _elevTouchDrag.y;
    if (!_elevTouchDrag.scrolling) {
      if (Math.hypot(dx, dy) < 8)
        return;
      _elevTouchDrag.scrolling = true;
      controls.enabled = false;
      try {
        root.setPointerCapture(ev.pointerId);
      } catch {}
    }
    ev.preventDefault();
    ev.stopPropagation();
    const movedY = ev.clientY - _elevTouchDrag.lastY;
    _elevTouchDrag.lastY = ev.clientY;
    _elevTouchDrag.acc += movedY;
    const pxPerMethod = Math.max(12, Math.min(30, H() / (_elevVisible * 1.2)));
    const steps = _elevTouchDrag.acc > 0 ? Math.floor(_elevTouchDrag.acc / pxPerMethod) : Math.ceil(_elevTouchDrag.acc / pxPerMethod);
    if (steps) {
      _elevTouchDrag.acc -= steps * pxPerMethod;
      scrollElev(f, -steps);
    }
  }
  function endElevTouchDrag(ev, cancelled = false) {
    if (!_elevTouchDrag || ev.pointerId !== _elevTouchDrag.id)
      return;
    const st = _elevTouchDrag, moved = Math.hypot(ev.clientX - st.x, ev.clientY - st.y);
    try {
      root.releasePointerCapture(ev.pointerId);
    } catch {}
    controls.enabled = st.controlsWasOn && !isTweening();
    _elevTouchDrag = null;
    if (st.scrolling) {
      _elevSuppressClickUntil = performance.now() + 350;
      ev.preventDefault();
      ev.stopPropagation();
      return;
    }
    if (!cancelled && moved <= 8) {
      const target = st.downTarget, isMethod = target.closest && target.closest(".method-pick,.item-pick,.tag-pick"), isHud = target.closest && target.closest(".hud");
      if (!isMethod && !isHud) {
        const boardTap = typeof getBoardTap === "function" ? getBoardTap() : null;
        if (typeof boardTap === "function") {
          boardTap(ev);
          ev.preventDefault();
          ev.stopPropagation();
        }
      }
    }
  }
  on(root, "pointerdown", beginElevTouchDrag, { passive: false, capture: true });
  on(root, "pointermove", moveElevTouchDrag, { passive: false, capture: true });
  on(root, "pointerup", (ev) => endElevTouchDrag(ev), { passive: false, capture: true });
  on(root, "pointercancel", (ev) => endElevTouchDrag(ev, true), { passive: false, capture: true });
  on(root, "click", (ev) => {
    if (_elevSuppressClickUntil && performance.now() < _elevSuppressClickUntil) {
      ev.preventDefault();
      ev.stopPropagation();
    }
  }, { capture: true });
  function setActiveMethodVisual(f, i) {
    _activeMethod = i;
    _methodCallouts.forEach((el, k) => {
      if (el)
        el.classList.toggle("active", k === i);
    });
    setSegFocus(f, i);
  }
  function openMethod(f, i) {
    const m = f.methods && f.methods[i];
    if (!m)
      return;
    const panelReady = _elevCodePanelOpen && _elevLastFrame && _elevLastFrame.fileId === f.id && _elevLastFrame.withCodePanel && _elevRailWorldBounds && _elevRailWorldBounds.fileId === f.id;
    _elevCodePanelOpen = true;
    const methods = f.methods || [];
    const vis = elevVisibleCount(f, methods.length);
    const max = Math.max(0, methods.length - vis);
    let needsRebuild = !elevGroup;
    if (max > 0) {
      const nextScroll = Math.max(0, Math.min(i - Math.floor(vis * 0.55), max));
      needsRebuild = needsRebuild || nextScroll !== _elevScroll || i < _elevScroll || i >= _elevScroll + vis;
      _elevScroll = nextScroll;
    } else {
      needsRebuild = needsRebuild || _elevScroll !== 0;
      _elevScroll = 0;
    }
    _activeMethod = i;
    if (panelReady && needsRebuild)
      buildElevation(f);
    setActiveMethodVisual(f, i);
    if (typeof dossier !== "undefined" && dossier)
      dossier.classList.remove("on");
    const cy = Math.max(8, f.height * 0.5);
    try {
      opts.onMethodOpen({
        path: f._path,
        fileId: f._fileId || null,
        file: f.name,
        name: m.name,
        line: m.line || null,
        loc: m.loc || 0,
        index: i,
        health: m.health,
        healthMeta: m.healthMeta || null,
        dead: !!m.dead,
        methods: (f.methods || []).map((x) => ({ name: x.name, line: x.line || null, loc: x.loc || 0, health: x.health || 0, healthMeta: x.healthMeta || null, dead: !!x.dead }))
      });
    } catch (e) {
      console.error("[cyberboard] onMethodOpen failed", e);
    }
    if (!panelReady)
      requestAnimationFrame(() => {
        if (getElevationId() === f.id)
          frameElevationTower(f, cy, true);
      });
  }
  function openExternalItem(f, i) {
    const t = f.items && f.items[i];
    if (!t)
      return;
    const panelReady = _elevCodePanelOpen && _elevLastFrame && _elevLastFrame.fileId === f.id && _elevLastFrame.withCodePanel && _elevRailWorldBounds && _elevRailWorldBounds.fileId === f.id;
    _elevCodePanelOpen = true;
    const items = f.items || [];
    const vis = elevVisibleCount(f, items.length);
    const max = Math.max(0, items.length - vis);
    let needsRebuild = !elevGroup;
    if (max > 0) {
      const nextScroll = Math.max(0, Math.min(i - Math.floor(vis * 0.55), max));
      needsRebuild = needsRebuild || nextScroll !== _elevScroll || i < _elevScroll || i >= _elevScroll + vis;
      _elevScroll = nextScroll;
    } else {
      needsRebuild = needsRebuild || _elevScroll !== 0;
      _elevScroll = 0;
    }
    _activeMethod = i;
    if (panelReady && needsRebuild)
      buildElevation(f);
    setActiveMethodVisual(f, i);
    if (typeof dossier !== "undefined" && dossier)
      dossier.classList.remove("on");
    try {
      opts.onItemOpen({
        id: f.id,
        name: f.name,
        kind: f.kind || "external",
        itemLabel: f.itemLabel || (KCFG[f.kind] || KCFG.db).label,
        unit: f.unit || (KCFG[f.kind] || KCFG.db).unit,
        fanIn: f.fanIn || 0,
        fanOut: f.fanOut || 0,
        index: i,
        confidence: f.confidence || "",
        sources: f.sources || [],
        signals: f.signals || [],
        sourceFiles: f.sourceFiles || [],
        connectors: f.connectors || [],
        item: Object.assign({}, t, { name: t.name, val: t.val, value: t.value, count: t.count, health: t.health }),
        items: items.map((x) => Object.assign({}, x, { name: x.name, val: x.val, value: x.value, count: x.count, health: x.health }))
      });
    } catch (e) {
      console.error("[cyberboard] onItemOpen failed", e);
    }
    if (!panelReady)
      requestAnimationFrame(() => {
        if (getElevationId() === f.id)
          frameElevationTower(f, Math.max(8, f.height * 0.5), true);
      });
  }
  function setSegFocus(f, i) {
    if (_segFocusFile && _segFocusFile !== f)
      restoreSeg(_segFocusFile);
    _segFocusFile = f;
    (f.segMats || []).forEach((mat, k) => {
      const on2 = k === i;
      mat.emissiveIntensity = on2 ? 2.35 : 0.24;
      mat.opacity = on2 ? 1 : 0.42;
    });
  }
  function applyFade(f) {
    const op = f.faded ? 0.17 : 1, em = f.faded ? 0.13 : 0.55;
    (f.segMats || []).forEach((mat) => {
      mat.opacity = op;
      mat.emissiveIntensity = em;
    });
    if (f.glow) {
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = markerRingOpacity(f);
    }
    f._tagOpacity = f.faded ? "0.3" : "";
    syncTag(f);
  }
  function restoreSeg(f) {
    if (!f)
      return;
    applyFade(f);
  }
  function clearSegFocus() {
    if (_segFocusFile) {
      restoreSeg(_segFocusFile);
      _segFocusFile = null;
    }
  }
  function removeElevation() {
    _methodCallouts = [];
    _activeMethod = -1;
    clearSegFocus();
    if (elevGroup) {
      scene.remove(elevGroup);
      elevGroup.traverse((o) => {
        if (o.geometry)
          o.geometry.dispose();
        if (o.material)
          o.material.dispose();
        if (o.element && o.element.parentNode)
          o.element.parentNode.removeChild(o.element);
      });
      elevGroup = null;
    }
    updateElevScroller();
  }
  function resetPanelState() {
    _elevCodePanelOpen = false;
    _elevRailWorldBounds = null;
  }
  function markCodePanelOpen() {
    _elevCodePanelOpen = true;
  }
  function frameFileIfActive(f) {
    if (getElevationId() === f.id)
      requestAnimationFrame(() => {
        if (getElevationId() === f.id)
          frameElevationTower(f, Math.max(8, f.height * 0.5), true);
      });
  }
  function handleWheel(ev) {
    if (getElevationId() == null || !_elevOverflow)
      return false;
    ev.preventDefault();
    ev.stopPropagation();
    scrollElev(nodeById[getElevationId()], ev.deltaY < 0 ? 3 : -3);
    return true;
  }
  function selectMethod(i) {
    if (getElevationId() == null)
      return false;
    const f = nodeById[getElevationId()];
    if (!f || !f.methods || !f.methods[i])
      return false;
    openMethod(f, i);
    return true;
  }
  function selectItem(i) {
    if (getElevationId() == null)
      return false;
    const f = nodeById[getElevationId()];
    if (!f || !f.isExternal || !f.items || !f.items[i])
      return false;
    openExternalItem(f, i);
    return true;
  }
  return {
    enterElevation,
    frameFileIfActive,
    getSuppressClickUntil: () => _elevSuppressClickUntil,
    handleWheel,
    markCodePanelOpen,
    removeElevation,
    resetPanelState,
    selectItem,
    selectMethod
  };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-focus.js
function createCyberboardFocus(ctx) {
  const {
    THREE: THREE2,
    opts,
    root,
    $,
    W,
    H,
    on,
    scene,
    camera,
    controls,
    files,
    exts,
    edges,
    MODULES,
    nodeById,
    outEdges,
    KCFG,
    PILLAR_W,
    MAX,
    COL,
    healthColor,
    markerRingColor,
    markerRingOpacity,
    syncTag,
    edgeScopeVisible,
    setEdgeScopeReveal,
    clearCameraViewOffset,
    setCameraViewOffsetPixels,
    getCameraViewOffset,
    tweenCam,
    isTweening,
    OVERVIEW_POS,
    OVERVIEW_LOOK,
    mergeLayer,
    router,
    edgeTypeOn,
    contextEdgeVisible
  } = ctx;
  let focusId = null, ringGroup = null, elevationId = null;
  let focusNeighbors = null, focusEdges = null, neighborGroup = null;
  const dossier = $("#dossier");
  function fileEdges(id) {
    return edges.filter((e) => e.a === id || e.b === id);
  }
  function badgeNodePayload(n) {
    if (!n)
      return null;
    return {
      id: n.id,
      name: n.name || "",
      path: n._path || "",
      fileId: n._fileId || null,
      module: n.module || "",
      kind: n.kind || "",
      isExternal: !!n.isExternal,
      fanIn: n.fanIn || 0,
      fanOut: n.fanOut || 0
    };
  }
  function badgeEdgePayload(e) {
    return {
      type: e.type || "edge",
      io: !!e.io,
      rest: !!e.rest,
      payload: e.payload || 0,
      from: badgeNodePayload(nodeById[e.a]),
      to: badgeNodePayload(nodeById[e.b])
    };
  }
  function fileStatusPayload(f) {
    const inbound = edges.filter((e) => e.b === f.id).map(badgeEdgePayload);
    const outbound = edges.filter((e) => e.a === f.id).map(badgeEdgePayload);
    const role = f.isDead ? "dead" : f.isEndpoint ? "entry" : "file";
    const methods = (f.methods || []).map((x) => ({
      name: x.name,
      line: x.line || null,
      loc: x.loc || 0,
      health: x.health || 0,
      healthMeta: x.healthMeta || null,
      dead: !!x.dead
    }));
    return {
      id: f.id,
      role,
      path: f._path || "",
      fileId: f._fileId || null,
      file: f.name,
      module: f.module || "",
      isEntry: !!f.isEndpoint,
      isDead: !!f.isDead,
      reason: f.isDead ? f.deadReason || "isolated file" : f.entryReason || "entry point heuristic",
      reasons: Array.isArray(f.statusReasons) ? f.statusReasons.filter(Boolean) : [],
      fanIn: f.fanIn || 0,
      fanOut: f.fanOut || 0,
      visibleIn: inbound.length,
      visibleOut: outbound.length,
      loc: f.loc || 0,
      methodCount: methods.length,
      coverage: f.coverage == null ? null : f.coverage,
      health: avgHealth(f),
      methods,
      inbound,
      outbound
    };
  }
  function openFileBadge(f) {
    if (!f || typeof opts.onFileBadgeOpen !== "function")
      return;
    elevation.markCodePanelOpen();
    if (typeof dossier !== "undefined" && dossier)
      dossier.classList.remove("on");
    try {
      opts.onFileBadgeOpen(fileStatusPayload(f));
    } catch (e) {
      console.error("[cyberboard] onFileBadgeOpen failed", e);
    }
    elevation.frameFileIfActive(f);
  }
  const clamp01 = (v) => Math.max(0, Math.min(1, v));
  function avgHealth(f) {
    const methods = f.methods || [];
    const total = methods.reduce((s, m) => s + Math.max(1, m.loc || 1), 0);
    const weighted = total ? methods.reduce((s, m) => s + (m.health || 0) * Math.max(1, m.loc || 1), 0) / total : 0.5;
    const couplingPenalty = Math.min(0.12, Math.log2((f.fanOut || 0) + 1) * 0.035 + Math.log2((f.fanIn || 0) + 1) * 0.02);
    return clamp01(weighted - couplingPenalty);
  }
  function gauge(idx, total, radius, frac, color, labelTxt) {
    const bg = new THREE2.Mesh(new THREE2.RingGeometry(radius, radius + 0.9, 48), new THREE2.MeshBasicMaterial({ color, transparent: true, opacity: 0.12, side: THREE2.DoubleSide }));
    bg.rotation.x = -Math.PI / 2;
    bg.position.set(0, 1.6, 0);
    const arc = new THREE2.Mesh(new THREE2.RingGeometry(radius, radius + 0.9, Math.max(8, Math.round(64 * frac)), 1, Math.PI / 2, Math.max(0.0001, frac) * Math.PI * 2), new THREE2.MeshBasicMaterial({ color, transparent: true, opacity: 0.92, side: THREE2.DoubleSide }));
    arc.rotation.x = -Math.PI / 2;
    arc.position.set(0, 1.62, 0);
    ringGroup.add(bg);
    ringGroup.add(arc);
    const lab = document.createElement("div");
    lab.className = "lbl ring";
    lab.textContent = labelTxt;
    const o = new CSS2DObject2(lab);
    o.position.set(13.5, 0.6, (idx - (total - 1) / 2) * 2.9);
    ringGroup.add(o);
  }
  function buildRings(f) {
    removeRings();
    ringGroup = new THREE2.Group;
    f.group.add(ringGroup);
    const fan = f.fanIn + f.fanOut, n = 5;
    if (f.isExternal) {
      const k = KCFG[f.kind] || KCFG.db;
      const it = f.items || [], ah2 = it.length ? it.reduce((s, t) => s + t.health, 0) / it.length : 0.5, tot = it.reduce((s, t) => s + t.val, 0);
      gauge(0, n, 5, Math.min(1, fan / MAX.fan), COL.cyan, `LINKS ${fan}`);
      gauge(1, n, 6.6, Math.min(1, tot / 2000), COL.cyan, `${(f.unit || k.unit || "").toUpperCase()} ~${tot}`);
      gauge(2, n, 8.2, Math.min(1, it.length / 8), COL.cyan, `${f.itemLabel || k.label || "ITEMS"} ${it.length}`);
      gauge(3, n, 9.8, 1, COL.amber, (f.kind || "ext").toUpperCase());
      gauge(4, n, 11.4, it.length ? ah2 : 0, it.length ? healthColor(ah2).getHex() : COL.doc, it.length ? `HEALTH ${Math.round(ah2 * 100)}%` : `HEALTH n/a`);
      return;
    }
    const ah = f.unknownHealth ? 0.5 : avgHealth(f);
    gauge(0, n, 5, Math.min(1, fan / MAX.fan), COL.cyan, `COUPLING ${fan}`);
    gauge(1, n, 6.6, Math.min(1, f.loc / MAX.loc), COL.cyan, f.loc == null ? `LOC n/a` : `LOC ${f.loc}`);
    gauge(2, n, 8.2, Math.min(1, f.methods.length / MAX.meth), COL.cyan, f.symbolsUnavailable ? `METHODS n/a` : `METHODS ${f.methods.length}`);
    gauge(3, n, 9.8, f.coverage == null ? 0 : f.coverage, COL.amber, f.coverage == null ? `COVERAGE n/a` : `COVERAGE ${Math.round(f.coverage * 100)}%`);
    gauge(4, n, 11.4, f.unknownHealth ? 0 : ah, f.unknownHealth ? COL.doc : healthColor(ah).getHex(), f.unknownHealth ? `HEALTH n/a` : `HEALTH ${Math.round(ah * 100)}%`);
  }
  function removeRings() {
    if (ringGroup) {
      if (ringGroup.parent)
        ringGroup.parent.remove(ringGroup);
      ringGroup.traverse((o) => {
        if (o.geometry)
          o.geometry.dispose();
        if (o.material)
          o.material.dispose();
        if (o.element && o.element.parentNode)
          o.element.parentNode.removeChild(o.element);
      });
      ringGroup = null;
    }
  }
  function applyFocus(id) {
    setEdgeScopeReveal((e) => id !== null && focusEdges && focusEdges.has(e.idx));
    const fm = id === null || nodeById[id].isExternal ? -999 : files[id].modIdx;
    const connMods = new Set;
    if (id !== null) {
      const fn = nodeById[id];
      if (fn && !fn.isExternal)
        connMods.add(fn.modIdx);
      if (focusNeighbors)
        focusNeighbors.forEach((nid) => {
          const n = nodeById[nid];
          if (n && !n.isExternal)
            connMods.add(n.modIdx);
        });
    }
    files.forEach((f) => {
      let op, emi, gl;
      if (id === null) {
        if (f.faded) {
          op = 0.17;
          emi = 0.13;
          gl = 0.06;
        } else {
          op = 1;
          emi = 0.55;
          gl = f.isDead ? 0.5 : 0.25;
        }
      } else if (f.id === id) {
        op = 1;
        emi = 1;
        gl = 0.75;
      } else if (focusNeighbors && focusNeighbors.has(f.id)) {
        op = 0.95;
        emi = 0.7;
        gl = 0.5;
      } else if (f.modIdx === fm) {
        op = 0.4;
        emi = 0.22;
        gl = 0.3;
      } else {
        op = 0.05;
        emi = 0.07;
        gl = 0.04;
      }
      f.segMats.forEach((m) => {
        m.opacity = op;
        m.emissiveIntensity = emi;
      });
      if (id === null && !f.faded)
        gl = markerRingOpacity(f);
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = gl;
      if (f.tag) {
        f._tagOpacity = id === null ? "" : op >= 0.3 ? "1" : f.isDead ? "0.18" : "0";
        syncTag(f);
      }
    });
    exts.forEach((x) => {
      let op, emi;
      if (id === null) {
        op = 1;
        emi = 0.5;
      } else if (x.id === id) {
        op = 1;
        emi = 1;
      } else if (focusNeighbors && focusNeighbors.has(x.id)) {
        op = 0.95;
        emi = 0.9;
      } else {
        op = 0.12;
        emi = 0.1;
      }
      x.segMats.forEach((m) => {
        m.opacity = op;
        m.emissiveIntensity = emi;
      });
      if (x.glow)
        x.glow.material.opacity = x.id === id ? 0.75 : id === null ? 0.3 : focusNeighbors && focusNeighbors.has(x.id) ? 0.5 : 0.06;
    });
    MODULES.forEach((m, i) => {
      const conn = id === null || i === fm || connMods.has(i);
      if (m.tileEdgeMat)
        m.tileEdgeMat.opacity = id !== null && i === fm ? 1 : conn ? m.tileBaseLine : m.tileBaseLine * 0.16;
      if (m.label && m.label.element)
        m.label.element.style.opacity = id === null || conn ? "" : "0.14";
    });
    edges.forEach((e) => {
      const locked = focusId !== null;
      const lit = id !== null && (focusEdges ? focusEdges.has(e.idx) : e.a === id || e.b === id);
      e.line.visible = id === null ? edgeScopeVisible(e) : (locked ? lit : true) && edgeScopeVisible(e);
      e.line.material.opacity = id === null ? e.baseOp : lit ? 0.95 : 0.04;
      e.line.material.linewidth = id !== null && lit ? e.baseW * 1.8 : e.baseW;
      e.lit = lit;
    });
  }
  const MOD_EXPAND = 1.55;
  function setExpand(focusFileId) {
    const fm = focusFileId === null ? -1 : files[focusFileId].modIdx;
    files.forEach((f) => {
      if (fm >= 0 && f.modIdx === fm && f.id !== focusFileId) {
        const m = MODULES[fm];
        f.targetX = m._cx + (f.x0 - m._cx) * MOD_EXPAND;
        f.targetZ = m._cz + (f.z0 - m._cz) * MOD_EXPAND;
      } else {
        f.targetX = f.x0;
        f.targetZ = f.z0;
      }
    });
    MODULES.forEach((m, i) => {
      m.tileTargetScale = i === fm ? MOD_EXPAND : 1;
    });
  }
  function setHelp(on2) {
    const h = $(".help"), lg = $("#cb-legend");
    if (h) {
      h.style.transition = "opacity .2s";
      h.style.opacity = on2 && !(lg && lg.classList.contains("collapsed")) ? "" : "0";
    }
  }
  function lockTarget(id) {
    elevation.resetPanelState();
    if (typeof opts.onMethodClose === "function")
      opts.onMethodClose();
    clearCameraViewOffset();
    clearPath();
    elevationId = null;
    elevation.removeElevation();
    setHelp(false);
    focusId = id;
    const f = nodeById[id];
    setExpand(null);
    buildNeighbors(id);
    applyFocus(id);
    buildRings(f);
    fillDossier(f);
    showName(f);
    const D = Math.max(50, f.height * 0.62 + 38);
    const look = new THREE2.Vector3(f.x0, Math.min(10, f.height * 0.4), f.z0);
    tweenCam(look.clone().add(new THREE2.Vector3(D * 0.42, D * 0.72, D * 0.56)), look);
  }
  function fillDossier(f) {
    if (f.isExternal) {
      const it = f.items || [], ah2 = it.length ? it.reduce((s, t) => s + t.health, 0) / it.length : 0.5;
      $("#d-name").textContent = f.name;
      $("#d-mod").textContent = (f.kind || "EXTERNAL").toUpperCase() + " · EXTERNAL";
      $("#d-loc").textContent = it.length ? it.reduce((s, t) => s + t.val, 0) : "—";
      $("#d-meth").textContent = it.length || "—";
      $("#d-fin").textContent = f.fanIn;
      $("#d-fout").textContent = f.fanOut;
      $("#d-cov").textContent = "—";
      const pips2 = Math.round(ah2 * 5);
      $("#d-health").textContent = f.isExternal && !(f.items || []).length || f.methods?.every((m) => m.health == null) ? "—" : "●".repeat(pips2) + "○".repeat(5 - pips2);
      const hb2 = $("#d-healthbar");
      hb2.style.width = it.length ? Math.round(ah2 * 100) + "%" : "0%";
      hb2.style.background = "#" + healthColor(ah2).getHexString();
      hb2.style.boxShadow = "0 0 8px #" + healthColor(ah2).getHexString();
      dossier.classList.add("on");
      return;
    }
    const ah = f.unknownHealth ? 0.5 : avgHealth(f);
    $("#d-name").textContent = f.name;
    $("#d-mod").textContent = f.module;
    $("#d-loc").textContent = f.loc == null ? "—" : f.loc;
    $("#d-meth").textContent = f.symbolsUnavailable ? "—" : f.methods.length;
    $("#d-fin").textContent = f.fanIn;
    $("#d-fout").textContent = f.fanOut;
    $("#d-cov").textContent = f.coverage == null ? "—" : Math.round(f.coverage * 100) + "%";
    const pips = Math.round(ah * 5);
    $("#d-health").textContent = f.isExternal && !(f.items || []).length || f.methods?.every((m) => m.health == null) ? "—" : "●".repeat(pips) + "○".repeat(5 - pips);
    const hb = $("#d-healthbar");
    hb.style.width = f.unknownHealth ? "0%" : Math.round(ah * 100) + "%";
    hb.style.background = "#" + healthColor(ah).getHexString();
    hb.style.boxShadow = "0 0 8px #" + healthColor(ah).getHexString();
    dossier.classList.add("on");
  }
  const focusState = {
    getFocusId: () => focusId,
    setFocusId: (id) => {
      focusId = id;
    },
    getElevationId: () => elevationId,
    setElevationId: (id) => {
      elevationId = id;
    }
  };
  let boardTapHandler = null;
  const elevation = createCyberboardElevation({
    THREE: THREE2,
    opts,
    root,
    $,
    W,
    H,
    on,
    scene,
    camera,
    controls,
    edges,
    nodeById,
    KCFG,
    PILLAR_W,
    COL,
    healthColor,
    markerRingColor,
    markerRingOpacity,
    syncTag,
    clearCameraViewOffset,
    setCameraViewOffsetPixels,
    getCameraViewOffset,
    tweenCam,
    isTweening,
    state: focusState,
    setHelp,
    clearPath,
    clearNeighbors,
    setExpand,
    applyFocus,
    removeRings,
    fillDossier,
    showName,
    getBoardTap: () => boardTapHandler
  });
  const nameDiv = document.createElement("div");
  nameDiv.className = "lbl filename";
  const nameLabel = new CSS2DObject2(nameDiv);
  nameLabel.visible = false;
  scene.add(nameLabel);
  function showName(f) {
    nameDiv.textContent = f.name;
    nameLabel.position.set(f.x0, f.height + 4, f.z0);
    nameLabel.visible = true;
  }
  function hideName() {
    nameLabel.visible = false;
  }
  function buildNeighbors(id) {
    clearNeighbors();
    const ctx2 = focusContextFor(id);
    focusEdges = ctx2.edges;
    focusNeighbors = new Set([...ctx2.nodes].filter((nid) => nid !== id));
    neighborGroup = new THREE2.Group;
    scene.add(neighborGroup);
    focusNeighbors.forEach((nid) => {
      const n = nodeById[nid];
      if (!n)
        return;
      const px = n.x0 ?? n.x, pz = n.z0 ?? n.z, ph = n.height || 6;
      const d = document.createElement("div");
      d.className = "lbl neighbor";
      d.textContent = n.name;
      const o = new CSS2DObject2(d);
      o.position.set(px, ph + 2.6, pz);
      neighborGroup.add(o);
      if (n.isExternal && n.mat)
        n.mat.emissiveIntensity = 1.2;
    });
  }
  function clearNeighbors() {
    focusNeighbors = null;
    focusEdges = null;
    if (neighborGroup) {
      scene.remove(neighborGroup);
      neighborGroup.traverse((o) => {
        if (o.element && o.element.parentNode)
          o.element.parentNode.removeChild(o.element);
      });
      neighborGroup = null;
    }
    exts.forEach((x) => {
      if (x.mat)
        x.mat.emissiveIntensity = 0.5;
    });
  }
  const inEdges = {};
  [...files, ...exts].forEach((n) => inEdges[n.id] = []);
  edges.forEach((e) => inEdges[e.b].push(e));
  function traceRank(e, dir) {
    const n = nodeById[dir === "in" ? e.a : e.b];
    let r = e.payload || 1;
    if (!e.hiddenByScope)
      r += 1000;
    if (nodeLooksEntry(n))
      r += 650;
    if (e.io)
      r += dir === "out" ? 160 : 30;
    if (e.type === "call")
      r += 80;
    return r;
  }
  function bestTraceEdge(list, dir, seen) {
    return (list || []).filter((e) => {
      if (edgeTypeOn[e.type] === false || e.hiddenByScope)
        return false;
      const next = dir === "in" ? e.a : e.b;
      return !seen.has(next);
    }).sort((a, b) => traceRank(b, dir) - traceRank(a, dir))[0] || null;
  }
  function focusContextFor(id) {
    const nodes = new Set([id]), es = new Set;
    const add = (e) => {
      if (!e)
        return;
      es.add(e.idx);
      nodes.add(e.a);
      nodes.add(e.b);
    };
    edges.forEach((e) => {
      if (e.a === id || e.b === id)
        add(e);
    });
    let cur = id, seen = new Set([id]);
    for (let i = 0;i < 12; i++) {
      const e = bestTraceEdge(inEdges[cur], "in", seen);
      if (!e)
        break;
      add(e);
      cur = e.a;
      seen.add(cur);
      if (nodeLooksEntry(nodeById[cur]))
        break;
    }
    cur = id;
    seen = new Set([id]);
    for (let i = 0;i < 12; i++) {
      const e = bestTraceEdge(outEdges[cur], "out", seen);
      if (!e)
        break;
      add(e);
      cur = e.b;
      seen.add(cur);
      if (nodeById[cur] && nodeById[cur].isExternal)
        break;
    }
    edges.forEach((e) => {
      if (!e.hiddenByScope && nodes.has(e.a) && nodes.has(e.b))
        es.add(e.idx);
    });
    es.forEach((idx) => {
      const e = edges[idx];
      if (e) {
        nodes.add(e.a);
        nodes.add(e.b);
      }
    });
    return { nodes, edges: es };
  }
  let pathEdges = null, pathGroup = null, moduleFocus = null;
  let moduleLabelGroup = null, moduleFocusFset = null;
  function syncMergeLayerVisibility() {
    const boardMode = focusId === null && elevationId === null && (pathEdges === null || moduleFocus !== null);
    mergeLayer.visible = !!(router.getMergeParallel() && boardMode);
    mergeLayer.children.forEach((mesh) => {
      const type = mesh.userData.mergeType;
      const ids = mesh.userData.mergeEdges || [];
      mesh.visible = mergeLayer.visible && edgeTypeOn[type] !== false && ids.some((idx) => contextEdgeVisible(edges[idx]));
    });
  }
  function edgePointAt(e, frac) {
    const pts = e._flowPts || e.pts || [];
    if (!pts.length)
      return new THREE2.Vector3;
    const cum = e._flowCum || e.cum, len = e._flowLen != null ? e._flowLen : e.len;
    const target = (len || 0) * frac;
    for (let i = 1;i < pts.length; i++) {
      if (cum && cum[i] >= target || i === pts.length - 1) {
        const a = pts[i - 1], b = pts[i], prev = cum ? cum[i - 1] : 0, cur = cum ? cum[i] : prev + a.distanceTo(b), seg = Math.max(0.0001, cur - prev);
        return a.clone().lerp(b, Math.max(0, Math.min(1, (target - prev) / seg)));
      }
    }
    return pts[Math.floor(pts.length / 2)].clone();
  }
  function edgeNodePayload(n) {
    if (!n)
      return null;
    return {
      id: n.id,
      name: n.name,
      path: n._path || "",
      fileId: n._fileId || "",
      module: n.module || "",
      kind: n.kind || "",
      isExternal: !!n.isExternal,
      itemLabel: n.itemLabel || "",
      unit: n.unit || "",
      fanIn: n.fanIn || 0,
      fanOut: n.fanOut || 0,
      confidence: n.confidence || "",
      sources: n.sources || [],
      signals: n.signals || [],
      sourceFiles: n.sourceFiles || [],
      connectors: n.connectors || [],
      items: n.items || []
    };
  }
  function openEdgeDetails(edge, ordered, chain) {
    if (typeof opts.onEdgeOpen !== "function")
      return;
    const src = nodeById[edge.a], dst = nodeById[edge.b];
    const chainEdges = [...chain || new Set([edge.idx])].map((idx) => edges[idx]).filter(Boolean).map((e) => ({
      idx: e.idx,
      type: e.type || "edge",
      io: !!e.io,
      rest: !!e.rest,
      payload: e.payload || 0,
      from: edgeNodePayload(nodeById[e.a]),
      to: edgeNodePayload(nodeById[e.b])
    }));
    try {
      opts.onEdgeOpen({
        edge: { idx: edge.idx, type: edge.type || "edge", io: !!edge.io, rest: !!edge.rest, trunk: !!edge.trunk, payload: edge.payload || 0, len: edge.len || 0 },
        from: edgeNodePayload(src),
        to: edgeNodePayload(dst),
        ordered: (ordered || []).map((id) => edgeNodePayload(nodeById[id])).filter(Boolean),
        chain: chainEdges
      });
    } catch (e) {
      console.error("[cyberboard] onEdgeOpen failed", e);
    }
  }
  function highlightPath(edge) {
    release();
    const src = nodeById[edge.a], dst = nodeById[edge.b];
    const chain = new Set([edge.idx]);
    const back = [edge.a];
    let cur = edge.a, g = 0;
    while (g++ < 24) {
      const pe = bestTraceEdge(inEdges[cur], "in", new Set(back));
      if (!pe)
        break;
      chain.add(pe.idx);
      back.push(pe.a);
      cur = pe.a;
    }
    back.reverse();
    const fwd = [edge.b];
    cur = edge.b;
    g = 0;
    while (g++ < 24) {
      const ne = bestTraceEdge(outEdges[cur], "out", new Set(fwd));
      if (!ne)
        break;
      chain.add(ne.idx);
      fwd.push(ne.b);
      cur = ne.b;
    }
    const ordered = [...back, ...fwd], idSet = new Set(ordered);
    edges.forEach((e) => {
      if (e.hiddenByScope && idSet.has(e.a) && idSet.has(e.b))
        chain.add(e.idx);
    });
    pathEdges = chain;
    moduleFocus = null;
    setEdgeScopeReveal((e) => chain.has(e.idx));
    files.forEach((f) => {
      const on2 = idSet.has(f.id);
      f.segMats.forEach((m) => {
        m.opacity = on2 ? 1 : 0.06;
        m.emissiveIntensity = on2 ? 0.9 : 0.08;
      });
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = on2 ? 0.6 : 0.03;
      if (f.tag) {
        f._tagOpacity = on2 ? "1" : "0.12";
        syncTag(f);
      }
    });
    edges.forEach((e) => {
      const on2 = chain.has(e.idx) && edgeScopeVisible(e);
      e.line.visible = on2;
      e.line.material.opacity = on2 ? 0.98 : e.baseOp;
      e.line.material.linewidth = on2 ? e.baseW * 1.9 : e.baseW;
    });
    pathGroup = new THREE2.Group;
    scene.add(pathGroup);
    {
      const mid = edgePointAt(edge, 0.5), d = document.createElement("div");
      d.className = "lbl edgepick" + (typeof opts.onEdgeOpen === "function" ? " edgepick-click" : "");
      d.textContent = (src ? src.name : edge.a) + " -> " + (dst ? dst.name : edge.b);
      if (typeof opts.onEdgeOpen === "function") {
        const born = performance.now();
        d.title = "Click to inspect this connection";
        d.addEventListener("pointerdown", (ev) => {
          ev.stopPropagation();
        });
        d.addEventListener("click", (ev) => {
          ev.stopPropagation();
          if (performance.now() - born < 180)
            return;
          openEdgeDetails(edge, ordered, chain);
        });
      }
      const o = new CSS2DObject2(d);
      o.position.set(mid.x, mid.y + 3, mid.z);
      pathGroup.add(o);
    }
    ordered.forEach((nid, i) => {
      const n = nodeById[nid];
      if (!n)
        return;
      const px = n.x0 ?? n.x, pz = n.z0 ?? n.z, ph = n.height || 6;
      const d = document.createElement("div");
      d.className = "lbl pathstep";
      const marker = document.createElement("i");
      marker.textContent = String(i + 1);
      d.append(marker, document.createTextNode(" " + n.name));
      const o = new CSS2DObject2(d);
      o.position.set(px, ph + 3.4, pz);
      pathGroup.add(o);
    });
    $("#d-name").textContent = (src ? src.name : nodeById[ordered[0]].name) + "  ->  " + (dst ? dst.name : nodeById[ordered[ordered.length - 1]].name);
    $("#d-mod").textContent = String(edge.type || "EDGE").toUpperCase() + " · CALL PATH · " + ordered.length + " nodes · " + chain.size + " hops";
    dossier.classList.add("on");
  }
  function highlightModule(mi, showLabels) {
    release();
    const eset = new Set, fset = new Set;
    files.forEach((f) => {
      if (f.modIdx === mi)
        fset.add(f.id);
    });
    edges.forEach((e) => {
      if (e.hiddenByScope)
        return;
      const a = nodeById[e.a], b = nodeById[e.b];
      if (a.modIdx === mi || b.modIdx === mi) {
        eset.add(e.idx);
        fset.add(e.a);
        fset.add(e.b);
      }
    });
    pathEdges = eset;
    moduleFocus = mi;
    setEdgeScopeReveal(null);
    files.forEach((f) => {
      const on2 = fset.has(f.id);
      const bo = f.faded ? 0.17 : 1, be = f.faded ? 0.13 : 0.9;
      f.segMats.forEach((m) => {
        m.opacity = on2 ? bo : 0.06;
        m.emissiveIntensity = on2 ? be : 0.08;
      });
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = on2 ? f.faded ? 0.06 : 0.6 : 0.03;
      if (f.tag) {
        f._tagOpacity = on2 ? f.faded ? "0.3" : "1" : "0.12";
        syncTag(f);
      }
    });
    edges.forEach((e) => {
      const on2 = eset.has(e.idx) && edgeScopeVisible(e);
      e.line.visible = on2;
      e.line.material.opacity = on2 ? 0.96 : e.baseOp;
    });
    moduleFocusFset = fset;
    if (showLabels)
      showModuleLabels();
    $("#d-name").textContent = MODULES[mi].name;
    $("#d-mod").textContent = "MODULE · " + fset.size + " nodes · " + eset.size + " edges";
    dossier.classList.add("on");
  }
  function showModuleLabels() {
    clearModuleLabels();
    if (!moduleFocusFset)
      return;
    moduleLabelGroup = new THREE2.Group;
    scene.add(moduleLabelGroup);
    moduleFocusFset.forEach((fidp) => {
      const n = nodeById[fidp];
      if (!n)
        return;
      const px = n.x0 ?? n.x, pz = n.z0 ?? n.z, ph = n.height || 6;
      const d = document.createElement("div");
      d.className = "lbl neighbor";
      d.textContent = n.name;
      const o = new CSS2DObject2(d);
      o.position.set(px, ph + 2.6, pz);
      moduleLabelGroup.add(o);
    });
  }
  function clearModuleLabels() {
    if (!moduleLabelGroup)
      return;
    scene.remove(moduleLabelGroup);
    moduleLabelGroup.traverse((o) => {
      if (o.element && o.element.parentNode)
        o.element.parentNode.removeChild(o.element);
    });
    moduleLabelGroup = null;
  }
  function clearPath() {
    clearModuleLabels();
    if (pathEdges === null)
      return;
    pathEdges = null;
    moduleFocus = null;
    moduleFocusFset = null;
    if (pathGroup) {
      scene.remove(pathGroup);
      pathGroup.traverse((o) => {
        if (o.element && o.element.parentNode)
          o.element.parentNode.removeChild(o.element);
      });
      pathGroup = null;
    }
    applyFocus(null);
  }
  function release() {
    if (focusId === null && elevationId === null && pathEdges === null)
      return;
    elevation.resetPanelState();
    clearCameraViewOffset();
    focusId = null;
    elevationId = null;
    setExpand(null);
    clearNeighbors();
    applyFocus(null);
    removeRings();
    elevation.removeElevation();
    clearPath();
    hideName();
    dossier.classList.remove("on");
    setHelp(true);
    if (typeof opts.onMethodClose === "function")
      opts.onMethodClose();
    tweenCam(OVERVIEW_POS.clone(), OVERVIEW_LOOK.clone());
  }
  function focusFile(path) {
    const norm = (p) => String(p || "").replace(/\\/g, "/").replace(/^\.\//, "").toLowerCase();
    const want = norm(path);
    if (!want)
      return false;
    const f = files.find((f2) => norm(f2._path) === want);
    if (!f)
      return false;
    lockTarget(f.id);
    return true;
  }
  return {
    getFocusId: () => focusId,
    getElevationId: () => elevationId,
    getPathEdges: () => pathEdges,
    getModuleFocus: () => moduleFocus,
    getFocusEdges: () => focusEdges,
    hasModuleLabels: () => !!moduleLabelGroup,
    getElevSuppressClickUntil: () => elevation.getSuppressClickUntil(),
    applyFocus,
    clearModuleLabels,
    enterElevation: elevation.enterElevation,
    focusFile,
    handleWheel: elevation.handleWheel,
    highlightModule,
    highlightPath,
    lockTarget,
    openFileBadge,
    release,
    selectItem: elevation.selectItem,
    selectMethod: elevation.selectMethod,
    setBoardTapHandler: (fn) => {
      boardTapHandler = typeof fn === "function" ? fn : null;
    },
    setHelp,
    showModuleLabels,
    syncMergeLayerVisibility
  };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-input.js
function createCyberboardInput(ctx) {
  const {
    THREE: THREE2,
    root,
    renderer,
    camera,
    controls,
    W,
    H,
    on,
    pickables,
    edges,
    MODULES,
    roadHW,
    edgeTypeOn,
    contextEdgeVisible,
    focusApi,
    tweenCam,
    OVERVIEW_POS,
    OVERVIEW_LOOK
  } = ctx;
  const ray = new THREE2.Raycaster;
  const mouse = new THREE2.Vector2;
  const mousePx = new THREE2.Vector2;
  ray.params.Line2 = { threshold: 2.5 };
  let downXY = null;
  function pointerXY(e) {
    const r = renderer.domElement.getBoundingClientRect();
    mousePx.set(e.clientX - r.left, e.clientY - r.top);
    mouse.x = mousePx.x / W() * 2 - 1;
    mouse.y = -(mousePx.y / H()) * 2 + 1;
  }
  function edgeScreenPoint(v) {
    const p = v.clone().project(camera);
    return { x: (p.x + 1) * 0.5 * W(), y: (1 - p.y) * 0.5 * H(), z: p.z };
  }
  function edgePickable(e) {
    return !!(e && e.line && e.pts && e.pts.length > 1 && edgeTypeOn[e.type] !== false && contextEdgeVisible(e));
  }
  function edgePickTolerance(e) {
    return Math.max(16, Math.min(30, 12 + (e.baseW || roadHW(e)) * 22));
  }
  function pickEdgeByRay() {
    const hit = ray.intersectObjects(edges.filter(edgePickable).map((e) => e.line), false);
    if (!hit.length)
      return null;
    return edges.find((e) => e.line === hit[0].object) || null;
  }
  function pickEdgeByScreenDistance() {
    let best = null;
    let bestScore = 1;
    edges.forEach((e) => {
      if (!edgePickable(e))
        return;
      const tol = edgePickTolerance(e);
      const tol2 = tol * tol;
      for (let i = 1;i < e.pts.length; i++) {
        const a = edgeScreenPoint(e.pts[i - 1]);
        const b = edgeScreenPoint(e.pts[i]);
        if (a.z < -1 && b.z < -1 || a.z > 1 && b.z > 1)
          continue;
        const d = distSqPointSeg2(mousePx.x, mousePx.y, a.x, a.y, b.x, b.y);
        const score = d / tol2;
        if (score < bestScore) {
          bestScore = score;
          best = e;
        }
      }
    });
    return best;
  }
  function activateEdge(edge) {
    if (!edge)
      return false;
    focusApi.highlightPath(edge);
    return true;
  }
  function handleBoardTap(e) {
    pointerXY(e);
    ray.setFromCamera(mouse, camera);
    const ph = ray.intersectObjects(pickables, false);
    if (ph.length) {
      focusApi.lockTarget(ph[0].object.userData.fileId);
      return;
    }
    if (activateEdge(pickEdgeByRay()))
      return;
    if (activateEdge(pickEdgeByScreenDistance()))
      return;
    const mh = ray.intersectObjects(MODULES.map((m) => m.tileMesh), false);
    if (mh.length) {
      const mi = mh[0].object.userData.modIdx;
      const m = MODULES[mi];
      if (focusApi.getModuleFocus() === mi)
        return;
      focusApi.highlightModule(mi, false);
      const d = Math.max(46, m._half * 3.4);
      tweenCam(new THREE2.Vector3(m._cx, d * 0.92, m._cz + d * 0.68), new THREE2.Vector3(m._cx, 0, m._cz));
      return;
    }
    focusApi.release();
  }
  on(renderer.domElement, "pointerdown", (e) => {
    downXY = [e.clientX, e.clientY];
  });
  on(renderer.domElement, "pointerup", (e) => {
    if (!downXY)
      return;
    const moved = Math.hypot(e.clientX - downXY[0], e.clientY - downXY[1]);
    downXY = null;
    if (moved <= 5)
      handleBoardTap(e);
  });
  const panKeys = new Set;
  const PAN_CODE = { KeyW: "f", KeyS: "b", KeyA: "l", KeyD: "r", ArrowUp: "f", ArrowDown: "b", ArrowLeft: "l", ArrowRight: "r" };
  on(window, "keydown", (e) => {
    if (!root.isConnected)
      return;
    if (e.key === "Escape") {
      focusApi.release();
      return;
    }
    const ae = document.activeElement;
    if (ae && (ae.tagName === "INPUT" || ae.tagName === "TEXTAREA" || ae.isContentEditable))
      return;
    if (PAN_CODE[e.code]) {
      panKeys.add(PAN_CODE[e.code]);
      e.preventDefault();
    }
  });
  on(window, "keyup", (e) => {
    if (PAN_CODE[e.code])
      panKeys.delete(PAN_CODE[e.code]);
  });
  on(renderer.domElement, "dblclick", (e) => {
    pointerXY(e);
    ray.setFromCamera(mouse, camera);
    const hit = ray.intersectObjects(pickables, false);
    if (hit.length) {
      focusApi.enterElevation(hit[0].object.userData.fileId);
      return;
    }
    const mh = ray.intersectObjects(MODULES.map((m) => m.tileMesh), false);
    if (!mh.length)
      return;
    const mi = mh[0].object.userData.modIdx;
    if (focusApi.getModuleFocus() !== mi)
      focusApi.highlightModule(mi, true);
    else if (focusApi.hasModuleLabels())
      focusApi.clearModuleLabels();
    else
      focusApi.showModuleLabels();
  });
  root.querySelectorAll(".views button").forEach((b) => on(b, "click", () => {
    focusApi.release();
    const v = b.dataset.view;
    if (v === "top")
      tweenCam(new THREE2.Vector3(0, 250, 0.5), new THREE2.Vector3(0, 0, 0));
    else if (v === "iso")
      tweenCam(new THREE2.Vector3(150, 160, 150), OVERVIEW_LOOK.clone());
    else
      tweenCam(OVERVIEW_POS.clone(), OVERVIEW_LOOK.clone());
  }));
  function updatePan(dt) {
    if (!panKeys.size)
      return;
    const fwd = new THREE2.Vector3;
    camera.getWorldDirection(fwd);
    fwd.y = 0;
    if (fwd.lengthSq() < 0.000001)
      fwd.set(0, 0, -1);
    fwd.normalize();
    const rightV = new THREE2.Vector3(-fwd.z, 0, fwd.x);
    const mv = new THREE2.Vector3;
    if (panKeys.has("f"))
      mv.add(fwd);
    if (panKeys.has("b"))
      mv.sub(fwd);
    if (panKeys.has("r"))
      mv.add(rightV);
    if (panKeys.has("l"))
      mv.sub(rightV);
    if (mv.lengthSq() > 0) {
      mv.normalize().multiplyScalar(Math.max(8, camera.position.distanceTo(controls.target)) * 0.9 * dt);
      camera.position.add(mv);
      controls.target.add(mv);
    }
  }
  return { handleBoardTap, updatePan };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-router.js
function createCyberboardRouter(ctx) {
  const {
    THREE: THREE2,
    scene,
    MODULES,
    files,
    exts,
    edges,
    nodeById,
    MAX,
    COL,
    EDGE_OP,
    EDGE_COL,
    PILLAR_W,
    ROAD_Y,
    laneType,
    edgeColorHex,
    contextEdgeVisible,
    syncMergeLayerVisibility
  } = ctx;
  const getFocusId = ctx.getFocusId || (() => null);
  const getElevationId = ctx.getElevationId || (() => null);
  const getPathEdges = ctx.getPathEdges || (() => null);
  const getModuleFocus = ctx.getModuleFocus || (() => null);
  const lineMats = [];
  const GRID = 2.4, PAD = 16;
  let bMinX = Infinity, bMaxX = -Infinity, bMinZ = Infinity, bMaxZ = -Infinity;
  MODULES.forEach((m) => {
    bMinX = Math.min(bMinX, m._cx - m._half);
    bMaxX = Math.max(bMaxX, m._cx + m._half);
    bMinZ = Math.min(bMinZ, m._cz - m._half);
    bMaxZ = Math.max(bMaxZ, m._cz + m._half);
  });
  exts.forEach((x) => {
    bMinX = Math.min(bMinX, x.x);
    bMaxX = Math.max(bMaxX, x.x);
    bMinZ = Math.min(bMinZ, x.z);
    bMaxZ = Math.max(bMaxZ, x.z);
  });
  bMinX -= PAD;
  bMaxX += PAD;
  bMinZ -= PAD;
  bMaxZ += PAD;
  const NX = Math.ceil((bMaxX - bMinX) / GRID), NZ = Math.ceil((bMaxZ - bMinZ) / GRID), NC = NX * NZ;
  const w2c = (x, z) => [
    Math.min(NX - 1, Math.max(0, Math.round((x - bMinX) / GRID - 0.5))),
    Math.min(NZ - 1, Math.max(0, Math.round((z - bMinZ) / GRID - 0.5)))
  ];
  const blocked = new Uint8Array(NC);
  function blockNode(x, z, rad) {
    const [cx, cz] = w2c(x, z), r = Math.ceil(rad / GRID);
    for (let dx = -r;dx <= r; dx++)
      for (let dz = -r;dz <= r; dz++) {
        const ix = cx + dx, iz = cz + dz;
        if (ix >= 0 && iz >= 0 && ix < NX && iz < NZ && dx * dx + dz * dz <= r * r)
          blocked[ix * NZ + iz] = 1;
      }
  }
  files.forEach((f) => blockNode(f.x, f.z, PILLAR_W * 1.1 + 0.6));
  exts.forEach((x) => blockNode(x.x, x.z, 7));
  function fanout(cx, cz, px, pz) {
    const dx = Math.sign(px - cx), dz = Math.sign(pz - cz);
    const fx = Math.max(0, Math.min(NX - 1, px + dx * 2)), fz = Math.max(0, Math.min(NZ - 1, pz + dz * 2));
    return blocked[fx * NZ + fz] ? [px, pz] : [fx, fz];
  }
  const MAXPAY = MAX.payload;
  const roadHW = (e) => e.io ? 0.48 : e.trunk ? 0.46 : 0.4;
  function setFlowPath(e, pts) {
    const { cum, len } = arclen(pts);
    e._flowPts = pts;
    e._flowCum = cum;
    e._flowLen = len;
  }
  function setEdgePts(e, pts) {
    pts = simplifyPath(pts);
    const { cum, len } = arclen(pts);
    e.pts = pts;
    e.len = len;
    e.cum = cum;
    setFlowPath(e, pts);
    if (e.line.geometry)
      e.line.geometry.dispose();
    e.line.geometry = ribbonGeo(pts, e.baseW || roadHW(e));
    e._visualPaths = [pts];
  }
  function setEdgeVisualPaths(e, paths) {
    if (e.line.geometry)
      e.line.geometry.dispose();
    const clean = paths.map((p) => simplifyPath(p)).filter((p) => p.length > 1);
    e.line.geometry = multiRibbonGeo(clean, e.baseW || roadHW(e));
    e._visualPaths = clean;
    setFlowPath(e, clean.length === 1 ? clean[0] : e.pts || []);
  }
  let mergeParallel = true;
  const mergeLayer = new THREE2.Group;
  mergeLayer.visible = false;
  scene.add(mergeLayer);
  const MERGE_MIN = GRID * 2, MERGE_DIST = GRID * 3, MERGE_EPS = 0.45;
  function clearMergeLayer() {
    mergeLayer.traverse((o) => {
      if (o.geometry)
        o.geometry.dispose();
      if (o.material)
        o.material.dispose();
    });
    mergeLayer.visible = false;
    mergeLayer.clear();
  }
  function mergeSegCandidate(e, i, pts) {
    if (!pts || i <= 0 || i >= pts.length - 2)
      return null;
    const A = pts[i], B = pts[i + 1], dx = B.x - A.x, dz = B.z - A.z, t = laneType(e);
    if (Math.abs(dz) < MERGE_EPS && Math.abs(dx) >= MERGE_MIN) {
      return { e, i, type: t, axis: "H", pos: (A.z + B.z) / 2, a: Math.min(A.x, B.x), b: Math.max(A.x, B.x), hw: e.baseW || roadHW(e), y: (A.y + B.y) / 2 };
    }
    if (Math.abs(dx) < MERGE_EPS && Math.abs(dz) >= MERGE_MIN) {
      return { e, i, type: t, axis: "V", pos: (A.x + B.x) / 2, a: Math.min(A.z, B.z), b: Math.max(A.z, B.z), hw: e.baseW || roadHW(e), y: (A.y + B.y) / 2 };
    }
    return null;
  }
  function collectMergePlans() {
    const cands = [];
    edges.forEach((e) => {
      const pts = e.pts;
      if (!pts || !contextEdgeVisible(e))
        return;
      for (let i = 0;i < pts.length - 1; i++) {
        const c = mergeSegCandidate(e, i, pts);
        if (c)
          cands.push(c);
      }
    });
    const byKey = {};
    cands.forEach((c) => (byKey[c.type + "_" + c.axis] = byKey[c.type + "_" + c.axis] || []).push(c));
    const buses = [], memberBus = {}, mergedEdges = new Set;
    for (const key in byKey) {
      const list = byKey[key].sort((a, b) => a.pos - b.pos || a.a - b.a);
      const parent = list.map((_, i) => i);
      for (let i = 0;i < list.length; i++) {
        for (let j = i + 1;j < list.length && list[j].pos - list[i].pos <= MERGE_DIST; j++) {
          if (overlapLen(list[i].a, list[i].b, list[j].a, list[j].b) >= MERGE_MIN)
            unionRoot(parent, i, j);
        }
      }
      const comps = {};
      list.forEach((s, i) => (comps[findRoot(parent, i)] = comps[findRoot(parent, i)] || []).push(s));
      Object.values(comps).forEach((comp) => {
        if (comp.length < 2)
          return;
        const evts = comp.flatMap((s) => [[s.a, 1], [s.b, -1]]).sort((x, y2) => x[0] - y2[0] || y2[1] - x[1]);
        let cov = 0, peak = 0;
        evts.forEach(([, d]) => {
          cov += d;
          if (cov > peak)
            peak = cov;
        });
        if (peak < 2)
          return;
        const members = comp;
        const a = Math.min(...members.map((s) => s.a)), b = Math.max(...members.map((s) => s.b));
        if (b - a < MERGE_MIN)
          return;
        const weight = members.reduce((n, s) => n + s.hw, 0) || 1;
        const pos = members.reduce((n, s) => n + s.pos * s.hw, 0) / weight;
        const halfWidth = members.map((s) => s.hw).sort((x, y2) => y2 - x).slice(0, 3).reduce((n, w) => n + w, 0);
        const y = Math.max(...members.map((s) => s.y));
        const bus = {
          type: members[0].type,
          axis: members[0].axis,
          a,
          b,
          pos,
          halfWidth,
          y,
          edges: [...new Set(members.map((s) => s.e.idx))].sort((x, y2) => x - y2)
        };
        buses.push(bus);
        members.forEach((s) => {
          memberBus[s.e.idx + "_" + s.i] = bus;
          mergedEdges.add(s.e.idx);
        });
      });
    }
    const ABSORB_GAP = 0.6;
    let absorbed = true, guard = 0;
    while (absorbed && guard++ < 6) {
      absorbed = false;
      buses.forEach((bus) => {
        (byKey[bus.type + "_" + bus.axis] || []).forEach((s) => {
          const key = s.e.idx + "_" + s.i;
          if (memberBus[key])
            return;
          if (Math.abs(s.pos - bus.pos) > MERGE_DIST)
            return;
          if (Math.max(bus.a - s.b, s.a - bus.b) > ABSORB_GAP)
            return;
          memberBus[key] = bus;
          mergedEdges.add(s.e.idx);
          if (!bus.edges.includes(s.e.idx))
            bus.edges.push(s.e.idx);
          bus.a = Math.min(bus.a, s.a);
          bus.b = Math.max(bus.b, s.b);
          absorbed = true;
        });
      });
    }
    const snapOf = {};
    buses.forEach((bus) => {
      let a = Infinity, b = -Infinity;
      (bus.edges || []).forEach((idx) => {
        const e = edges[idx];
        if (!e)
          return;
        const sp = snapOf[idx] || (snapOf[idx] = edgeSnappedPath(e, memberBus));
        for (let i = 1;i < sp.length; i++) {
          const A = sp[i - 1], B = sp[i];
          const ax = Math.abs(A.z - B.z) < 0.05 ? "H" : Math.abs(A.x - B.x) < 0.05 ? "V" : null;
          if (ax !== bus.axis)
            continue;
          const p = ax === "H" ? A.z : A.x;
          if (Math.abs(p - bus.pos) > 0.2)
            continue;
          const lo = Math.min(ax === "H" ? A.x : A.z, ax === "H" ? B.x : B.z), hi = Math.max(ax === "H" ? A.x : A.z, ax === "H" ? B.x : B.z);
          a = Math.min(a, lo);
          b = Math.max(b, hi);
        }
      });
      if (isFinite(a)) {
        bus.a = a;
        bus.b = b;
      }
    });
    return { buses, memberBus, mergedEdges };
  }
  function edgeSnappedPath(e, memberBus) {
    const pts = e.pts.map((p) => p.clone());
    for (let i = 0;i < pts.length - 1; i++) {
      const bus = memberBus[e.idx + "_" + i];
      if (!bus)
        continue;
      if (bus.axis === "H") {
        pts[i].z = bus.pos;
        pts[i + 1].z = bus.pos;
      } else {
        pts[i].x = bus.pos;
        pts[i + 1].x = bus.pos;
      }
    }
    return simplifyPath(pts);
  }
  function renderMergeBus(bus) {
    const pts = bus.axis === "H" ? [new THREE2.Vector3(bus.a, bus.y, bus.pos), new THREE2.Vector3(bus.b, bus.y, bus.pos)] : [new THREE2.Vector3(bus.pos, bus.y, bus.a), new THREE2.Vector3(bus.pos, bus.y, bus.b)];
    const mat = new THREE2.MeshBasicMaterial({ color: EDGE_COL[bus.type], transparent: true, opacity: 0.96, side: THREE2.DoubleSide, depthWrite: false, depthTest: true });
    const mesh = new THREE2.Mesh(ribbonGeo(pts, bus.halfWidth || roadHW({ type: bus.type })), mat);
    mesh.renderOrder = 4;
    mesh.userData = { mergeType: bus.type, mergeEdges: bus.edges || [] };
    mergeLayer.add(mesh);
  }
  function renderEdgeRoutes() {
    clearMergeLayer();
    edges.forEach((e) => {
      if (e.pts)
        setEdgePts(e, e.pts);
    });
    if (!mergeParallel)
      return;
    if (getFocusId() !== null || getElevationId() !== null)
      return;
    if (getPathEdges() !== null && getModuleFocus() === null)
      return;
    const plans = collectMergePlans();
    plans.mergedEdges.forEach((idx) => {
      const e = edges[idx];
      if (e)
        setEdgeVisualPaths(e, [edgeSnappedPath(e, plans.memberBus)]);
    });
    plans.buses.sort((a, b) => a.type.localeCompare(b.type) || a.axis.localeCompare(b.axis) || a.pos - b.pos || a.a - b.a).forEach(renderMergeBus);
    syncMergeLayerVisibility();
  }
  edges.forEach((e, i) => e.idx = i);
  const HALF = Math.max(...MODULES.map((m) => m._half)), CHM = 14;
  const SNAP = 4, snap = (v) => Math.round(v / SNAP) * SNAP;
  const _uniq = (vals) => [...new Set(vals.map((v) => Math.round(v)))].sort((a, b) => a - b);
  const _channels = (centers) => {
    const m = HALF + CHM, out = [centers[0] - m];
    for (let i = 0;i < centers.length - 1; i++)
      out.push((centers[i] + centers[i + 1]) / 2);
    out.push(centers[centers.length - 1] + m);
    return out;
  };
  const Vx = _channels(_uniq(MODULES.map((m) => m._cx))).map(snap);
  const Hz = _channels(_uniq(MODULES.map((m) => m._cz))).map(snap);
  const nearestIdx = (arr, v) => {
    let bi = 0, bd = Infinity;
    for (let i = 0;i < arr.length; i++) {
      const d = Math.abs(arr[i] - v);
      if (d < bd) {
        bd = d;
        bi = i;
      }
    }
    return bi;
  };
  function attach(n) {
    const hi = nearestIdx(Hz, n.z), vi = nearestIdx(Vx, n.x);
    return Math.abs(Vx[vi] - n.x) < Math.abs(Hz[hi] - n.z) ? { axis: "V", x: Vx[vi], z: n.z } : { axis: "H", x: n.x, z: Hz[hi] };
  }
  function connect(A, B) {
    if (A.axis === "H" && B.axis === "H") {
      if (Math.abs(A.z - B.z) < 0.5)
        return [[A.x, A.z], [B.x, B.z]];
      const vt = Vx[nearestIdx(Vx, (A.x + B.x) / 2)];
      return [[A.x, A.z], [vt, A.z], [vt, B.z], [B.x, B.z]];
    }
    if (A.axis === "V" && B.axis === "V") {
      if (Math.abs(A.x - B.x) < 0.5)
        return [[A.x, A.z], [B.x, B.z]];
      const ht = Hz[nearestIdx(Hz, (A.z + B.z) / 2)];
      return [[A.x, A.z], [A.x, ht], [B.x, ht], [B.x, B.z]];
    }
    if (A.axis === "H" && B.axis === "V")
      return [[A.x, A.z], [B.x, A.z], [B.x, B.z]];
    return [[A.x, A.z], [A.x, B.z], [B.x, B.z]];
  }
  function refreshEdgePoly(e) {
    const a = nodeById[e.a], b = nodeById[e.b];
    if (!a.isExternal && !b.isExternal && a.modIdx === b.modIdx) {
      if (Math.abs(a.x - b.x) >= Math.abs(a.z - b.z)) {
        if (Math.abs(a.z - b.z) < 0.5) {
          e._poly = [[a.x, a.z], [b.x, b.z]];
          e._axA = "H";
          e._axB = "H";
          return;
        }
        const mx = snap((a.x + b.x) / 2);
        e._poly = [[a.x, a.z], [mx, a.z], [mx, b.z], [b.x, b.z]];
        e._axA = "V";
        e._axB = "V";
      } else {
        if (Math.abs(a.x - b.x) < 0.5) {
          e._poly = [[a.x, a.z], [b.x, b.z]];
          e._axA = "V";
          e._axB = "V";
          return;
        }
        const mz = snap((a.z + b.z) / 2);
        e._poly = [[a.x, a.z], [a.x, mz], [b.x, mz], [b.x, b.z]];
        e._axA = "H";
        e._axB = "H";
      }
      return;
    }
    const A = attach(a), B = attach(b);
    e._poly = [[a.x, a.z], ...connect(A, B), [b.x, b.z]];
    e._axA = A.axis;
    e._axB = B.axis;
  }
  edges.forEach(refreshEdgePoly);
  let lineUse = {};
  function rebuildLineUse() {
    lineUse = {};
    edges.forEach((e) => {
      const p = e._poly;
      if (!p)
        return;
      for (let i = 1;i < p.length - 2; i++) {
        const horiz = Math.abs(p[i][1] - p[i + 1][1]) < 0.5;
        const key = horiz ? "H" + Math.round(p[i][1]) : "V" + Math.round(p[i][0]);
        const a = horiz ? Math.min(p[i][0], p[i + 1][0]) : Math.min(p[i][1], p[i + 1][1]);
        const b = horiz ? Math.max(p[i][0], p[i + 1][0]) : Math.max(p[i][1], p[i + 1][1]);
        (lineUse[key] = lineUse[key] || []).push({ e, i, a, b });
      }
    });
  }
  const MARGIN = 2;
  function corridorZ(cz) {
    let lo = -1e9, hi = 1e9;
    MODULES.forEach((m) => {
      const a = m._cz - m._half, b = m._cz + m._half;
      if (b <= cz + 0.5)
        lo = Math.max(lo, b);
      if (a >= cz - 0.5)
        hi = Math.min(hi, a);
    });
    return [lo + MARGIN, hi - MARGIN];
  }
  function corridorX(cx) {
    let lo = -1e9, hi = 1e9;
    MODULES.forEach((m) => {
      const a = m._cx - m._half, b = m._cx + m._half;
      if (b <= cx + 0.5)
        lo = Math.max(lo, b);
      if (a >= cx - 0.5)
        hi = Math.min(hi, a);
    });
    return [lo + MARGIN, hi - MARGIN];
  }
  let MINGAP = 1;
  const lane = {}, spOf = {};
  const TW = 0.48;
  const TYPE_LANE_GAP = GRID * 2;
  const TYPE_ORDER = ["inherit", "import", "call", "io", "local"];
  function assignLanes() {
    rebuildLineUse();
    for (const k in lane)
      delete lane[k];
    for (const k in spOf)
      delete spOf[k];
    for (const k in lineUse) {
      const recs = lineUse[k].slice().sort((a, b) => a.a - b.a || a.b - b.b || String(a.e.type).localeCompare(String(b.e.type)) || a.e.idx - b.e.idx);
      let n;
      if (mergeParallel) {
        const present = [...new Set(recs.map((r) => laneType(r.e)))].sort((a, b) => TYPE_ORDER.indexOf(a) - TYPE_ORDER.indexOf(b));
        const slotOf = {};
        present.forEach((t, i) => slotOf[t] = i);
        recs.forEach((r) => r.slot = slotOf[laneType(r.e)]);
        n = Math.max(1, present.length);
      } else {
        const slots = [];
        recs.forEach((r) => {
          let slot = -1;
          for (let i = 0;i < slots.length; i++) {
            const s = slots[i];
            if (s.end >= r.a - 0.5)
              continue;
            if (s.type !== r.e.type && s.end > r.a - TYPE_LANE_GAP)
              continue;
            slot = i;
            break;
          }
          if (slot < 0) {
            slot = slots.length;
            slots.push({ end: r.b, type: r.e.type });
          } else {
            slots[slot].end = r.b;
            slots[slot].type = r.e.type;
          }
          r.slot = slot;
        });
        n = Math.max(1, slots.length);
      }
      const horiz = k[0] === "H", center = parseInt(k.slice(1)), cor = horiz ? corridorZ(center) : corridorX(center);
      const target = 2 * TW + MINGAP, sp = n > 1 ? Math.min(target, (cor[1] - cor[0]) / (n + 1)) : target;
      spOf[k] = sp;
      recs.forEach((r) => lane[r.e.idx + "_" + r.i + "_" + k] = Math.max(cor[0] - center, Math.min(cor[1] - center, (r.slot - (n - 1) / 2) * sp)));
    }
  }
  function widths() {
    edges.forEach((e) => {
      const p = e._poly;
      if (!p) {
        e._hw = roadHW(e);
        e._cap = null;
        e.baseW = e._hw;
        return;
      }
      let cap = Infinity;
      for (let i = 1;i < p.length - 2; i++) {
        const horiz = Math.abs(p[i][1] - p[i + 1][1]) < 0.5, k = horiz ? "H" + Math.round(p[i][1]) : "V" + Math.round(p[i][0]);
        if (spOf[k] != null)
          cap = Math.min(cap, spOf[k]);
      }
      e._cap = cap;
      e._hw = Math.min(roadHW(e), isFinite(cap) ? Math.max(0.12, (cap - MINGAP) / 2) : roadHW(e));
      e.baseW = e._hw;
    });
  }
  assignLanes();
  widths();
  const portList = {};
  edges.forEach((e) => {
    if (!e._poly)
      return;
    (portList[e.a] = portList[e.a] || []).push([e, "a"]);
    (portList[e.b] = portList[e.b] || []).push([e, "b"]);
  });
  for (const fidp in portList)
    portList[fidp].sort((p, q) => {
      const op = p[1] === "a" ? nodeById[p[0].b] : nodeById[p[0].a], oq = q[1] === "a" ? nodeById[q[0].b] : nodeById[q[0].a];
      return op.x - oq.x;
    });
  const portOff = {}, PCL = 4.5;
  function assignPorts() {
    const PSP = 2 * TW + MINGAP;
    for (const fidp in portList) {
      const lst = portList[fidp], n = lst.length;
      lst.forEach(([e, end], i) => portOff[e.idx + "_" + end] = Math.max(-PCL, Math.min(PCL, (i - (n - 1) / 2) * PSP)));
    }
  }
  assignPorts();
  const ELB = 5;
  function edgePts(e) {
    e.y = ROAD_Y + (e.io ? 0.1 : e.trunk ? 0.06 : 0.02);
    const a = nodeById[e.a], b = nodeById[e.b], p = e._poly;
    if (!p)
      return [new THREE2.Vector3(a.x, e.y, a.z), new THREE2.Vector3(b.x, e.y, b.z)];
    if (p.length < 4)
      return simplifyPath(p.map((c) => new THREE2.Vector3(c[0], e.y, c[1])));
    const oA = portOff[e.idx + "_a"] || 0, oB = portOff[e.idx + "_b"] || 0, L = p.length;
    const q = [];
    for (let i = 0;i < L; i++) {
      let x = p[i][0], z = p[i][1];
      for (const j of [i - 1, i]) {
        if (j < 1 || j > L - 3)
          continue;
        const horiz = Math.abs(p[j][1] - p[j + 1][1]) < 0.5;
        if (horiz)
          z = p[i][1] + (lane[e.idx + "_" + j + "_H" + Math.round(p[j][1])] || 0);
        else
          x = p[i][0] + (lane[e.idx + "_" + j + "_V" + Math.round(p[j][0])] || 0);
      }
      q.push([x, z]);
    }
    const stub = (pin, att, off, axis) => {
      if (axis === "H") {
        const dir2 = Math.sign(att[1] - pin[1]) || 1, el2 = Math.min(ELB, Math.abs(att[1] - pin[1]) * 0.5), fx = pin[0] + off;
        return [[pin[0], pin[1]], [fx, pin[1] + dir2 * el2], [fx, att[1]]];
      }
      const dir = Math.sign(att[0] - pin[0]) || 1, el = Math.min(ELB, Math.abs(att[0] - pin[0]) * 0.5), fz = att[1] + off;
      return [[pin[0], pin[1]], [pin[0] + dir * el, fz], [att[0], fz]];
    };
    const A = stub(q[0], q[1], oA, e._axA), B = stub(q[L - 1], q[L - 2], oB, e._axB);
    const raw = [...A, ...q.slice(2, L - 2), ...B.slice().reverse()];
    return simplifyPath(raw.map((c) => new THREE2.Vector3(c[0], e.y, c[1])));
  }
  edges.forEach((e) => {
    const mat = new THREE2.MeshBasicMaterial({ color: edgeColorHex(e), transparent: true, opacity: e.io ? EDGE_OP.io : e.trunk ? EDGE_OP.trunk : EDGE_OP.local, side: THREE2.DoubleSide, depthWrite: false, depthTest: true });
    const mesh = new THREE2.Mesh(new THREE2.BufferGeometry, mat);
    scene.add(mesh);
    mesh.renderOrder = 3;
    mesh.visible = !e.hiddenByScope;
    Object.assign(e, { line: mesh, baseOp: mat.opacity, baseW: e._hw || roadHW(e) });
  });
  function deoverlap() {
    if (mergeParallel || edges.length > 300) {
      renderEdgeRoutes();
      return;
    }
    const DG = Math.min(MINGAP, 1.2);
    for (let pass = 0;pass < 6; pass++) {
      const segs = [];
      edges.forEach((e) => {
        const p = e.pts;
        if (!p || p.length < 2)
          return;
        for (let i = 1;i < p.length - 2; i++) {
          const A = p[i], B = p[i + 1];
          if (Math.abs(A.x - B.x) < 0.4 && Math.abs(A.z - B.z) > 1.2)
            segs.push({ axis: "V", p, i, hw: e.baseW || roadHW(e) });
          else if (Math.abs(A.z - B.z) < 0.4 && Math.abs(A.x - B.x) > 1.2)
            segs.push({ axis: "H", p, i, hw: e.baseW || roadHW(e) });
        }
      });
      let moved = false;
      for (const axis of ["V", "H"]) {
        const co = axis === "V" ? "x" : "z", sp = axis === "V" ? "z" : "x";
        const list = segs.filter((s) => s.axis === axis).map((s) => {
          const A = s.p[s.i], B = s.p[s.i + 1];
          s.pos = A[co];
          s.a = Math.min(A[sp], B[sp]);
          s.b = Math.max(A[sp], B[sp]);
          return s;
        }).sort((s, t) => s.pos - t.pos);
        const placed = [];
        for (const s of list) {
          let np = s.pos, g = 0, m = true;
          while (m && g++ < 60) {
            m = false;
            for (const q of placed) {
              if (s.b < q.a - 0.1 || s.a > q.b + 0.1)
                continue;
              const need = s.hw + q.hw + DG;
              if (Math.abs(np - q.pos) < need - 0.05) {
                np = q.pos + (np >= q.pos ? need : -need);
                m = true;
              }
            }
          }
          if (Math.abs(np - s.pos) > 0.01)
            moved = true;
          s.p[s.i][co] = np;
          s.p[s.i + 1][co] = np;
          s.pos = np;
          placed.push(s);
        }
      }
      if (!moved)
        break;
    }
    renderEdgeRoutes();
  }
  function relayout() {
    edges.forEach(refreshEdgePoly);
    assignLanes();
    assignPorts();
    widths();
    edges.forEach((e) => {
      e.baseW = e._hw;
      e.pts = edgePts(e);
    });
    deoverlap();
  }
  const _mergeDefault = mergeParallel;
  mergeParallel = false;
  relayout();
  mergeParallel = _mergeDefault;
  function rerouteLiveEdges() {
    edges.forEach(refreshEdgePoly);
    assignLanes();
    assignPorts();
    widths();
    edges.forEach((e) => {
      e.baseW = e._hw;
      setEdgePts(e, edgePts(e));
    });
    renderEdgeRoutes();
  }
  function setGap(g) {
    MINGAP = g;
    relayout();
  }
  return {
    lineMats,
    mergeLayer,
    roadHW,
    setEdgePts,
    renderEdgeRoutes,
    relayout,
    rerouteLiveEdges,
    setGap,
    getMergeParallel: () => mergeParallel,
    setMergeParallel(value) {
      mergeParallel = !!value;
    },
    toggleMergeParallel() {
      mergeParallel = !mergeParallel;
      return mergeParallel;
    }
  };
}

// ../../../../private/var/folders/vf/n8_5k0wj3md7j3g9_p_klfcm0000gn/T/tmp.lxlXY0NJQh/cyberboard/cb-core.js
function createCyberboard(container, opts = {}) {
  container.innerHTML = CYBERBOARD_TEMPLATE;
  const root = container.querySelector(".cb-root");
  const $ = (s) => root.querySelector(s);
  const W = () => root.clientWidth || 1, H = () => root.clientHeight || 1;
  const cleanups = [];
  const on = (target, type, fn, optsL) => {
    target.addEventListener(type, fn, optsL);
    cleanups.push(() => target.removeEventListener(type, fn, optsL));
  };
  let bootHold = !!opts.loading;
  let bootT = 0;
  function scheduleBootFade(delay = 700) {
    clearTimeout(bootT);
    bootT = setTimeout(() => {
      const b = $("#boot");
      if (b && !bootHold)
        b.classList.add("gone");
    }, delay);
  }
  function setLoading(loading) {
    bootHold = !!loading;
    const b = $("#boot");
    if (!b)
      return;
    if (bootHold) {
      clearTimeout(bootT);
      b.classList.remove("gone");
    } else {
      scheduleBootFade(260);
    }
  }
  const { COL, lightScene, EDGE_OP, C_GOOD, C_WARN, C_BAD, EDGE_COL, REQ_COL, RES_COL, WRITE_COL, DEL_COL } = resolveCyberboardPalette({ THREE: THREE2, root, colorLuma });
  const laneType = (e) => e.local ? "local" : e.type;
  const edgeColorHex = (e) => e.local ? EDGE_COL.local : EDGE_COL[e.type] || EDGE_COL.import;
  function healthColor(h) {
    const c = new THREE2.Color;
    if (h > 0.5)
      c.lerpColors(C_WARN, C_GOOD, (h - 0.5) * 2);
    else
      c.lerpColors(C_BAD, C_WARN, h * 2);
    return c;
  }
  const HEIGHT_PER_LOC = 0.085, SEG_GAP = 0.45, PILLAR_W = 2.6;
  const SEG_SOFT_LOC = 100, SEG_COMPRESS_K = 600;
  const segHeight = (loc) => {
    const L = Math.max(0, Number(loc) || 0);
    const eff = L <= SEG_SOFT_LOC ? L : SEG_SOFT_LOC + (L - SEG_SOFT_LOC) / (1 + (L - SEG_SOFT_LOC) / SEG_COMPRESS_K);
    return eff * HEIGHT_PER_LOC;
  };
  const FILE_SPACING = 16, TILE_SPACING = 88, MOD_COLS = 3, ROAD_Y = 0.18;
  const KCFG = {
    db: { label: "TABLES", unit: "rows", geo: "cyl", vr: [20, 200], hs: 0.03 },
    ts: { label: "SERIES", unit: "pts", geo: "cyl", vr: [50, 500], hs: 0.012 },
    cache: { label: "KEYSETS", unit: "keys", geo: "cyl", vr: [300, 4000], hs: 0.0013 },
    cloud: { label: "FILES", unit: "KB", geo: "box", vr: [50, 900], hs: 0.006 },
    fs: { label: "FILES", unit: "KB", geo: "box", vr: [10, 400], hs: 0.009 },
    queue: { label: "TOPICS", unit: "msg/s", geo: "cyl", vr: [1, 200], hs: 0.04 },
    logs: { label: "STREAMS", unit: "l/s", geo: "box", vr: [1, 500], hs: 0.02 },
    api: { label: "ENDPOINTS", unit: "req/s", geo: "box", vr: [1, 300], hs: 0.02 }
  };
  const _src = opts && opts.data && Array.isArray(opts.data.files) && opts.data.files.length ? opts.data : buildDemoData({ HEIGHT_PER_LOC, SEG_GAP, FILE_SPACING, TILE_SPACING, MOD_COLS, KCFG, showDocs: opts.showDocs === true });
  const { MODULES, files, edges } = _src, exts = _src.exts || [];
  const agent = _src.agent || null;
  const nodeById = {};
  files.forEach((f) => nodeById[f.id] = f);
  exts.forEach((x) => nodeById[x.id] = x);
  edges.forEach((e) => {
    const a = nodeById[e.a], b = nodeById[e.b];
    e.local = !!(a && b && !a.isExternal && !b.isExternal && a.modIdx === b.modIdx && a.modIdx >= 0);
  });
  const _scaleFiles = files.filter((f) => !f.isDoc).length ? files.filter((f) => !f.isDoc) : files;
  const MAX = {
    loc: Math.max(1, ..._scaleFiles.map((f) => f.loc)),
    meth: Math.max(1, ..._scaleFiles.map((f) => f.methods.length)),
    fan: Math.max(...files.map((f) => f.fanIn + f.fanOut)) || 1,
    payload: Math.max(1, ...edges.map((e) => e.payload)) || 1
  };
  let _bx0 = Infinity, _bx1 = -Infinity, _bz0 = Infinity, _bz1 = -Infinity;
  MODULES.forEach((m) => {
    _bx0 = Math.min(_bx0, m._cx - m._half);
    _bx1 = Math.max(_bx1, m._cx + m._half);
    _bz0 = Math.min(_bz0, m._cz - m._half);
    _bz1 = Math.max(_bz1, m._cz + m._half);
  });
  exts.forEach((x) => {
    const xx = x.x0 ?? x.x, zz = x.z0 ?? x.z;
    _bx0 = Math.min(_bx0, xx);
    _bx1 = Math.max(_bx1, xx);
    _bz0 = Math.min(_bz0, zz);
    _bz1 = Math.max(_bz1, zz);
  });
  if (!isFinite(_bx0)) {
    _bx0 = -130;
    _bx1 = 130;
    _bz0 = -90;
    _bz1 = 90;
  }
  const _bcx = (_bx0 + _bx1) / 2, _bcz = (_bz0 + _bz1) / 2, _bspan = Math.max(_bx1 - _bx0, _bz1 - _bz0, 120);
  const app = root.querySelector(".cb-app");
  const scene = new THREE2.Scene;
  scene.background = new THREE2.Color(COL.bg);
  scene.fog = new THREE2.FogExp2(COL.bg, Math.min(lightScene ? 0.0018 : 0.0035, (lightScene ? 0.45 : 0.9) / _bspan));
  const camera = new THREE2.PerspectiveCamera(50, W() / H(), 0.5, Math.max(2000, _bspan * 8));
  const OVERVIEW_POS = new THREE2.Vector3(_bcx, _bspan * 0.62, _bcz + _bspan * 0.46);
  const OVERVIEW_LOOK = new THREE2.Vector3(_bcx, 0, _bcz + 4);
  camera.position.copy(OVERVIEW_POS);
  let _cameraViewOffset = null;
  function applyCameraProjection() {
    const w = W(), h = H();
    camera.aspect = w / h;
    if (_cameraViewOffset)
      camera.setViewOffset(w, h, _cameraViewOffset.x * w, _cameraViewOffset.y * h, w, h);
    else
      camera.clearViewOffset();
    camera.updateProjectionMatrix();
  }
  function setCameraViewOffsetPixels(x, y) {
    const w = W(), h = H();
    if (w < 2 || h < 2)
      return;
    _cameraViewOffset = { x: x / w, y: y / h };
    applyCameraProjection();
  }
  function clearCameraViewOffset() {
    _cameraViewOffset = null;
    camera.clearViewOffset();
    camera.updateProjectionMatrix();
  }
  const renderer = new THREE2.WebGLRenderer({ antialias: true, alpha: false });
  renderer.setClearColor(COL.bg, 1);
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setSize(W(), H());
  app.appendChild(renderer.domElement);
  const labelRenderer = new CSS2DRenderer;
  labelRenderer.setSize(W(), H());
  labelRenderer.domElement.id = "labels";
  labelRenderer.domElement.style.pointerEvents = "none";
  labelRenderer.domElement.style.position = "absolute";
  labelRenderer.domElement.style.top = "0";
  labelRenderer.domElement.style.left = "0";
  labelRenderer.domElement.style.zIndex = "55";
  app.appendChild(labelRenderer.domElement);
  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.target.copy(OVERVIEW_LOOK);
  controls.maxPolarAngle = Math.PI * 0.49;
  scene.add(new THREE2.AmbientLight(COL.ambient, lightScene ? 0.78 : 0.6));
  const key = new THREE2.DirectionalLight(COL.key, lightScene ? 0.92 : 0.8);
  key.position.set(40, 120, 60);
  scene.add(key);
  const rim = new THREE2.PointLight(COL.cyan, lightScene ? 0.28 : 0.5, 400);
  rim.position.set(-60, 40, -40);
  scene.add(rim);
  const _G = Math.max(420, _bspan * 1.7);
  const grid = new THREE2.GridHelper(_G, Math.max(40, Math.round(_G / 5)), COL.grid, COL.grid);
  (Array.isArray(grid.material) ? grid.material : [grid.material]).forEach((m) => {
    m.opacity = lightScene ? 0.55 : 0.32;
    m.transparent = true;
  });
  grid.position.set(_bcx, 0, _bcz);
  scene.add(grid);
  const floor = new THREE2.Mesh(new THREE2.PlaneGeometry(_G, _G), new THREE2.MeshBasicMaterial({ color: COL.floor }));
  floor.rotation.x = -Math.PI / 2;
  floor.position.set(_bcx, -0.02, _bcz);
  scene.add(floor);
  function makeLabel(text, cls, x, y, z) {
    const d = document.createElement("div");
    d.className = "lbl " + cls;
    d.textContent = text;
    const o = new CSS2DObject3(d);
    o.position.set(x, y, z);
    scene.add(o);
    return o;
  }
  MODULES.forEach((mod, mi) => {
    const s = mod._half * 2;
    const geo = new THREE2.PlaneGeometry(s, s);
    const m = new THREE2.Mesh(geo, new THREE2.MeshBasicMaterial({ color: COL.tile, transparent: true, opacity: lightScene ? 0.82 : 0.35 }));
    m.renderOrder = 0;
    m.rotation.x = -Math.PI / 2;
    m.position.set(mod._cx, 0, mod._cz);
    scene.add(m);
    const edge = new THREE2.LineSegments(new THREE2.EdgesGeometry(geo), new THREE2.LineBasicMaterial({ color: COL.tileLine, transparent: true, opacity: lightScene ? 0.72 : 0.6 }));
    edge.renderOrder = 1;
    edge.rotation.x = -Math.PI / 2;
    edge.position.set(mod._cx, 0.03, mod._cz);
    scene.add(edge);
    mod.tileMesh = m;
    m.userData.modIdx = mi;
    mod.tileEdge = edge;
    mod.tileEdgeMat = edge.material;
    mod.tileBaseLine = 0.6;
    mod.tileTargetScale = 1;
    const h = mod._half, b = 3.2, pts = [];
    const corners = [[-h, -h, 1, 1], [h, -h, -1, 1], [-h, h, 1, -1], [h, h, -1, -1]];
    corners.forEach(([cxx, czz, sx, sz]) => {
      pts.push(cxx, 0.06, czz, cxx + sx * b, 0.06, czz);
      pts.push(cxx, 0.06, czz, cxx, 0.06, czz + sz * b);
    });
    const bg = new THREE2.BufferGeometry;
    bg.setAttribute("position", new THREE2.Float32BufferAttribute(pts.map((v, i) => i % 3 === 0 ? v + mod._cx : i % 3 === 2 ? v + mod._cz : v), 3));
    scene.add(new THREE2.LineSegments(bg, new THREE2.LineBasicMaterial({ color: COL.cyan, transparent: true, opacity: 0.7 })));
    mod.label = makeLabel(mod.name, "module", mod._cx, 0.4, mod._cz - mod._half - 3.4);
  });
  const pickables = [];
  const markerOn = { entry: true, dead: true };
  let tagTopDownHidden = false;
  function roleMarkerEnabled(f) {
    return f.isDead ? markerOn.dead !== false : f.isEndpoint ? markerOn.entry !== false : false;
  }
  function markerRingColor(f) {
    return f.isDead && markerOn.dead !== false ? COL.bad : f.isEndpoint && markerOn.entry !== false ? COL.good : f.isDoc ? COL.doc : COL.cyan;
  }
  function markerRingOpacity(f) {
    return f.faded ? 0.06 : f.isDead && markerOn.dead !== false ? 0.5 : f.isDoc ? 0.14 : 0.25;
  }
  function syncTag(f) {
    if (!f.tag)
      return;
    f.tag.visible = roleMarkerEnabled(f) && !tagTopDownHidden;
    f.tag.element.style.opacity = f._tagOpacity || "";
  }
  function syncMarkerLook(f) {
    if (f.glow && f.glow.material) {
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = markerRingOpacity(f);
    }
    syncTag(f);
  }
  function syncAllMarkers() {
    files.forEach((f) => syncMarkerLook(f));
    const id = focusApi?.getFocusId();
    if (id !== null && id !== undefined)
      focusApi.applyFocus(id);
  }
  function applyFade(f) {
    const op = f.faded ? 0.17 : 1, em = f.faded ? 0.13 : 0.55;
    (f.segMats || []).forEach((mat) => {
      mat.opacity = op;
      mat.emissiveIntensity = em;
    });
    if (f.glow) {
      f.glow.material.color.setHex(markerRingColor(f));
      f.glow.material.opacity = markerRingOpacity(f);
    }
    f._tagOpacity = f.faded ? "0.3" : "";
    syncTag(f);
  }
  files.forEach((f) => {
    const grp = new THREE2.Group;
    grp.position.set(f.x, 0, f.z);
    f.x0 = f.x;
    f.z0 = f.z;
    f.targetX = f.x;
    f.targetZ = f.z;
    let y = 0;
    f.segMats = [];
    f.segMid = [];
    f.methods.forEach((meth) => {
      const hgt = segHeight(meth.loc);
      const dead = !!meth.dead, docSeg = !!meth.doc;
      const col = docSeg ? new THREE2.Color(COL.doc) : dead ? new THREE2.Color(16718669) : meth.health == null ? new THREE2.Color(COL.doc) : healthColor(meth.health);
      const mat = new THREE2.MeshStandardMaterial({
        color: col,
        emissive: col,
        emissiveIntensity: docSeg ? 0.3 : dead ? 1.15 : 0.55,
        metalness: 0.2,
        roughness: docSeg ? 0.72 : 0.4,
        transparent: true,
        opacity: 1
      });
      const seg = new THREE2.Mesh(new THREE2.BoxGeometry(PILLAR_W, hgt, PILLAR_W), mat);
      seg.renderOrder = 8;
      seg.position.y = y + hgt / 2;
      seg.userData.fileId = f.id;
      grp.add(seg);
      if (!docSeg)
        pickables.push(seg);
      f.segMats.push(mat);
      f.segMid.push(y + hgt / 2);
      y += hgt + SEG_GAP;
    });
    const ringCol = markerRingColor(f);
    const ring = new THREE2.Mesh(new THREE2.RingGeometry(PILLAR_W * 0.75, PILLAR_W * 1.05, 32), new THREE2.MeshBasicMaterial({ color: ringCol, transparent: true, opacity: markerRingOpacity(f), side: THREE2.DoubleSide }));
    ring.renderOrder = 7;
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.05;
    grp.add(ring);
    f.glow = ring;
    f.group = grp;
    f.height = y;
    if (f.isEndpoint || f.isDead) {
      const d = document.createElement("div");
      d.className = "lbl tag " + (f.isDead ? "dead" : "entry");
      d.textContent = f.isDead ? "⚠ DEAD" : "▷ ENTRY";
      const o = new CSS2DObject3(d);
      o.position.set(0, y + 2.4, 0);
      grp.add(o);
      f.tag = o;
    }
    if (f.isDoc && f.isAgentDoc) {
      const d = document.createElement("div");
      d.className = "lbl tag doc";
      const dot = document.createElement("span");
      dot.className = "doc-dot";
      dot.textContent = "●";
      d.appendChild(dot);
      d.appendChild(document.createTextNode(" " + f.name));
      const o = new CSS2DObject3(d);
      o.position.set(0, y + 2.4, 0);
      grp.add(o);
      f.docTag = o;
    }
    if ((f.isEndpoint || f.isDead) && f.tag && typeof opts.onFileBadgeOpen === "function") {
      const d = f.tag.element;
      d.classList.add("tag-pick");
      d.title = f.isDead ? "Click to inspect why this file is marked DEAD" : "Click to inspect why this file is an ENTRY point";
      d.addEventListener("pointerdown", (ev) => {
        ev.stopPropagation();
      });
      d.addEventListener("click", (ev) => {
        ev.stopPropagation();
        focusApi?.openFileBadge(f);
      });
    }
    applyFade(f);
    scene.add(grp);
  });
  exts.forEach((x) => {
    const c = new THREE2.Color(x.color);
    x._pulse = 0;
    x.segMats = [];
    x.segMid = [];
    const grp = new THREE2.Group;
    grp.position.set(x.x, 0, x.z);
    x.group = grp;
    x.x0 = x.x;
    x.z0 = x.z;
    let y = 0, topY;
    if (x.items) {
      const k = KCFG[x.kind] || KCFG.db, box = k.geo === "box";
      const baseH = x.items.length > 24 ? Math.max(0.85, 2.4 * 24 / x.items.length) : 2.4;
      const gap = x.items.length > 40 ? 0.22 : 0.4;
      x.items.forEach((t) => {
        const h = baseH + t.val * k.hs, col = healthColor(t.health);
        const m = new THREE2.MeshStandardMaterial({ color: col, emissive: col, emissiveIntensity: 0.5, metalness: 0.3, roughness: 0.45, transparent: true, opacity: 1 });
        m._baseEm = col;
        const seg = new THREE2.Mesh(box ? new THREE2.BoxGeometry(6, h, 6) : new THREE2.CylinderGeometry(3.1, 3.1, h, 22), m);
        seg.renderOrder = 8;
        seg.position.set(0, y + h / 2, 0);
        seg.userData.fileId = x.id;
        grp.add(seg);
        pickables.push(seg);
        x.segMats.push(m);
        x.segMid.push(y + h / 2);
        y += h + gap;
      });
      topY = y + 3;
    } else {
      const geo = x.kind === "cache" ? new THREE2.BoxGeometry(5, 5, 5) : new THREE2.IcosahedronGeometry(3.8, 0);
      const m = new THREE2.MeshStandardMaterial({ color: c, emissive: c, emissiveIntensity: 0.5, metalness: 0.3, roughness: 0.45, transparent: true, opacity: 1 });
      m._baseEm = c;
      const mesh = new THREE2.Mesh(geo, m);
      mesh.position.set(0, 3.2, 0);
      mesh.userData.fileId = x.id;
      grp.add(mesh);
      pickables.push(mesh);
      x.segMats.push(m);
      x.segMid.push(3.2);
      y = 6.4;
      topY = 9;
      mesh.renderOrder = 8;
    }
    x.height = y;
    x.mat = x.segMats[x.segMats.length - 1];
    const ring = new THREE2.Mesh(new THREE2.RingGeometry(4.4, 5.6, 30), new THREE2.MeshBasicMaterial({ color: c, transparent: true, opacity: 0.3, side: THREE2.DoubleSide }));
    ring.renderOrder = 7;
    ring.rotation.x = -Math.PI / 2;
    ring.position.set(0, 0.05, 0);
    grp.add(ring);
    x.glow = ring;
    scene.add(grp);
    const d = document.createElement("div");
    d.className = "lbl ext";
    d.textContent = x.name;
    const o = new CSS2DObject3(d);
    o.position.set(0, topY, 0);
    grp.add(o);
  });
  let agentCore = null;
  if (agent && Array.isArray(agent.fileIds) && agent.fileIds.length) {
    const ac = new THREE2.Color(agent.color != null ? agent.color : COL.agent);
    let maxTop = 8;
    files.forEach((f) => {
      if ((f.height || 0) > maxTop)
        maxTop = f.height;
    });
    const ay = Math.max(46, Math.min(maxTop + 30, _bspan * 0.55));
    const agrp = new THREE2.Group;
    agrp.position.set(_bcx, ay, _bcz);
    const gm = new THREE2.MeshStandardMaterial({ color: ac, emissive: ac, emissiveIntensity: 0.9, metalness: 0.4, roughness: 0.3, transparent: true, opacity: 0.96 });
    agentCore = new THREE2.Mesh(new THREE2.OctahedronGeometry(5.4, 0), gm);
    agentCore.renderOrder = 9;
    agrp.add(agentCore);
    [7.2, 9].forEach((r, i) => {
      const halo = new THREE2.Mesh(new THREE2.RingGeometry(r, r + 0.5, 48), new THREE2.MeshBasicMaterial({ color: ac, transparent: true, opacity: i ? 0.2 : 0.4, side: THREE2.DoubleSide }));
      halo.rotation.x = -Math.PI / 2;
      halo.position.y = i ? -0.7 : 0.7;
      agrp.add(halo);
    });
    scene.add(agrp);
    const dl = document.createElement("div");
    dl.className = "lbl agent";
    dl.innerHTML = `${agent.name}<span>reads ${agent.fileIds.length} instruction file${agent.fileIds.length > 1 ? "s" : ""}</span>`;
    const ol = new CSS2DObject3(dl);
    ol.position.set(0, 9.4, 0);
    agrp.add(ol);
    const AGENT = new THREE2.Vector3(_bcx, ay - 4.4, _bcz);
    const beams = agent.fileIds.map((id) => {
      const f = nodeById[id];
      if (!f)
        return null;
      const line = new THREE2.Line(new THREE2.BufferGeometry, new THREE2.LineBasicMaterial({ color: ac, transparent: true, opacity: 0.55 }));
      line.renderOrder = 6;
      scene.add(line);
      return { line, f };
    }).filter(Boolean);
    agent._update = () => {
      beams.forEach((b) => {
        const from = new THREE2.Vector3(b.f.x, (b.f.height || 6) + 1.2, b.f.z);
        const mid = new THREE2.Vector3((from.x + AGENT.x) / 2, from.y + (AGENT.y - from.y) * 0.72, (from.z + AGENT.z) / 2);
        b.line.geometry.setFromPoints(new THREE2.QuadraticBezierCurve3(from, mid, AGENT).getPoints(22));
      });
    };
    agent._update();
  }
  let focusApi;
  const router = createCyberboardRouter({
    THREE: THREE2,
    scene,
    MODULES,
    files,
    exts,
    edges,
    nodeById,
    MAX,
    COL,
    EDGE_OP,
    EDGE_COL,
    PILLAR_W,
    ROAD_Y,
    laneType,
    edgeColorHex,
    contextEdgeVisible: (edge) => contextEdgeVisible(edge),
    syncMergeLayerVisibility: () => focusApi?.syncMergeLayerVisibility(),
    getFocusId: () => focusApi?.getFocusId() ?? null,
    getElevationId: () => focusApi?.getElevationId() ?? null,
    getPathEdges: () => focusApi?.getPathEdges() ?? null,
    getModuleFocus: () => focusApi?.getModuleFocus() ?? null
  });
  const { lineMats, mergeLayer, roadHW } = router;
  {
    const gs = $("#gap"), gv = $("#gapv");
    if (gs)
      on(gs, "input", () => {
        const v = parseFloat(gs.value);
        if (gv)
          gv.textContent = v.toFixed(1);
        router.setGap(v);
      });
  }
  {
    const lt = $("[data-cb-legend]");
    if (lt)
      on(lt, "click", () => {
        const lg = $("#cb-legend");
        if (!lg)
          return;
        const collapsed = lg.classList.toggle("collapsed");
        focusApi?.setHelp(!collapsed && focusApi.getFocusId() === null && focusApi.getElevationId() === null && focusApi.getPathEdges() === null);
      });
  }
  on(root, "wheel", (ev) => {
    focusApi?.handleWheel(ev);
  }, { passive: false, capture: true });
  const edgeTypeOn = { inherit: true, import: true, call: true, io: true, local: true };
  function edgeScopeVisible(e) {
    return edgeTypeOn[laneType(e)] !== false && (!e.hiddenByScope || e.scopeReveal);
  }
  function contextEdgeVisible(e) {
    const pathEdges = focusApi?.getPathEdges() ?? null;
    const focusId = focusApi?.getFocusId() ?? null;
    const focusEdges = focusApi?.getFocusEdges() ?? null;
    if (pathEdges !== null)
      return pathEdges.has(e.idx) && edgeScopeVisible(e);
    if (focusId !== null)
      return focusEdges ? focusEdges.has(e.idx) && edgeScopeVisible(e) : (e.a === focusId || e.b === focusId) && edgeScopeVisible(e);
    return edgeScopeVisible(e);
  }
  function applyEdgeTypeVis() {
    edges.forEach((e) => {
      if (e.line)
        e.line.visible = contextEdgeVisible(e);
    });
    router.renderEdgeRoutes();
  }
  function setEdgeScopeReveal(fn) {
    edges.forEach((e) => {
      e.scopeReveal = !!(fn && fn(e));
      if (e.line)
        e.line.visible = contextEdgeVisible(e);
    });
    router.renderEdgeRoutes();
  }
  root.querySelectorAll(".edge-toggle").forEach((b) => on(b, "click", (ev) => {
    ev.stopPropagation();
    const t = b.dataset.edgeType;
    edgeTypeOn[t] = !edgeTypeOn[t];
    b.classList.toggle("on", edgeTypeOn[t]);
    applyEdgeTypeVis();
  }));
  root.querySelectorAll(".marker-toggle").forEach((b) => on(b, "click", (ev) => {
    ev.stopPropagation();
    const t = b.dataset.markerType;
    markerOn[t] = !markerOn[t];
    b.classList.toggle("on", markerOn[t]);
    syncAllMarkers();
  }));
  {
    const db = $("[data-cb-docs]");
    if (db) {
      db.classList.toggle("on", opts.showDocs === true);
      on(db, "click", (ev) => {
        ev.stopPropagation();
        if (typeof opts.onToggleDocs === "function")
          opts.onToggleDocs();
      });
    }
  }
  {
    const mb = $("[data-trace-merge]");
    if (mb) {
      mb.classList.toggle("on", router.getMergeParallel());
      on(mb, "click", (ev) => {
        ev.stopPropagation();
        router.toggleMergeParallel();
        mb.classList.toggle("on", router.getMergeParallel());
        router.relayout();
      });
    }
  }
  const flow = createCyberboardFlow({
    THREE: THREE2,
    scene,
    files,
    exts,
    edges,
    nodeById,
    maxPayload: MAX.payload,
    REQ_COL,
    RES_COL,
    WRITE_COL,
    DEL_COL,
    edgeScopeVisible: (edge) => edgeScopeVisible(edge)
  });
  const { outEdges } = flow;
  focusApi = createCyberboardFocus({
    THREE: THREE2,
    opts,
    root,
    $,
    W,
    H,
    on,
    scene,
    camera,
    controls,
    files,
    exts,
    edges,
    MODULES,
    nodeById,
    outEdges,
    KCFG,
    PILLAR_W,
    MAX,
    COL,
    healthColor,
    markerRingColor,
    markerRingOpacity,
    syncTag,
    edgeScopeVisible: (edge) => edgeScopeVisible(edge),
    setEdgeScopeReveal: (fn) => setEdgeScopeReveal(fn),
    clearCameraViewOffset,
    setCameraViewOffsetPixels,
    getCameraViewOffset: () => _cameraViewOffset,
    tweenCam,
    isTweening: () => !!tween,
    OVERVIEW_POS,
    OVERVIEW_LOOK,
    mergeLayer,
    router,
    edgeTypeOn,
    contextEdgeVisible: (edge) => contextEdgeVisible(edge)
  });
  let tween = null;
  function tweenCam(pos, look) {
    tween = { pos, look, t: 0 };
    controls.enabled = false;
  }
  function updateTween(dt) {
    if (!tween)
      return;
    tween.t = Math.min(1, tween.t + dt * 1.6);
    const e = tween.t < 0.5 ? 2 * tween.t * tween.t : 1 - Math.pow(-2 * tween.t + 2, 2) / 2;
    camera.position.lerp(tween.pos, e * 0.18 + 0.04);
    controls.target.lerp(tween.look, e * 0.18 + 0.04);
    if (tween.t >= 1 && camera.position.distanceTo(tween.pos) < 0.6) {
      controls.enabled = true;
      tween = null;
    }
  }
  const input = createCyberboardInput({
    THREE: THREE2,
    root,
    renderer,
    camera,
    controls,
    W,
    H,
    on,
    pickables,
    edges,
    MODULES,
    roadHW,
    edgeTypeOn,
    contextEdgeVisible: (edge) => contextEdgeVisible(edge),
    focusApi,
    tweenCam,
    OVERVIEW_POS,
    OVERVIEW_LOOK
  });
  focusApi.setBoardTapHandler(input.handleBoardTap);
  const ro = new ResizeObserver(() => {
    const w = W(), h = H();
    if (w < 2 || h < 2)
      return;
    applyCameraProjection();
    renderer.setSize(w, h);
    labelRenderer.setSize(w, h);
    lineMats.forEach((m) => m.resolution.set(w, h));
    renderer.render(scene, camera);
    labelRenderer.render(scene, camera);
  });
  ro.observe(root);
  let last = performance.now(), _lastW = 0, _lastH = 0;
  let rafId = requestAnimationFrame(animate);
  const _kick = () => {
    const w = W(), h = H();
    if (w < 2 || h < 2)
      return;
    renderer.setSize(w, h + 1);
    labelRenderer.setSize(w, h + 1);
    renderer.render(scene, camera);
    applyCameraProjection();
    renderer.setSize(w, h);
    labelRenderer.setSize(w, h);
    lineMats.forEach((m) => m.resolution.set(w, h));
    renderer.render(scene, camera);
    labelRenderer.render(scene, camera);
    _lastW = w;
    _lastH = h;
  };
  requestAnimationFrame(_kick);
  const _kt1 = setTimeout(_kick, 90), _kt2 = setTimeout(_kick, 280);
  cleanups.push(() => {
    clearTimeout(_kt1);
    clearTimeout(_kt2);
  });
  function animate(now) {
    const dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    {
      const w = W(), h = H();
      if (w > 1 && h > 1 && (w !== _lastW || h !== _lastH)) {
        _lastW = w;
        _lastH = h;
        applyCameraProjection();
        renderer.setSize(w, h);
        labelRenderer.setSize(w, h);
        lineMats.forEach((m) => m.resolution.set(w, h));
      }
    }
    updateTween(dt);
    const k = Math.min(1, dt * 6);
    let moved = false;
    files.forEach((f) => {
      if (f.targetX === undefined)
        return;
      const nx = f.group.position.x + (f.targetX - f.group.position.x) * k;
      const nz = f.group.position.z + (f.targetZ - f.group.position.z) * k;
      if (Math.abs(nx - f.group.position.x) > 0.001 || Math.abs(nz - f.group.position.z) > 0.001)
        moved = true;
      f.group.position.x = nx;
      f.group.position.z = nz;
      f.x = nx;
      f.z = nz;
    });
    MODULES.forEach((m) => {
      if (!m.tileMesh)
        return;
      const s = m.tileMesh.scale.x + (m.tileTargetScale - m.tileMesh.scale.x) * k;
      m.tileMesh.scale.set(s, s, 1);
      m.tileEdge.scale.set(s, s, 1);
      if (m.label)
        m.label.position.z = m._cz - m._half * s - 3.4;
    });
    if (moved)
      router.rerouteLiveEdges();
    if (moved && agent && agent._update)
      agent._update();
    if (agentCore)
      agentCore.rotation.y += dt * 0.5;
    flow.update(dt, {
      flowing: focusApi.getFocusId() === null && focusApi.getElevationId() === null,
      pathEdges: focusApi.getPathEdges()
    });
    tagTopDownHidden = controls.getPolarAngle() < 0.42;
    files.forEach((f) => {
      syncTag(f);
      if (f.docTag)
        f.docTag.visible = !tagTopDownHidden;
    });
    input.updatePan(dt);
    controls.update();
    renderer.render(scene, camera);
    labelRenderer.render(scene, camera);
    rafId = requestAnimationFrame(animate);
  }
  if (bootHold)
    setLoading(true);
  else
    scheduleBootFade(700);
  cleanups.push(() => clearTimeout(bootT));
  function pause() {
    if (rafId) {
      cancelAnimationFrame(rafId);
      rafId = 0;
    }
  }
  function resume() {
    if (!rafId) {
      last = performance.now();
      rafId = requestAnimationFrame(animate);
    }
  }
  function destroy() {
    cancelAnimationFrame(rafId);
    ro.disconnect();
    cleanups.forEach((fn) => fn());
    try {
      controls.dispose();
    } catch {}
    scene.traverse((o) => {
      if (o.geometry)
        o.geometry.dispose?.();
      const m = o.material;
      if (m) {
        (Array.isArray(m) ? m : [m]).forEach((mm) => mm.dispose?.());
      }
    });
    try {
      renderer.dispose();
      renderer.forceContextLoss?.();
    } catch {}
    if (renderer.domElement?.parentNode)
      renderer.domElement.parentNode.removeChild(renderer.domElement);
    if (labelRenderer.domElement?.parentNode)
      labelRenderer.domElement.parentNode.removeChild(labelRenderer.domElement);
    container.innerHTML = "";
  }
  function selectMethod(i) {
    return focusApi.selectMethod(i);
  }
  function selectItem(i) {
    return focusApi.selectItem(i);
  }
  function focusFile(path) {
    return focusApi.focusFile(path);
  }
  function debugRouteStats() {
    const scan = (paths, edge, samples2) => {
      let diagonalSegments2 = 0, totalSegments2 = 0;
      (paths || []).forEach((pts) => {
        for (let i = 1;i < pts.length; i++) {
          const a = pts[i - 1], b = pts[i], dx = Math.abs(a.x - b.x), dz = Math.abs(a.z - b.z);
          totalSegments2++;
          if (dx > 0.05 && dz > 0.05) {
            diagonalSegments2++;
            if (samples2.length < 12)
              samples2.push({ idx: edge.idx, type: edge.type, from: edge.a, to: edge.b, i, dx: +dx.toFixed(2), dz: +dz.toFixed(2) });
          }
        }
      });
      return { totalSegments: totalSegments2, diagonalSegments: diagonalSegments2 };
    };
    let diagonalSegments = 0, totalSegments = 0, visualDiagonalSegments = 0, visualTotalSegments = 0;
    const samples = [], visualSamples = [];
    edges.forEach((e) => {
      const base = scan([e.pts || []], e, samples);
      const visual = scan(e._visualPaths || [e.pts || []], e, visualSamples);
      diagonalSegments += base.diagonalSegments;
      totalSegments += base.totalSegments;
      visualDiagonalSegments += visual.diagonalSegments;
      visualTotalSegments += visual.totalSegments;
    });
    const mergeMeshes = mergeLayer.children.length;
    return { totalSegments, diagonalSegments, samples, visualTotalSegments, visualDiagonalSegments, visualSamples, mergeParallel: router.getMergeParallel(), mergeMeshes };
  }
  if (router.getMergeParallel())
    router.relayout();
  return { destroy, pause, resume, getScene: () => scene, getCamera: () => camera, selectMethod, selectItem, focusFile, setLoading, debugRouteStats };
}
if (typeof window !== "undefined")
  window.createCyberboard = createCyberboard;
export {
  createCyberboard
};
