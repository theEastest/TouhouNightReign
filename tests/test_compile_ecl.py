"""Compiler regressions independent of the generated Lua tables."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "compile_ecl", Path(__file__).resolve().parents[1] / "tools/compile_ecl.py")
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class EclCompilerTests(unittest.TestCase):
    def test_parameterized_routine_is_not_lost(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "stage.decl"
            source.write_text("void Attack(var A, var B)\n{\n wait(%A);\n return;\n}\n", encoding="utf-8")
            routine = compiler.compile_file(source)["Attack"]
        self.assertEqual(routine[0], ("params", ["A", "B"]))
        self.assertEqual(routine[1], ("ins", "wait", ["%A"]))

    def test_multiple_stack_values_keep_operand_order(self):
        result = compiler.compile_body("""
!E
 3;
!N
 5;
!H
 7;
!LO
 9;
!E
 11;
!N
 13;
!H
 15;
!LO
 17;
!*
 etCount(0, [-1], [-2]);
""")
        args = result[-1][2]
        self.assertEqual(args[1]["__branches__"], ["11", "13", "15", "17", "17"])
        self.assertEqual(args[2]["__branches__"], ["3", "5", "7", "9", "9"])

    def test_difficulty_masks_apply_to_calls(self):
        result = compiler.compile_body("!NHL\n@Attack() async;\n!*\nreturn;")
        self.assertEqual(result[0], ("diff", "NHL"))
        self.assertEqual(result[2], ("diff_end",))


if __name__ == "__main__":
    unittest.main()
