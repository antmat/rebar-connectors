# Helical Rebar Insert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the failed thin TPU sleeve with a printable right-hand, two-start PETG helical cage that matches the measured rebar winding and provides three short calibration fits before a full-length insert is printed.

**Architecture:** `rebar_insert.scad` generates a thick cylindrical cage whose two through-slots follow the measured 45 mm lead and expose the 2.5 mm winding ribs instead of covering them with a fragile membrane. A solid flange contains non-through internal grooves, connects both helical bands, and remains outside the existing 12.2 mm socket. Focused OpenSCAD tests verify dimensions, connected components, handedness, slot voids, and band material before the export script publishes calibration and full-length artifacts.

**Tech Stack:** OpenSCAD 2026.06.12 with Manifold backend, Python 3 standard library and `unittest`, Bash, binary STL inspection, PETG.

## Global Constraints

- Work only in the existing isolated worktree on branch `feature/helical-rebar-insert`.
- Preserve user-owned untracked `3way.stl` and `rebar_insert.stl` in the primary checkout.
- Rebar core diameter is 9.1 mm; maximum diameter over the winding is 11.3 mm.
- The winding has two right-hand starts, a 180° phase offset, 45 mm lead per start, and 2.5 mm rib width.
- Clockwise rotation viewed from the outer flange face must advance the cage along the rebar, like a conventional right-hand nut.
- Socket diameter is 12.2 mm and usable depth is 30 mm.
- Cage outside diameter is 12.0 mm; core bore is 9.5 mm.
- Full working length is 29 mm; calibration working length is 12 mm.
- Flange is 15 mm diameter and 2.4 mm thick.
- Calibration slot widths are 2.9/3.1/3.3 mm for `narrow`/`medium`/`wide`; `medium` is the default.
- All printable parts use PETG, a 0.4 mm nozzle, 0.20 mm layers, at least four perimeters, flange-down orientation, and no supports by default.
- Preserve the existing connector models, six connector tests, and cut-list calculation.
- Remove the failed TPU sleeve artifacts from the recommended build outputs; Git history preserves the old design.

---

### Task 1: Replace the sleeve with a tested two-start helical cage

**Files:**
- Modify: `tests/scad_test_utils.py`
- Create: `tests/helical_insert_probes.scad`
- Create: `tests/test_helical_rebar_insert.py`
- Modify: `rebar_insert.scad`

**Interfaces:**
- Consumes: measured dimensions from `docs/superpowers/specs/2026-07-15-helical-rebar-insert-design.md` and `run_openscad()` / `inspect_binary_stl()` from `tests/scad_test_utils.py`.
- Produces: `helicalInsert(slotWidth, workingLength, markerCount)`, `calibrationSingle()`, `calibrationSet()`, `fullInsert()`, `assemblyPreview()`, `Part="calibration_single|calibration_set|full|assembly_preview"`, `Fit="narrow|medium|wide"`, numeric diagnostics, and `MeshStats.components`.

- [ ] **Step 1: Extend binary STL inspection with connected-component counting**

Change the collection import and `MeshStats` definition in `tests/scad_test_utils.py` to:

```python
from collections import Counter, defaultdict, deque


@dataclass(frozen=True)
class MeshStats:
    triangles: int
    volume: float
    bounds_min: tuple[float, float, float]
    bounds_max: tuple[float, float, float]
    nonmanifold_edges: int
    components: int

    @property
    def dimensions(self) -> tuple[float, float, float]:
        return tuple(
            high - low
            for low, high in zip(self.bounds_min, self.bounds_max, strict=True)
        )
```

Inside `inspect_binary_stl()`, initialize `triangle_vertices` immediately before the triangle loop:

```python
    triangle_vertices: list[
        tuple[
            tuple[float, float, float],
            tuple[float, float, float],
            tuple[float, float, float],
        ]
    ] = []
```

Append each parsed triangle immediately after `vertices` is constructed:

```python
        triangle_vertices.append(tuple(vertices))
```

After the triangle loop and before the return, add:

