#!/usr/bin/env bash
# Demande deux rendus (sans puis avec le bandeau visible), attend qu'ils soient finis, télécharge
# les fichiers par leurs liens signés et affiche leur marquage (ExifTool pour le PNG, lire_marquage.py
# pour le PNG et le GLB). Comme Open WebUI, il passe le jeton du studio et l'en-tête d'identité.
# Prérequis, dans un autre terminal : kubectl -n studio3d port-forward svc/studio 8000:8000
# et le jeton dans l'environnement : export STUDIO_JETON=…
set -euo pipefail
URL=${STUDIO_URL:-http://127.0.0.1:8000}
QUI=${QUI:-essai@example.com}
PYTHON=${PYTHON:-python3}    # sous Windows : PYTHON=python
: "${STUDIO_JETON:?STUDIO_JETON manquant}"
ICI=$(cd "$(dirname "$0")/.." && pwd)
SCENE='import bpy\nbpy.ops.mesh.primitive_plane_add(size=6); bpy.context.object.name = \"Decor sol\"\nbpy.ops.mesh.primitive_cylinder_add(radius=0.5, depth=1, location=(0, 0, 0.5))'

outil() { # $1 : nom de l'outil, $2 : arguments JSON ; affiche le résultat de l'outil (texte JSON)
  curl -s "$URL/mcp" -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -H "Authorization: Bearer $STUDIO_JETON" -H "X-Utilisateur-Email: $QUI" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":$2}}" \
    | sed -n 's/^data: //p' | sed 's/\\"/"/g'
}
numero() { grep -o '"numero": *[0-9]*' | head -1 | grep -o '[0-9]*$'; }

sans=$(outil soumettre_rendu "{\"titre\":\"Sans bandeau\",\"code\":\"$SCENE\"}" | numero)
avec=$(outil soumettre_rendu "{\"titre\":\"Avec bandeau\",\"code\":\"$SCENE\",\"marquage_visible\":true}" | numero)
echo "Demandes : $sans (sans bandeau), $avec (avec bandeau)"

for n in "$sans" "$avec"; do
  until outil etat_rendu "{\"numero\":$n}" | grep -Eq '"statut": *"(termine|erreur)"'; do sleep 5; done
  etat=$(outil etat_rendu "{\"numero\":$n}")
  png=$(echo "$etat" | grep -o 'http[^)" ]*\.png' | head -1)
  glb=$(echo "$etat" | grep -o 'http[^)" ]*\.glb' | head -1)
  curl -s -o "rendu-$n.png" "$png"
  curl -s -o "rendu-$n.glb" "$glb"
  echo "--- rendu $n"
  if command -v exiftool >/dev/null; then exiftool -G1 -s -XMP:all -PNG:all "rendu-$n.png"; else "$PYTHON" "$ICI/lire_marquage.py" "rendu-$n.png"; fi
  "$PYTHON" "$ICI/lire_marquage.py" "rendu-$n.glb"
done
echo "Ouvrez rendu-$avec.png : le bandeau « AI studio3D · date » est en bas à droite."
