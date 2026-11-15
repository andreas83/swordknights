#!/usr/bin/env python3
"""Puts the colour textures of one Tripo export onto the meshes of another.

    python3 -I tools/merge_glb.py animated.glb textured.glb \\
        assets/characters/princess.glb
    godot --headless --path . --import

The animated export (Mixamo rig, clips) came without base colours; the
textured export has them but no rig. Their meshes are the same parts with the
same UVs, so each material of the animated file takes the base colour image
of the material of the same name in the textured file.

WHY A GRAFT AND NOT A RE-EXPORT.
Tripo rigs and animates a model in one job and textures it in another, and
the owner's princess came out of the two as two files: one that moves and is
grey, one that is coloured and cannot move. Both are cut into the same parts
(`tripo_part_*`) with the same UV sets -- only the vertex order differs -- so a
texture atlas maps onto the animated part exactly. Nothing is resampled or
re-encoded: the image bytes are copied into the animated file's binary chunk
as they were. The UV sets are compared part by part, as sets (`uv_set()`), and
any part whose UVs differ is named, because a texture on mismatched UVs is a
scrambled skin that nothing downstream would notice. Render the result
(tests/character_poses.gd) before trusting it all the same.

A development tool, run by hand when a new export arrives; CI never runs it.
Standard library only.
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys


def load(path: str) -> tuple[dict, bytearray]:
    """The JSON chunk and the binary chunk of a .glb."""
    with open(path, "rb") as f:
        data = f.read()
    clen, _ = struct.unpack("<I4s", data[12:20])
    doc = json.loads(data[20:20 + clen])
    start = 20 + clen
    blen, _ = struct.unpack("<I4s", data[start:start + 8])
    return doc, bytearray(data[start + 8:start + 8 + blen])


def view_bytes(doc: dict, binary: bytearray, view_index: int) -> bytes:
    view = doc["bufferViews"][view_index]
    off = view.get("byteOffset", 0)
    return bytes(binary[off:off + view["byteLength"]])


def accessor_bytes(doc: dict, binary: bytearray, acc_index: int) -> bytes:
    acc = doc["accessors"][acc_index]
    return view_bytes(doc, binary, acc["bufferView"])


def uv_set(uvs: bytes) -> str:
    """A fingerprint of a part's UVs that ignores their order: the two exports
    list the same vertices in a different order, so their raw bytes never
    match, while the set of (u, v) pairs must."""
    pairs = sorted(uvs[i:i + 8] for i in range(0, len(uvs), 8))
    return hashlib.sha1(b"".join(pairs)).hexdigest()


def by_material(doc: dict) -> dict:
    """Material name -> the first primitive drawn in it: one part each."""
    out = {}
    for mesh in doc["meshes"]:
        prim = mesh["primitives"][0]
        out[doc["materials"][prim["material"]]["name"]] = prim
    return out


def main(animated: str, textured: str, out: str) -> None:
    adoc, abin = load(animated)
    tdoc, tbin = load(textured)
    aprims, tprims = by_material(adoc), by_material(tdoc)
    mismatched = []
    for name, prim in aprims.items():
        a_uv = accessor_bytes(adoc, abin, prim["attributes"]["TEXCOORD_0"])
        t_uv = accessor_bytes(tdoc, tbin, tprims[name]["attributes"]["TEXCOORD_0"])
        if uv_set(a_uv) != uv_set(t_uv):
            mismatched.append(name)
    print("uv mismatches:", mismatched)
    adoc.setdefault("images", [])
    adoc.setdefault("textures", [])
    sampler = 0 if adoc.get("samplers") else None
    for material in adoc["materials"]:
        source = next(m for m in tdoc["materials"] if m["name"] == material["name"])
        tex = tdoc["textures"][source["pbrMetallicRoughness"]["baseColorTexture"]["index"]]
        image = tdoc["images"][tex["source"]]
        blob = view_bytes(tdoc, tbin, image["bufferView"])
        while len(abin) % 4:
            abin.append(0)
        offset = len(abin)
        abin.extend(blob)
        adoc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob)})
        adoc["images"].append({"name": image.get("name", ""), "mimeType": image["mimeType"],
                               "bufferView": len(adoc["bufferViews"]) - 1})
        texture = {"source": len(adoc["images"]) - 1}
        if sampler is not None:
            texture["sampler"] = sampler
        adoc["textures"].append(texture)
        pbr = material.setdefault("pbrMetallicRoughness", {})
        pbr["baseColorTexture"] = {"index": len(adoc["textures"]) - 1}
        pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
        pbr["roughnessFactor"] = source["pbrMetallicRoughness"].get("roughnessFactor", 0.9)
    while len(abin) % 4:
        abin.append(0)
    adoc["buffers"][0]["byteLength"] = len(abin)
    js = json.dumps(adoc, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(abin)
    with open(out, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON"))
        f.write(js)
        f.write(struct.pack("<I4s", len(abin), b"BIN\x00"))
        f.write(abin)
    print("wrote", out, total)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