```python
    triangles_by_vertex: defaultdict[
        tuple[float, float, float],
        list[int],
    ] = defaultdict(list)
    for triangle_index, vertices in enumerate(triangle_vertices):
        for vertex in vertices:
            triangles_by_vertex[_vertex_key(vertex)].append(triangle_index)

    unseen = set(range(triangle_count))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            triangle_index = queue.popleft()
            for vertex in triangle_vertices[triangle_index]:
                for neighbor in triangles_by_vertex[_vertex_key(vertex)]:
                    if neighbor in unseen:
                        unseen.remove(neighbor)
                        queue.append(neighbor)
```

Add `components=components` to the returned `MeshStats` instance.

- [ ] **Step 2: Add independent right-hand slot and band probes**

Create `tests/helical_insert_probes.scad`:

```openscad
include <../rebar_insert.scad>

Probe = "reference"; // [reference, slot_void, band_solid]

probeDiameter = 0.3;
probeZ = Flange_Thickness_mm + 8;
probeRadius = (_coreBoreDiameter() + Cage_D_mm) / 4;
rightHandAngle = 360 * probeZ / Helix_Lead_mm;

module probePair(angleOffset) {
    for (start = [0 : 1]) {
        angle = rightHandAngle + start * 180 + angleOffset;
        rotate([0, 0, angle])
            translate([probeRadius, 0, probeZ])
                sphere(d=probeDiameter, $fn=48);
    }
}

module insertForProbe() {
    helicalInsert(
        slotWidth=3.1,
        workingLength=Full_Length_mm,
        markerCount=2
    );
}

if (Probe == "reference")
    probePair(0);
else if (Probe == "slot_void")
    difference() {
        probePair(0);
        insertForProbe();
    }
else if (Probe == "band_solid")
    intersection() {
        probePair(90);
        insertForProbe();
    }
else
    assert(false, str("Unsupported Probe: ", Probe));
```

The test runner will pass `Render_Model=false` so the included model exposes its modules without rendering its normal top-level output.

- [ ] **Step 3: Write the failing helical cage tests**

Create `tests/test_helical_rebar_insert.py`:

```python
import re
import tempfile
import unittest
from pathlib import Path

from scad_test_utils import ROOT, inspect_binary_stl, run_openscad

MODEL = ROOT / "rebar_insert.scad"
PROBE_MODEL = ROOT / "tests" / "helical_insert_probes.scad"

FIT_WIDTHS = {
    "narrow": 2.9,
    "medium": 3.1,
    "wide": 3.3,
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
    def test_calibration_metrics_match_measured_rebar(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            for fit, expected_width in FIT_WIDTHS.items():
                with self.subTest(fit=fit):
                    metrics = read_metrics(
                        "calibration_single",
                        fit,
                        directory,
                    )
                    self.assertAlmostEqual(metrics["core_d"], 9.1)
                    self.assertAlmostEqual(metrics["bore_d"], 9.5)
                    self.assertAlmostEqual(metrics["rebar_max_d"], 11.3)
                    self.assertAlmostEqual(metrics["rib_width"], 2.5)
                    self.assertAlmostEqual(metrics["cage_d"], 12.0)
                    self.assertAlmostEqual(metrics["slot_width"], expected_width)
                    self.assertAlmostEqual(metrics["working_length"], 12.0)
                    self.assertAlmostEqual(metrics["lead"], 45.0)
                    self.assertEqual(metrics["starts"], 2)
                    self.assertEqual(metrics["hand_sign"], 1)

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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 4: Run the focused tests and confirm the old sleeve fails the contract**

Run:

```bash
PYTHONPATH=tests python3 -m unittest discover \
    -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: failures because the current model rejects `Part="calibration_single"`, does not emit the new diagnostics, and has no `helicalInsert()` module.

- [ ] **Step 5: Implement the helical cage model**

Replace `rebar_insert.scad` with:

