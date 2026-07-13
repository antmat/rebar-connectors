import tempfile
import unittest
from pathlib import Path

from scad_test_utils import ROOT, run_openscad


class ToolchainTest(unittest.TestCase):
    def test_bosl2_smoke_model_renders(self) -> None:
        source = ROOT / "tests" / "bosl2_smoke.scad"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bosl2-smoke.stl"
            result = run_openscad(
                source,
                output,
                extra_args=("--export-format", "binstl"),
            )
            self.assertEqual(
                result.returncode,
                0,
                result.stdout + result.stderr,
            )
            self.assertTrue(output.exists())
            self.assertGreater(output.stat().st_size, 84)


if __name__ == "__main__":
    unittest.main()
