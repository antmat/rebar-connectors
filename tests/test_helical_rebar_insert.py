import re
import tempfile
import unittest
from pathlib import Path

from scad_test_utils import ROOT, inspect_binary_stl, run_openscad

MODEL = ROOT / "rebar_insert.scad"
PROBE_MODEL = ROOT / "tests" / "helical_insert_probes.scad"

FIT_DIMENSIONS = {
    "loose": (1.2, 12.2),
    "medium": (1.3, 12.4),
    "tight": (1.4, 12.6),
}


def render_model(
    part: str,
    directory: str,
    fit: str = "medium",
):
    output = Path(directory) / f"{part}-{fit}.stl"
    result = run_openscad(
        MODEL,
        output,
        defines=(f'Part="{part}"', f'Fit="{fit}"'),
        extra_args=("--export-format", "binstl"),
    )
    return result, output


def read_metrics(part: str, fit: str, directory: str) -> dict[str, float]:
    output = Path(directory) / f"{part}-{fit}.echo"
    result = run_openscad(
        MODEL,
        output,
        defines=(
            f'Part="{part}"',
            f'Fit="{fit}"',
            "Diagnostics=true",
        ),
    )
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)
    return {
        name: float(value)
        for name, value in re.findall(
            r"([a-z_]+)=(-?[0-9.]+)",
            output.read_text(),
        )
    }


def render_probe(probe: str, directory: str):
    output = Path(directory) / f"{probe}.stl"
    result = run_openscad(
        PROBE_MODEL,
        output,
        defines=("Render_Model=false", f'Probe="{probe}"'),
        extra_args=("--export-format", "binstl"),
    )
    return result, output


class HelicalInsertTest(unittest.TestCase):
    def test_calibration_length_must_fit_socket_depth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "too-long-calibration.stl"
            result = run_openscad(
                MODEL,
                output,
                defines=(
                    'Part="calibration_single"',
                    "Calibration_Length_mm=30",
                ),
                extra_args=("--export-format", "binstl"),
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Calibration_Length_mm must be positive and shorter than the socket",
            result.stdout + result.stderr,
        )

    def test_calibration_metrics_match_measured_rebar(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for fit, (expected_wall, expected_cage) in FIT_DIMENSIONS.items():
                with self.subTest(fit=fit):
                    metrics = read_metrics(
                        "calibration_single",
                        fit,
                        directory,
                    )
                    self.assertIn("core_d", metrics)
                    self.assertAlmostEqual(metrics["core_d"], 9.1)
                    self.assertIn("core_clearance", metrics)
                    self.assertAlmostEqual(metrics["core_clearance"], 0.7)
                    self.assertAlmostEqual(metrics["bore_d"], 9.8)
                    self.assertAlmostEqual(metrics["rebar_max_d"], 11.3)
                    self.assertAlmostEqual(metrics["rib_width"], 2.5)
                    self.assertIn("wall_t", metrics)
                    self.assertAlmostEqual(metrics["wall_t"], expected_wall)
                    self.assertAlmostEqual(metrics["cage_d"], expected_cage)
                    self.assertAlmostEqual(metrics["slot_width"], 3.5)
                    self.assertIn("entry_d", metrics)
                    self.assertAlmostEqual(metrics["entry_d"], 10.8)
                    self.assertAlmostEqual(metrics["working_length"], 12.0)
                    self.assertAlmostEqual(metrics["lead"], 45.0)
                    self.assertEqual(metrics["starts"], 2)
                    self.assertEqual(metrics["twist_sign"], -1)

    def test_tight_insert_may_exceed_reference_socket_diameter(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_model(
                "calibration_single",
                directory,
                fit="tight",
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertEqual(stats.components, 1)

    def test_calibration_single_is_one_printable_component(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_model(
                "calibration_single",
                directory,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertEqual(stats.components, 1)
        self.assertGreater(stats.volume, 100)
        self.assertAlmostEqual(stats.bounds_min[2], 0.0, places=3)
        self.assertAlmostEqual(stats.dimensions[2], 14.4, places=3)

    def test_calibration_set_contains_three_separate_parts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_model(
                "calibration_set",
                directory,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertEqual(stats.components, 3)
        self.assertAlmostEqual(stats.bounds_min[2], 0.0, places=3)
        self.assertAlmostEqual(stats.dimensions[2], 14.4, places=3)
        self.assertLess(stats.dimensions[0], 60.0)

    def test_full_insert_is_one_31_4_mm_component(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_model("full", directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertEqual(stats.components, 1)
        self.assertGreater(stats.volume, 250)
        self.assertAlmostEqual(stats.bounds_min[2], 0.0, places=3)
        self.assertAlmostEqual(stats.dimensions[2], 31.4, places=3)

    def test_right_hand_slots_are_void_and_quadrature_bands_are_solid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            reference_result, reference_output = render_probe(
                "reference",
                directory,
            )
            self.assertEqual(
                reference_result.returncode,
                0,
                reference_result.stdout + reference_result.stderr,
            )
            reference = inspect_binary_stl(reference_output)

            for probe in ("slot_void", "band_solid"):
                with self.subTest(probe=probe):
                    result, output = render_probe(probe, directory)
                    self.assertEqual(
                        result.returncode,
                        0,
                        result.stdout + result.stderr,
                    )
                    stats = inspect_binary_stl(output)
                    self.assertEqual(stats.nonmanifold_edges, 0)
                    self.assertEqual(stats.components, 2)
                    self.assertAlmostEqual(
                        stats.volume,
                        reference.volume,
                        delta=reference.volume * 0.05,
                    )

    def test_flange_entry_is_open_at_face_and_closes_to_bore(self) -> None:
        cases = (
            ("entry_reference_low", "entry_void"),
            ("entry_reference_high", "entry_wall"),
        )
        with tempfile.TemporaryDirectory() as directory:
            for reference_probe, insert_probe in cases:
                with self.subTest(probe=insert_probe):
                    reference_result, reference_output = render_probe(
                        reference_probe,
                        directory,
                    )
                    self.assertEqual(
                        reference_result.returncode,
                        0,
                        reference_result.stdout + reference_result.stderr,
                    )
                    result, output = render_probe(insert_probe, directory)
                    self.assertEqual(
                        result.returncode,
                        0,
                        result.stdout + result.stderr,
                    )
                    reference = inspect_binary_stl(reference_output)
                    stats = inspect_binary_stl(output)
                    self.assertEqual(stats.nonmanifold_edges, 0)
                    self.assertEqual(stats.components, 1)
                    self.assertAlmostEqual(
                        stats.volume,
                        reference.volume,
                        delta=reference.volume * 0.05,
                    )


if __name__ == "__main__":
    unittest.main()
