#!/usr/bin/env bash
set -euo pipefail

web_root="$(cd "$(dirname "$0")" && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# File-backed WKWebView does not consistently support cross-file ES modules.
# Ship one classic script with the exact same vendored Three.js and Repo Lens.
mkdir -p "$scratch/node_modules/three"
cp "$web_root"/*.js "$scratch/"
cp "$web_root/build/cb-core.js" "$scratch/cb-core.js"
cp -R "$web_root/build/three/." "$scratch/node_modules/three/"
cat > "$scratch/node_modules/three/package.json" <<'JSON'
{"name":"three","type":"module","main":"./three.module.js"}
JSON
bun build "$scratch/mesh-graph.js" --target browser --format iife --minify-syntax --minify-whitespace \
  --outfile "$web_root/build/viewer.js"
python3 - "$web_root/build/viewer.js" <<'PY'
from pathlib import Path
import re
import sys
path = Path(sys.argv[1])
path.write_text(re.sub(r"[ \t]+\n", "\n", path.read_text()))
PY
