import math
import os
import platform
import struct
import subprocess
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OPENSCAD_BIN = Path(
    os.environ.get(
        "OPENSCAD_BIN",
        "/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD",
    )
)


def openscad_command() -> list[str]:
    command = [str(OPENSCAD_BIN)]
    if platform.machine() == "arm64" and OPENSCAD_BIN.name == "OpenSCAD":
        command = ["arch", "-x86_64", str(OPENSCAD_BIN)]
    return command


def run_openscad(
    source: Path,
    output: Path,
    defines: tuple[str, ...] = (),
    extra_args: tuple[str, ...] = (),
) -> subprocess.CompletedProcess[str]:
    environment = os.environ.copy()
    environment["OPENSCADPATH"] = str(ROOT)
    command = openscad_command()
    command.extend(["--backend", "Manifold", "--hardwarnings"])
    command.extend(extra_args)
    for define in defines:
        command.extend(["-D", define])
    command.extend(["-o", str(output), str(source)])
    return subprocess.run(
        command,
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )


@dataclass(frozen=True)
class MeshStats:
    triangles: int
    volume: float
    bounds_min: tuple[float, float, float]
    bounds_max: tuple[float, float, float]
    nonmanifold_edges: int

    @property
    def dimensions(self) -> tuple[float, float, float]:
        return tuple(
            high - low
            for low, high in zip(self.bounds_min, self.bounds_max, strict=True)
        )


def _vertex_key(vertex: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(round(value, 5) for value in vertex)


def inspect_binary_stl(path: Path) -> MeshStats:
    data = path.read_bytes()
    if len(data) < 84:
        raise ValueError(f"{path} is not a binary STL")
    triangle_count = struct.unpack_from("<I", data, 80)[0]
    expected_size = 84 + triangle_count * 50
    if len(data) != expected_size:
        raise ValueError(
            f"{path} has {len(data)} bytes; expected {expected_size}"
        )

    edge_counts: Counter[
        tuple[
            tuple[float, float, float],
            tuple[float, float, float],
        ]
    ] = Counter()
    minimum = [math.inf, math.inf, math.inf]
    maximum = [-math.inf, -math.inf, -math.inf]
    signed_volume = 0.0

    for index in range(triangle_count):
        offset = 84 + index * 50 + 12
        values = struct.unpack_from("<9f", data, offset)
        vertices = [
            (values[0], values[1], values[2]),
            (values[3], values[4], values[5]),
            (values[6], values[7], values[8]),
        ]
        for vertex in vertices:
            for axis, value in enumerate(vertex):
                minimum[axis] = min(minimum[axis], value)
                maximum[axis] = max(maximum[axis], value)
        a, b, c = vertices
        signed_volume += (
            a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])
        ) / 6.0
        for start, end in ((a, b), (b, c), (c, a)):
            edge = tuple(sorted((_vertex_key(start), _vertex_key(end))))
            edge_counts[edge] += 1

    return MeshStats(
        triangles=triangle_count,
        volume=abs(signed_volume),
        bounds_min=tuple(minimum),
        bounds_max=tuple(maximum),
        nonmanifold_edges=sum(count != 2 for count in edge_counts.values()),
    )
