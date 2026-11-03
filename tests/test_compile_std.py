"""Preserve scene geometry and byte-addressed camera programs from thstd."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "compile_std", Path(__file__).resolve().parents[1] / "tools/compile_std.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class StdCompilerTests(unittest.TestCase):
    def test_geometry_and_timeline_survive_compilation(self):
        source = """ENTRY:
 Position: 1 2 3
 Width: 1024
 Height: 512
 QUAD:
  Script_index: 0
  Position: 0 0 300.5
  Width: 1024
  Height: 512
 QUAD:
  Script_index: 1
  Position: 4 5 6
  Width: 128
  Height: 64
 FACE: 256 -1.5 384 -64
SCRIPT:
 ins_8(#1060100f, 400.0f, 900.0f);
390:
 ins_2(-50.0f, 512.0f, -400.0f);
 ins_1(20, 390);
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "st01.txt"
            path.write_text(source, encoding="utf-8")
            entries, timeline = compiler.parse_std(path)
        self.assertEqual(entries[0]["position"], [1, 2, 3])
        self.assertEqual(len(entries[0]["quads"]), 2)
        self.assertEqual(entries[0]["quads"][0]["position"][2], 300.5)
        self.assertEqual(entries[0]["width"], 1024)
        self.assertEqual(entries[0]["faces"][0], dict(flags=256, x=-1.5, y=384, z=-64))
        self.assertEqual(timeline[0]["args"][0], 0x1060100f)
        self.assertEqual(timeline[1]["time"], 390)
        self.assertEqual(timeline[1]["offset"], 20)
        self.assertEqual(timeline[2]["args"], [20, 390])


if __name__ == "__main__":
    unittest.main()
