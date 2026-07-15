import importlib.util
import subprocess
import sys
import unittest
from pathlib import Path

from scad_test_utils import ROOT

SCRIPT = ROOT / "scripts" / "rebar_cut_list.py"


def load_script():
    spec = importlib.util.spec_from_file_location("rebar_cut_list", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RebarCutListTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = load_script()

    def test_rounds_cut_lengths_half_up_to_whole_millimetres(self) -> None:
        self.assertTrue(hasattr(self.module, "round_cut_mm"))
        self.assertEqual(self.module.round_cut_mm(10.49), 10)
        self.assertEqual(self.module.round_cut_mm(10.5), 11)
        self.assertEqual(self.module.round_cut_mm(10.51), 11)

    def test_capped_insert_groups_include_stop_gap(self) -> None:
        self.assertTrue(hasattr(self.module, "INSERT_STOP_GAP_MM"))
        self.assertTrue(hasattr(self.module, "rounded_cut_groups"))
        self.assertEqual(self.module.INSERT_STOP_GAP_MM, 1.0)
        self.assertEqual(
            [
                length
                for _, _, length in self.module.rounded_cut_groups(3000, 2000)
            ],
            [1124, 1119, 1973, 1693],
        )

    def test_cli_prints_whole_millimetres_and_cut_tolerance(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--diameter",
                "3000",
                "--height",
                "2000",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for line in (
            "8 шт. × 1124 мм",
            "8 шт. × 1119 мм",
            "8 шт. × 1973 мм",
            "8 шт. × 1693 мм",
            "допуск реза: ±1 мм",
            "47.272 м",
        ):
            with self.subTest(line=line):
                self.assertIn(line, result.stdout)


if __name__ == "__main__":
    unittest.main()