```openscad
$fn = $preview ? 64 : 128;

/* [Output] */

Part = "calibration_set"; // [calibration_single, calibration_set, full, assembly_preview]
Fit = "medium"; // [narrow, medium, wide]
Diagnostics = false;

/* [Measured rebar] */

Core_D_mm = 9.1; // [5:0.1:20]
Core_Clearance_mm = 0.4; // [0.1:0.1:1]
Rebar_Max_D_mm = 11.3; // [5:0.1:25]
Rib_Width_mm = 2.5; // [0.5:0.1:6]
Helix_Lead_mm = 45; // [10:1:100]
Helix_Starts = 2; // [1:1:4]
Helix_Hand = "right"; // [right, left]

/* [Socket and cage] */

Socket_D_mm = 12.2; // [5:0.1:30]
Socket_Depth_mm = 30; // [5:1:50]
Cage_D_mm = 12; // [5:0.1:30]
Full_Length_mm = 29; // [5:1:40]
Calibration_Length_mm = 12; // [5:1:20]
Flange_D_mm = 15; // [10:0.5:25]
Flange_Thickness_mm = 2.4; // [0.8:0.2:5]

/* [Hidden] */

Render_Model = true;
Rib_Radial_Clearance_mm = 0.15;
fitClearanceStart = 0.2;
fitClearanceStep = 0.1;
fudge = 0.02;
markerDiameter = 1.2;
markerRadius = Flange_D_mm / 2;
previewSocketWall = 4;

function _fitIndex(fit) =
    fit == "narrow" ? 0
    : fit == "medium" ? 1
    : fit == "wide" ? 2
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _slotWidth(fit) =
    Rib_Width_mm
    + 2 * (fitClearanceStart + _fitIndex(fit) * fitClearanceStep);
function _coreBoreDiameter() = Core_D_mm + Core_Clearance_mm;
function _handSign() =
    Helix_Hand == "right" ? 1
    : Helix_Hand == "left" ? -1
    : assert(false, str("Unsupported Helix_Hand: ", Helix_Hand)) 0;
function _twist(height) =
    _handSign() * 360 * height / Helix_Lead_mm;
function _slices(height) = max(32, ceil(height / 0.25));
function _grooveOuterRadius() =
    Rebar_Max_D_mm / 2 + Rib_Radial_Clearance_mm;
function _selectedWorkingLength() =
    Part == "calibration_single" || Part == "calibration_set"
    ? Calibration_Length_mm
    : Full_Length_mm;

module _validateParameters() {
    assert(Core_D_mm > 0, "Core_D_mm must be positive");
    assert(Core_Clearance_mm > 0,
        "Core_Clearance_mm must be positive");
    assert(Rebar_Max_D_mm > Core_D_mm,
        "Rebar_Max_D_mm must exceed Core_D_mm");
    assert(Rib_Width_mm > 0, "Rib_Width_mm must be positive");
    assert(Helix_Lead_mm > 0, "Helix_Lead_mm must be positive");
    assert(Helix_Starts >= 1, "Helix_Starts must be at least one");
    assert(Helix_Hand == "right" || Helix_Hand == "left",
        "Helix_Hand must be right or left");
    assert(Socket_D_mm > Cage_D_mm,
        "Cage_D_mm must be smaller than Socket_D_mm");
    assert(Cage_D_mm > _coreBoreDiameter(),
        "Cage_D_mm must exceed the core bore");
    assert(_grooveOuterRadius() < Cage_D_mm / 2,
        "Radial rib clearance must stay inside Cage_D_mm");
    assert(Full_Length_mm > 0 && Full_Length_mm < Socket_Depth_mm,
        "Full_Length_mm must be positive and shorter than the socket");
    assert(Calibration_Length_mm > 0,
        "Calibration_Length_mm must be positive");
    assert(Flange_D_mm > Socket_D_mm,
        "Flange_D_mm must retain the cage outside the socket");
    assert(Flange_Thickness_mm > 0,
        "Flange_Thickness_mm must be positive");
    assert(_slotWidth("narrow") > Rib_Width_mm,
        "Every slot must be wider than the measured rib");
    _fitIndex(Fit);
    children();
}

module _markerBumps(count) {
    for (index = [0 : count - 1]) {
        angle = 270 + (index - (count - 1) / 2) * 18;
        rotate([0, 0, angle])
            translate([markerRadius, 0, 0])
                cylinder(d=markerDiameter, h=Flange_Thickness_mm);
    }
}

module _helicalCutters(slotWidth, totalHeight, outerRadius) {
    innerRadius = _coreBoreDiameter() / 2 - fudge;
    radialDepth = outerRadius - innerRadius + fudge;
    for (start = [0 : Helix_Starts - 1]) {
        rotate([0, 0, start * 360 / Helix_Starts])
            linear_extrude(
                height=totalHeight + fudge,
                twist=_twist(totalHeight + fudge),
                slices=_slices(totalHeight),
                convexity=20
            )
                translate([innerRadius, -slotWidth / 2])
                    square([radialDepth, slotWidth]);
    }
}

module _throughSlots(slotWidth, totalHeight) {
    extent = Flange_D_mm + 2;
    intersection() {
        _helicalCutters(
            slotWidth=slotWidth,
            totalHeight=totalHeight,
            outerRadius=Cage_D_mm / 2 + fudge
        );
        translate([
            -extent,
            -extent,
            Flange_Thickness_mm
        ])
            cube([
                2 * extent,
                2 * extent,
                totalHeight - Flange_Thickness_mm + 2 * fudge
            ]);
    }
}

module helicalInsert(slotWidth, workingLength, markerCount) {
    totalHeight = Flange_Thickness_mm + workingLength;
    difference() {
        union() {
            cylinder(d=Flange_D_mm, h=Flange_Thickness_mm);
            translate([0, 0, Flange_Thickness_mm - fudge])
                cylinder(
                    d=Cage_D_mm,
                    h=workingLength + fudge
                );
            _markerBumps(markerCount);
        }
        translate([0, 0, -fudge])
            cylinder(
                d=_coreBoreDiameter(),
                h=totalHeight + 2 * fudge
            );
        _helicalCutters(
            slotWidth=slotWidth,
            totalHeight=totalHeight,
            outerRadius=_grooveOuterRadius()
        );
        _throughSlots(slotWidth, totalHeight);
    }
}

module calibrationSingle() {
    helicalInsert(
        slotWidth=_slotWidth(Fit),
        workingLength=Calibration_Length_mm,
        markerCount=_fitIndex(Fit) + 1
    );
}

module calibrationSet() {
    for (index = [0 : 2]) {
        fit = ["narrow", "medium", "wide"][index];
        translate([(index - 1) * 20, 0, 0])
            helicalInsert(
                slotWidth=_slotWidth(fit),
                workingLength=Calibration_Length_mm,
                markerCount=index + 1
            );
    }
}

module fullInsert() {
    helicalInsert(
        slotWidth=_slotWidth(Fit),
        workingLength=Full_Length_mm,
        markerCount=_fitIndex(Fit) + 1
    );
}

module _rebarModel(height) {
    ribHeight = (Rebar_Max_D_mm - Core_D_mm) / 2;
    union() {
        cylinder(d=Core_D_mm, h=height);
        for (start = [0 : Helix_Starts - 1]) {
            rotate([0, 0, start * 360 / Helix_Starts])
                linear_extrude(
                    height=height,
                    twist=_twist(height),
                    slices=_slices(height),
                    convexity=20
                )
                    translate([Core_D_mm / 2 + ribHeight / 2, 0])
                        scale([ribHeight / Rib_Width_mm, 1])
                            circle(d=Rib_Width_mm);
        }
    }
}

module assemblyPreview() {
    totalHeight = Flange_Thickness_mm + Full_Length_mm;
    color([0.95, 0.65, 0.1])
        fullInsert();
    color([0.35, 0.35, 0.38])
        translate([0, 0, -4])
            _rebarModel(totalHeight + 8);
    color([0.1, 0.65, 0.8, 0.25])
        translate([0, 0, Flange_Thickness_mm])
            difference() {
                cylinder(
                    d=Socket_D_mm + 2 * previewSocketWall,
                    h=Socket_Depth_mm
                );
                translate([0, 0, -fudge])
                    cylinder(
                        d=Socket_D_mm,
                        h=Socket_Depth_mm + 2 * fudge
                    );
            }
}

module _diagnostics() {
    if (Diagnostics)
        echo(str(
            "core_d=", Core_D_mm,
            " bore_d=", _coreBoreDiameter(),
            " rebar_max_d=", Rebar_Max_D_mm,
            " rib_width=", Rib_Width_mm,
            " cage_d=", Cage_D_mm,
            " slot_width=", _slotWidth(Fit),
            " working_length=", _selectedWorkingLength(),
            " lead=", Helix_Lead_mm,
            " starts=", Helix_Starts,
            " hand_sign=", _handSign(),
            " flange_d=", Flange_D_mm,
            " flange_t=", Flange_Thickness_mm
        ));
}

if (Render_Model)
    _validateParameters() {
        _diagnostics();
        if (Part == "calibration_single")
            calibrationSingle();
        else if (Part == "calibration_set")
            calibrationSet();
        else if (Part == "full")
            fullInsert();
        else if (Part == "assembly_preview")
            assemblyPreview();
        else
            assert(false, str("Unsupported Part: ", Part));
    }
```

