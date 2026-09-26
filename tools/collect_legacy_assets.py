"""Copy every texture the compiled ANM data refers to.

Reads the th15 sprite dump, collects the texture path of each archive entry and
copies the file into the project asset tree, keeping the reference layout so the
Lua data can address it by the same relative path.

Usage:
    python tools/collect_legacy_assets.py <unpacked_root> <spec_dir> <out_dir>
"""
import io
import os
import re
import shutil
import sys


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 1
    unpacked = sys.argv[1].rstrip("/\\")
    spec_dir = sys.argv[2]
    out_dir = sys.argv[3]
    anm_root = os.path.join(unpacked, "th15_anm")

    wanted = {}
    for filename in sorted(os.listdir(spec_dir)):
        if not filename.endswith(".txt"):
            continue
        for line in io.open(os.path.join(spec_dir, filename), encoding="utf-8", errors="replace"):
            if line.startswith("Name: "):
                texture = line[6:].strip().replace("\\", "/")
                wanted[texture] = True

    copied, missing = 0, []
    for texture in sorted(wanted):
        source = os.path.join(anm_root, texture)
        if not os.path.isfile(source):
            missing.append(texture)
            continue
        target = os.path.join(out_dir, texture)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(source, target)
        copied += 1
    print("copied %d textures, %d missing" % (copied, len(missing)))
    for name in missing[:20]:
        print("  missing: " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
