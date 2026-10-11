"""Lit le marquage d'un rendu du studio (module s3d04), sans dépendance : bibliothèque standard seulement.

  python lire_marquage.py rendu.png     champs texte du PNG (tEXt, iTXt) et paquet XMP résumé
  python lire_marquage.py modele.glb    asset.generator et asset.extras du GLB

ExifTool lit très bien le PNG ; il ne lit pas le glTF : ce script sert surtout au modèle 3D.
"""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ATTRIBUTS = ("Iptc4xmpExt:DigitalSourceType", "xmp:CreatorTool", "xmp:CreateDate", "xmpMM:DocumentID")


def lire_png(data: bytes) -> list[tuple[str, str]]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("ce n'est pas un PNG")
    champs, pos = [], 8
    while pos < len(data):
        longueur, genre = struct.unpack_from(">I4s", data, pos)
        corps = data[pos + 8:pos + 8 + longueur]
        pos += 12 + longueur                                   # longueur, type, données, CRC
        if genre == b"tEXt":
            cle, valeur = corps.split(b"\0", 1)
            champs.append((cle.decode("latin-1"), valeur.decode("latin-1")))
        elif genre == b"iTXt":
            cle, reste = corps.split(b"\0", 1)
            compresse, _methode = reste[0], reste[1]
            _langue, _cle_traduite, texte = reste[2:].split(b"\0", 2)
            texte = zlib.decompress(texte) if compresse else texte
            texte = texte.decode("utf-8")
            if cle == b"XML:com.adobe.xmp":                    # paquet XMP : ses quatre attributs
                for a in ATTRIBUTS:
                    m = re.search(re.escape(a) + r'="([^"]*)"', texte)
                    if m:
                        champs.append((f"XMP {a}", m.group(1)))
            else:
                champs.append((cle.decode("latin-1"), texte))
        elif genre == b"IEND":
            break
    return champs


def lire_glb(data: bytes) -> list[tuple[str, str]]:
    longueur, genre = struct.unpack_from("<I4s", data, 12)
    if data[:4] != b"glTF" or genre != b"JSON":
        raise ValueError("ce n'est pas un GLB")
    asset = json.loads(data[20:20 + longueur]).get("asset", {})
    champs = [("asset.generator", asset.get("generator", ""))]
    champs += [(f"asset.extras.{k}", str(v)) for k, v in asset.get("extras", {}).items()]
    return champs


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    chemin = Path(sys.argv[1])
    data = chemin.read_bytes()
    champs = lire_glb(data) if chemin.suffix.lower() == ".glb" else lire_png(data)
    if not champs:
        print("aucun marquage trouvé")
    largeur = max((len(k) for k, _ in champs), default=0)
    for cle, valeur in champs:
        print(f"{cle.ljust(largeur)} : {valeur}")


if __name__ == "__main__":
    main()
