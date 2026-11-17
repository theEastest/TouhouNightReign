import importlib.util
import pathlib
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "compile_anm", pathlib.Path(__file__).parents[1] / "tools/compile_anm.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class CompileAnimationTest(unittest.TestCase):
    def test_small_motion_rates_keep_source_precision(self):
        for value in (-0.000033333334, 0.0000001, 0.034906585):
            self.assertEqual(float(compiler.lua_number(value)), value)

    def test_variable_mask_survives_lowering(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "effect.txt"
            path.write_text("ENTRY #0\nName: effect.png\nScript: 66\n"
                            "Instruction #0: 0 3 117 10004.0f 10011.0f 128.0f\n"
                            "Instruction #1: 0 0 402 1.0f 1.0f\n", encoding="utf-8")
            instructions = compiler.parse_spec(path)[0]["scripts"][66]
        self.assertEqual(instructions[0]["mask"], 3)
        self.assertEqual(instructions[0]["args"], [10004, 10011, 128])
        self.assertEqual(instructions[1]["mask"], 0)


if __name__ == "__main__":
    unittest.main()
