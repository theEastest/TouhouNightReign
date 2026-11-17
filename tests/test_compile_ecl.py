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

    def test_difficulty_stack_expressions_are_preserved(self):
        result = compiler.compile_body("!E\n$D * 2;\n!NHL\n$D;\n!*\nwait([-1]);")
        self.assertEqual(result[-1][2][0]["__branches__"], ["$D * 2", "$D", "$D", "$D", "0"])

    def test_async_number_is_an_identifier_with_arguments(self):
        self.assertEqual(compiler.compile_body("@Attack(6) async 1;"),
                         [("call_id", "Attack", 1, ["6"])])

    def test_plain_and_difficulty_stack_values_combine(self):
        result = compiler.compile_body("%C + 48;\n!ENHLO\n60;\n!*\nmovePosTime([-1], 4, [-2.0f], 192.0f);")
        self.assertEqual(result[-1][2][0]["__branches__"], ["60"] * 5)
        self.assertEqual(result[-1][2][2]["__branches__"], ["%C + 48"] * 5)

    def test_inline_expression_counts_toward_stack_offset(self):
        result = compiler.compile_body("!ENHLO\n0.5f;\n!*\netAngle(0, %A + %B, [-2.0f]);")
        self.assertEqual(result[-1][2][2]["__branches__"], ["0.5f"] * 5)

    def test_cancel_effect_stack_arithmetic_survives_time_label(self):
        result = compiler.compile_body("%A;\n+1:\n10;\naddf();\nsetf(%A);")
        self.assertEqual(result[-1], ("assign", "%A", "=", "(%A) + (10)"))

    def test_random_stack_expressions_run_before_direct_registers(self):
        args = '0, %RANDF2 * 16.0f, %RANDF * 32.0f, %RANDRAD'
        result = compiler.compile_body(f"etOffsetAbs({args});")
        self.assertEqual(result[-1][3], [3, 2])

    def test_difficulty_stack_random_precedes_inline_expression(self):
        result = compiler.compile_body("""
!E
 (%RANDF * 1.0f) + 1.0f;
!NHL
 (%RANDF * 1.0f) + 2.0f;
!*
 etExSet2(1, 1, 0, 16, 70, 1, 4, 0, 1.5707964f + (%RANDF2 * 0.17453292f), [-2.0f], -999999.0f, -999999.0f);
""")
        instruction = result[-1]
        self.assertEqual(instruction[3], [10, 9])
        self.assertEqual(instruction[2][9]["__branches__"][1], "(%RANDF * 1.0f) + 2.0f")
        self.assertEqual(instruction[2][10], "-999999.0f")

    def test_nonrandom_difficulty_values_do_not_consume_random(self):
        result = compiler.compile_body("!ENHLO\n42;\n!*\nwait([-1]);")
        self.assertEqual(len(result[-1]), 3)

    def test_multiple_random_stack_values_keep_push_order(self):
        result = compiler.compile_body("""
!ENHLO
 %RANDF + 1;
!*
!ENHLO
 %RANDF + 2;
!*
 etOffsetAbs(0, [-1.0f], [-2.0f]);
""")
        self.assertEqual(result[-1][3], [3, 2])


if __name__ == "__main__":
    unittest.main()