- [ ] **Step 6: Run the focused tests and fix only contract failures**

Run:

```bash
PYTHONPATH=tests python3 -m unittest discover \
    -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: 5 tests pass. OpenSCAD output for every rendered STL reports `Status: NoError`; no hard warning is emitted.

- [ ] **Step 7: Render and visually inspect the assembly diagnostic**

Run:

```bash
mkdir -p /tmp/helical-rebar-insert
arch -x86_64 /Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 70,-90,70,0,0,14 \
    -D 'Part="assembly_preview"' \
    -o /tmp/helical-rebar-insert/assembly.png \
    rebar_insert.scad
```

Inspect `/tmp/helical-rebar-insert/assembly.png` with `view_image`. Confirm that both winding ribs occupy the two open slots, the cage bands are continuous, the slots rise in the right-hand direction, the flange is outside the socket, and the rebar can continue to the blind stop.

- [ ] **Step 8: Run the complete baseline plus new tests**

Run:

```bash
PYTHONPATH=tests python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Expected: 11 tests pass: the existing 6 plus the new 5.

- [ ] **Step 9: Commit the tested model**

```bash
git add rebar_insert.scad tests/scad_test_utils.py \
    tests/helical_insert_probes.scad tests/test_helical_rebar_insert.py
git commit -m "Replace TPU sleeve with helical PETG cage"
```

