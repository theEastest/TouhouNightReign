import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('compile_msg', Path(__file__).resolve().parents[1] / 'tools/compile_msg.py')
compiler = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compiler)


class MsgCompilerTests(unittest.TestCase):
    def test_timing_text_and_control_instructions(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'dialog.txt'
            path.write_text('entry 0 (256)\n@34\n\t17;中文;标点\n@38\n\t11;600\n@42\n\t12\n\t28;112.0f;270.0f\n\t0\nentry 1 (256)\n@0\n\t21\n\t0\n', encoding='utf-8')
            result = compiler.parse(path)
        self.assertEqual(result[0][0], dict(time=34, id=17, args=['中文;标点']))
        self.assertEqual(result[0][1]['args'], [600])
        self.assertEqual(result[0][2]['id'], 12)
        self.assertEqual(result[0][3]['args'], [112, 270])
        self.assertEqual(result[1][0]['id'], 21)


if __name__ == '__main__':
    unittest.main()
