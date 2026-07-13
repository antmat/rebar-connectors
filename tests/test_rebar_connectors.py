import math
import re
import tempfile
import unittest
from pathlib import Path

from scad_test_utils import ROOT, inspect_binary_stl, run_openscad

MODEL = ROOT / "rebar_connectors.scad"
PROBE_MODEL = ROOT / "tests" / "lower_socket_probes.scad"

PORT_COUNT = 3
NOMINAL_HOLE_D_MM = 12.2
NOMINAL_SOCKET_DEPTH_MM = 30.0
NOMINAL_ENTRY_CHAMFER_MM = 1.0
GO_GAUGE_D_MM = 12.0
NO_GO_GAUGE_D_MM = 12.6
GO_STOP_CLEARANCE_MM = 0.2
GO_OUTSIDE_EXTENSION_MM = 2.0
NO_GO_END_MARGIN_MM = 1.0
STOP_PROBE_GAP_MM = 0.2
STOP_PROBE_LENGTH_MM = 0.5

# Covers independent cylinder tessellation and Manifold boolean rounding.
PROBE_VOLUME_RELATIVE_TOLERANCE = 0.02


def render_part(part: str, directory: str):
    output = Path(directory) / f"{part}.stl"
    result = run_openscad(
        MODEL,
        output,
        defines=(f'Part="{part}"',),
        extra_args=("--export-format", "binstl"),
    )
    return result, output


def read_metrics(part: str, directory: str) -> dict[str, float]:
    output = Path(directory) / f"{part}.echo"
    result = run_openscad(
        MODEL,
        output,
        defines=(f'Part="{part}"', "Diagnostics=true"),
    )
    if result.returncode != 0:
        raise AssertionError(result.stdout + result.stderr)
    values = {}
    for name, value in re.findall(r"([a-z_]+)=([0-9.]+)", output.read_text()):
        values[name] = float(value)
    return values


def render_probe(probe: str, directory: str):
    output = Path(directory) / f"lower_socket_{probe}.stl"
    result = run_openscad(
        PROBE_MODEL,
        output,
        defines=(f'Probe="{probe}"',),
        extra_args=("--export-format", "binstl"),
    )
    return result, output


def cylinder_volume(diameter: float, length: float) -> float:
    return math.pi * diameter**2 * length / 4


class LowerConnectorTest(unittest.TestCase):
    def test_lower_connector_defaults_and_channels(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            metrics = read_metrics("lower_3way", directory)
        self.assertEqual(metrics["ports"], 3)
        self.assertAlmostEqual(metrics["hole_d"], 12.2, places=6)
        self.assertAlmostEqual(metrics["depth"], 30.0, places=6)
        self.assertAlmostEqual(metrics["outer_d"], 20.2, places=6)
        self.assertGreaterEqual(metrics["actual_web"], 3.0)

    def test_lower_connector_is_closed_printable_geometry(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_part("lower_3way", directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertGreater(stats.triangles, 100)
        self.assertGreater(stats.volume, 1_000)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertGreater(min(stats.dimensions), 20.2)
        self.assertLess(max(stats.dimensions), 150)


class LowerSocketProbeTest(unittest.TestCase):
    def assert_probe_volume(self, probe: str, expected_volume: float) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result, output = render_probe(probe, directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            stats = inspect_binary_stl(output)
        self.assertEqual(stats.nonmanifold_edges, 0)
        self.assertAlmostEqual(
            stats.volume,
            expected_volume,
            delta=expected_volume * PROBE_VOLUME_RELATIVE_TOLERANCE,
        )

    def test_near_nominal_go_gauge_fits_all_three_sockets(self) -> None:
        probe_length = (
            NOMINAL_SOCKET_DEPTH_MM
            - GO_STOP_CLEARANCE_MM
            + GO_OUTSIDE_EXTENSION_MM
        )
        expected_volume = PORT_COUNT * cylinder_volume(
            GO_GAUGE_D_MM,
            probe_length,
        )
        self.assert_probe_volume("go", expected_volume)

    def test_oversize_no_go_gauge_hits_all_three_socket_walls(self) -> None:
        probe_length = (
            NOMINAL_SOCKET_DEPTH_MM
            - NOMINAL_ENTRY_CHAMFER_MM
            - 2 * NO_GO_END_MARGIN_MM
        )
        expected_volume = PORT_COUNT * (
            cylinder_volume(NO_GO_GAUGE_D_MM, probe_length)
            - cylinder_volume(NOMINAL_HOLE_D_MM, probe_length)
        )
        self.assert_probe_volume("no_go", expected_volume)

    def test_probes_immediately_behind_all_three_blind_stops_are_solid(self) -> None:
        expected_volume = PORT_COUNT * cylinder_volume(
            GO_GAUGE_D_MM,
            STOP_PROBE_LENGTH_MM,
        )
        self.assert_probe_volume("stop", expected_volume)


if __name__ == "__main__":
    unittest.main()