Expected: the commit contains only the model and focused test infrastructure.

---

### Task 2: Publish calibration artifacts and PETG print guidance

**Files:**
- Modify: `scripts/render_rebar_insert.sh`
- Modify: `.gitignore`
- Modify: `REBAR_CONNECTORS.md`
- Delete: `build/tpu_insert_loose.stl`
- Delete: `build/tpu_insert_medium.stl`
- Delete: `build/tpu_insert_tight.stl`
- Delete: `build/tpu_insert_fit_set.stl`
- Delete: `build/tpu_insert_fit_set.png`
- Generate: `build/helical_insert_calibration_narrow.stl`
- Generate: `build/helical_insert_calibration_medium.stl`
- Generate: `build/helical_insert_calibration_wide.stl`
- Generate: `build/helical_insert_calibration_set.stl`
- Generate: `build/helical_insert_full_medium.stl`
- Generate: `build/helical_insert_calibration_set.png`
- Generate: `build/helical_insert_full_medium.png`
- Generate: `build/helical_insert_assembly_preview.png`

**Interfaces:**
- Consumes: `Part` and `Fit` modes implemented in Task 1.
- Produces: one reproducible export command, five PETG STL artifacts, three PNG diagnostics, updated tracked-artifact rules, and the physical calibration workflow.

- [ ] **Step 1: Demonstrate that the old exporter does not satisfy the new artifact contract**

Run:

```bash
scripts/render_rebar_insert.sh
test -s build/helical_insert_calibration_set.stl
```

Expected: the exporter itself exits 0 but the `test` command exits 1 because only the obsolete `tpu_insert_*` files are produced.

- [ ] **Step 2: Replace the exporter**

