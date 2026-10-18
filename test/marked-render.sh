#!/usr/bin/env bash
# Asks for two renders (without, then with the visible banner), waits until they are finished, downloads
# the files through their signed links and shows their marking (ExifTool for the PNG, read_marking.py
# for the PNG and the GLB). Like Open WebUI, it sends the studio token and the identity header.
# Prerequisites, in another terminal: kubectl -n studio3d port-forward svc/studio 8000:8000
# and the token in the environment: export STUDIO_TOKEN=…
set -euo pipefail
URL=${STUDIO_URL:-http://127.0.0.1:8000}
WHO=${WHO:-test@example.com}
PYTHON=${PYTHON:-python3}    # on Windows: PYTHON=python
: "${STUDIO_TOKEN:?STUDIO_TOKEN missing}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
SCENE='import bpy\nbpy.ops.mesh.primitive_plane_add(size=6); bpy.context.object.name = \"Decor floor\"\nbpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, location=(0, 0, 0.5))'

tool() { # $1: tool name, $2: JSON arguments; prints the tool result (JSON text)
  curl -s "$URL/mcp" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: Bearer $STUDIO_TOKEN" -H "X-User-Email: $WHO" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
    | sed -n 's/^data: //p' | sed 's/\\"/"/g'
}
number() { grep -o '"number": *[0-9]*' | head -1 | grep -o '[0-9]*$'; }

without=$(tool submit_render "{\"title\":\"Without banner\",\"code\":\"$SCENE\"}" | number)
with=$(tool submit_render "{\"title\":\"With banner\",\"code\":\"$SCENE\",\"visible_marking\":true}" | number)
echo "Requests: $without (without banner), $with (with banner)"

for n in "$without" "$with"; do
  until tool render_status "{\"number\":$n}" | grep -Eq '"status": *"(done|error)"'; do sleep 5; done
  status=$(tool render_status "{\"number\":$n}")
  png=$(echo "$status" | grep -o 'http[^)" ]*\.png' | head -1)
  glb=$(echo "$status" | grep -o 'http[^)" ]*\.glb' | head -1)
  curl -s -o "render-$n.png" "$png"
  curl -s -o "render-$n.glb" "$glb"
  echo "--- render $n"
  if command -v exiftool >/dev/null; then exiftool -G1 -s -XMP:all -PNG:all "render-$n.png"; else "$PYTHON" "$HERE/read_marking.py" "render-$n.png"; fi
  "$PYTHON" "$HERE/read_marking.py" "render-$n.glb"
done
echo "Open render-$with.png: the \"AI studio3D · date\" banner is at the bottom right."
