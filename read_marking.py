"""Reads the marking of a studio render (module s3d04), with no dependency: standard library only.

  python read_marking.py render.png     PNG text fields (tEXt, iTXt) and a summary of the XMP packet
  python read_marking.py model.glb      asset.generator and asset.extras of the GLB

ExifTool reads the PNG very well; it does not read glTF: this script is mostly for the 3D model.
"""
import json
import re
import struct
import sys
import zlib
from pathlib import Path

ATTRIBUTES = ("Iptc4xmpExt:DigitalSourceType", "xmp:CreatorTool", "xmp:CreateDate", "xmpMM:DocumentID")


def read_png(data: bytes) -> list[tuple[str, str]]:
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    fields, pos = [], 8
    while pos < len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length                                     # length, type, data, CRC
        if kind == b"tEXt":
            key, value = body.split(b"\0", 1)
            fields.append((key.decode("latin-1"), value.decode("latin-1")))
        elif kind == b"iTXt":
            key, rest = body.split(b"\0", 1)
            compressed, _method = rest[0], rest[1]
            _language, _translated_key, text = rest[2:].split(b"\0", 2)
            text = zlib.decompress(text) if compressed else text
            text = text.decode("utf-8")
            if key == b"XML:com.adobe.xmp":                    # XMP packet: its four attributes
                for a in ATTRIBUTES:
                    m = re.search(re.escape(a) + r'="([^"]*)"', text)
                    if m:
                        fields.append((f"XMP {a}", m.group(1)))
            else:
                fields.append((key.decode("latin-1"), text))
        elif kind == b"IEND":
            break
    return fields


def read_glb(data: bytes) -> list[tuple[str, str]]:
    length, kind = struct.unpack_from("<I4s", data, 12)
    if data[:4] != b"glTF" or kind != b"JSON":
        raise ValueError("not a GLB file")
    asset = json.loads(data[20:20 + length]).get("asset", {})
    fields = [("asset.generator", asset.get("generator", ""))]
    fields += [(f"asset.extras.{k}", str(v)) for k, v in asset.get("extras", {}).items()]
    return fields


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = Path(sys.argv[1])
    data = path.read_bytes()
    fields = read_glb(data) if path.suffix.lower() == ".glb" else read_png(data)
    if not fields:
        print("no marking found")
    width = max((len(k) for k, _ in fields), default=0)
    for key, value in fields:
        print(f"{key.ljust(width)} : {value}")


if __name__ == "__main__":
    main()