Replace `scripts/render_rebar_insert.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OPENSCAD_BIN=${OPENSCAD_BIN:-/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD}

run_scad() {
    if [[ $(uname -s) == Darwin \
        && $(uname -m) == arm64 \
        && $(basename "$OPENSCAD_BIN") == OpenSCAD ]]; then
        arch -x86_64 "$OPENSCAD_BIN" "$@"
    else
        "$OPENSCAD_BIN" "$@"
    fi
}

mkdir -p "$ROOT/build"

for fit in narrow medium wide; do
    run_scad \
        --backend Manifold \
        --hardwarnings \
        --export-format binstl \
        -D 'Part="calibration_single"' \
        -D "Fit=\"$fit\"" \
        -o "$ROOT/build/helical_insert_calibration_$fit.stl" \
        "$ROOT/rebar_insert.scad"
done

run_scad \
    --backend Manifold \
    --hardwarnings \
    --export-format binstl \
    -D 'Part="calibration_set"' \
    -o "$ROOT/build/helical_insert_calibration_set.stl" \
    "$ROOT/rebar_insert.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --export-format binstl \
    -D 'Part="full"' \
    -D 'Fit="medium"' \
    -o "$ROOT/build/helical_insert_full_medium.stl" \
    "$ROOT/rebar_insert.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 65,-90,58,0,0,7 \
    -D 'Part="calibration_set"' \
    -o "$ROOT/build/helical_insert_calibration_set.png" \
    "$ROOT/rebar_insert.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 65,-90,70,0,0,15 \
    -D 'Part="full"' \
    -D 'Fit="medium"' \
    -o "$ROOT/build/helical_insert_full_medium.png" \
    "$ROOT/rebar_insert.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 70,-90,70,0,0,14 \
    -D 'Part="assembly_preview"' \
    -o "$ROOT/build/helical_insert_assembly_preview.png" \
    "$ROOT/rebar_insert.scad"
```

Retain executable mode `100755`.

- [ ] **Step 3: Replace tracked artifact exceptions**

Replace the five `!build/tpu_insert_*` lines in `.gitignore` with:

```gitignore
!build/helical_insert_calibration_narrow.stl
!build/helical_insert_calibration_medium.stl
!build/helical_insert_calibration_wide.stl
!build/helical_insert_calibration_set.stl
!build/helical_insert_full_medium.stl
!build/helical_insert_calibration_set.png
!build/helical_insert_full_medium.png
!build/helical_insert_assembly_preview.png
```

- [ ] **Step 4: Replace the failed TPU instructions**

Replace the entire `## TPU-вкладыши для арматуры 11,3 мм` section in `REBAR_CONNECTORS.md` with:

```markdown
## Винтовая PETG-клетка для рифлёной арматуры

Файл `rebar_insert.scad` создаёт правую двухзаходную клетку для партии арматуры
с сердцевиной около 9,1 мм и диаметром 11,3 мм по двум навитым рёбрам. Ширина
ребра — 2,5 мм, ход каждого захода — 45 мм, сдвиг между заходами — 180°.

Клетка не закрывает вершины навивки тонкой оболочкой. Рёбра проходят через две
сквозные винтовые прорези, а пространство над сердцевиной заполняют толстые
PETG-ленты с наружным диаметром 12,0 мм. Усиленный буртик Ø15 × 2,4 мм соединяет
ленты и остаётся снаружи канала.

Сначала напечатайте `helical_insert_calibration_set.stl`. Набор содержит три
коротких образца:

| Метка | Вариант | Ширина прорези |
|---|---|---:|
| 1 выступ | `narrow` | 2,9 мм |
| 2 выступа | `medium` | 3,1 мм |
| 3 выступа | `wide` | 3,3 мм |

Начните со среднего образца. Если он заклинивает, попробуйте широкий; если
заметно люфтит — узкий. Подходящий образец должен навинчиваться рукой по часовой
стрелке, без побеления или трещин PETG, и вместе с арматурой входить рукой в
реальное крепление. Не продавливайте заклинивший образец инструментом.

Рекомендуемые начальные настройки:

- материал — PETG;
- сопло — 0,4 мм;
- слой — 0,20 мм;
- генератор стенок — Arachne;
- число периметров в настройке — 3; Arachne может объединить их в меньшее число
  более широких линий;
- поддержки — выключены;
- ориентация — буртиком на столе.

Перед печатью проверьте в предпросмотре слайсера, что обе винтовые ленты
непрерывны по всей высоте. Полноразмерный файл по умолчанию использует среднюю
прорезь 3,1 мм; после калибровки нужный вариант можно выбрать параметром `Fit`
в OpenSCAD и экспортировать повторно.

Готовые файлы создаются командой:

```bash
scripts/render_rebar_insert.sh
```

Скрипт экспортирует три отдельных образца, общий калибровочный набор,
полноразмерную среднюю клетку и три контрольных PNG. Центральный проход остаётся
сквозным, поэтому арматура доходит до прежнего глухого упора и длины из
`scripts/rebar_cut_list.py` не меняются.
```

- [ ] **Step 5: Remove obsolete artifacts and generate the new set**

Run:

```bash
git rm build/tpu_insert_loose.stl \
    build/tpu_insert_medium.stl \
    build/tpu_insert_tight.stl \
    build/tpu_insert_fit_set.stl \
    build/tpu_insert_fit_set.png
scripts/render_rebar_insert.sh
```

Expected: eight `build/helical_insert_*` files are non-empty. Every OpenSCAD invocation exits 0, every STL reports `Status: NoError`, and no warning is emitted.

- [ ] **Step 6: Verify the exported files and script contract**

Run:

```bash
bash -n scripts/render_rebar_insert.sh
test -x scripts/render_rebar_insert.sh
for file in \
    build/helical_insert_calibration_narrow.stl \
    build/helical_insert_calibration_medium.stl \
    build/helical_insert_calibration_wide.stl \
    build/helical_insert_calibration_set.stl \
    build/helical_insert_full_medium.stl \
    build/helical_insert_calibration_set.png \
    build/helical_insert_full_medium.png \
    build/helical_insert_assembly_preview.png; do
    test -s "$file"
done
```

Expected: every command exits 0.

- [ ] **Step 7: Inspect all three final PNGs**

Open these files with `view_image`:

```text
build/helical_insert_calibration_set.png
build/helical_insert_full_medium.png
build/helical_insert_assembly_preview.png
```

Confirm that the calibration set contains three separated flange-down parts with one/two/three markers, the full cage has two continuous right-hand bands, the two winding ribs sit in open slots, and the flange remains outside the translucent socket.

- [ ] **Step 8: Run final regression and cut-list verification**

Run:

```bash
PYTHONPATH=tests python3 -m unittest discover -s tests -p 'test_*.py' -v
scripts/rebar_cut_list.py --diameter 3000 --height 2000
git diff --check
git status --short
```

Expected: 11 tests pass; the cut list remains 32 pieces totaling 47.331 m; only the intended model, tests, exporter, documentation, ignore rules, artifact deletions, and new artifacts are changed.

- [ ] **Step 9: Commit the published PETG workflow**

```bash
git add .gitignore REBAR_CONNECTORS.md scripts/render_rebar_insert.sh \
    build/helical_insert_calibration_narrow.stl \
    build/helical_insert_calibration_medium.stl \
    build/helical_insert_calibration_wide.stl \
    build/helical_insert_calibration_set.stl \
    build/helical_insert_full_medium.stl \
    build/helical_insert_calibration_set.png \
    build/helical_insert_full_medium.png \
    build/helical_insert_assembly_preview.png
git commit -m "Publish helical PETG insert calibration set"
```

Expected: the feature worktree is clean after the commit. The primary checkout still contains the untouched untracked `3way.stl` and `rebar_insert.stl`.

---

## Completion Criteria

- The failed thin C-shaped TPU sleeve is replaced by a right-hand, two-start PETG cage.
- Two through-slots have 45 mm lead, 180° phase offset, and selected width 2.9/3.1/3.3 mm.
- The cage bore is 9.5 mm, band outside diameter is 12.0 mm, full working length is 29 mm, and flange is 15 × 2.4 mm.
- Clockwise rotation viewed from the outer flange face advances the cage along the rebar.
- Calibration set contains three separate 12 mm working-length parts with readable markers.
- Each individual STL is one connected manifold component; the set has three components; all start at Z=0 and have positive volume.
- Slot probes confirm voids at both right-hand helical paths and solid material 90° away.
- PETG print and physical acceptance instructions are documented.
- Obsolete TPU build artifacts are no longer recommended or tracked.
- Existing connector tests and the 47.331 m cut-list example remain unchanged.
- User-owned `3way.stl` and `rebar_insert.stl` remain untouched and untracked in the primary checkout.
