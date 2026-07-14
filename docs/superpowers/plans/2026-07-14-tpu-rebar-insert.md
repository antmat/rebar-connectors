# TPU Rebar Insert Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a printable split TPU insert that adapts 11.3 mm rebar to the existing 12.2 mm blind sockets, with three calibrated fit levels and a retaining flange.

**Architecture:** A standalone OpenSCAD model derives a constant wall thickness from socket and rebar diameters, then applies 0.0/0.1/0.2 mm diametric preload while keeping the wall constant. A separate export script produces individual inserts, the three-part fit set, and a visual preview without rerendering the connector models.

**Tech Stack:** OpenSCAD 2026.06.12, Manifold backend, Bash, Python standard-library STL inspection, Bambu TPU for AMS 68D.

## Global Constraints

- Execute feature work in a dedicated Git worktree created from `main`; preserve the user-owned untracked `3way.stl` in the primary checkout.
- Rebar diameter is 11.3 mm and socket diameter is 12.2 mm by default.
- Insert length inside the socket is 26 mm.
- Wall thickness is `(Socket_D_mm - Rebar_D_mm) / 2`, which is 0.45 mm by default.
- Fit preload is 0.0 mm for `loose`, 0.1 mm for `medium`, and 0.2 mm for `tight`.
- The longitudinal slit is 1.0 mm wide and passes through the sleeve and flange.
- The retaining flange is 15 mm in diameter and 1.2 mm thick.
- Print orientation is flange-down with the sleeve vertical; supports are not required.
- Use a shared explicit `$fn` for concentric cylinders so the 0.45 mm wall is geometrically uniform.
- User acceptance remains visual-first; retain the existing six tests and use focused mesh/bounds checks without expanding test infrastructure.
- Preserve all existing final connector artifacts and the user-owned root `3way.stl`.

---

### Task 1: Build and validate the parameterized split insert

**Files:**
- Create: `rebar_insert.scad`

**Interfaces:**
- Consumes: `Part`, `Fit`, `Rebar_D_mm`, `Socket_D_mm`, `Insert_Length_mm`, `Slit_Width_mm`, `Flange_D_mm`, and `Flange_Thickness_mm`.
- Produces: `tpuInsert(fit, markerCount)`, `singleInsert()`, `fitSet()`, `Part="single"`, and `Part="fit_set"`.

- [ ] **Step 1: Create an isolated worktree**

Use `superpowers:using-git-worktrees` and create branch `feature/tpu-rebar-insert` from `main`. Verify the new worktree is clean and that `3way.stl` remains only in the primary checkout.

- [ ] **Step 2: Confirm the model does not exist**

Run:

```bash
test ! -e rebar_insert.scad
```

Expected: exit code 0.

- [ ] **Step 3: Create the OpenSCAD model**

Create `rebar_insert.scad` with:

```openscad
$fn = $preview ? 64 : 128;

/* [Output] */

Part = "fit_set"; // [single, fit_set]
Fit = "medium"; // [loose, medium, tight]

/* [Geometry] */

Rebar_D_mm = 11.3; // [5:0.1:30]
Socket_D_mm = 12.2; // [5:0.1:30]
Insert_Length_mm = 26; // [5:1:29]
Slit_Width_mm = 1; // [0.4:0.1:3]
Flange_D_mm = 15; // [10:0.5:25]
Flange_Thickness_mm = 1.2; // [0.6:0.2:3]

/* [Hidden] */

fitStep = 0.1;
fudge = 0.02;
markerDiameter = 1.2;
markerRadius = Flange_D_mm / 2 - markerDiameter / 4;

function _fitIndex(fit) =
    fit == "loose" ? 0
    : fit == "medium" ? 1
    : fit == "tight" ? 2
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _preload(fit) = _fitIndex(fit) * fitStep;
function _wallThickness() = (Socket_D_mm - Rebar_D_mm) / 2;
function _innerDiameter(fit) = Rebar_D_mm - _preload(fit);
function _outerDiameter(fit) =
    _innerDiameter(fit) + 2 * _wallThickness();

module _validateParameters() {
    assert(Rebar_D_mm > 0, "Rebar_D_mm must be positive");
    assert(Socket_D_mm > Rebar_D_mm,
        "Socket_D_mm must be larger than Rebar_D_mm");
    assert(Insert_Length_mm > 0, "Insert_Length_mm must be positive");
    assert(Slit_Width_mm > 0, "Slit_Width_mm must be positive");
    assert(Flange_D_mm > Socket_D_mm,
        "Flange_D_mm must retain the insert outside the socket");
    assert(Flange_Thickness_mm > 0,
        "Flange_Thickness_mm must be positive");
    assert(_innerDiameter("tight") > 0,
        "Tight preload must leave a positive inner diameter");
    assert(Slit_Width_mm < _outerDiameter("tight"),
        "Slit_Width_mm must be smaller than the insert diameter");
    assert(markerDiameter > 0, "Marker diameter must be positive");
    children();
}

module _markerBumps(count) {
    for (index = [0 : count - 1]) {
        angle = 180 + (index - (count - 1) / 2) * 18;
        translate([
            markerRadius * cos(angle),
            markerRadius * sin(angle),
            0
        ])
            cylinder(d=markerDiameter, h=Flange_Thickness_mm);
    }
}

module tpuInsert(fit, markerCount) {
    innerDiameter = _innerDiameter(fit);
    outerDiameter = _outerDiameter(fit);
    totalHeight = Flange_Thickness_mm + Insert_Length_mm;
    difference() {
        union() {
            cylinder(d=Flange_D_mm, h=Flange_Thickness_mm);
            translate([0, 0, Flange_Thickness_mm - fudge])
                cylinder(
                    d=outerDiameter,
                    h=Insert_Length_mm + fudge
                );
            _markerBumps(markerCount);
        }
        translate([0, 0, -fudge])
            cylinder(d=innerDiameter, h=totalHeight + 2 * fudge);
        translate([0, -Slit_Width_mm / 2, -fudge])
            cube([
                Flange_D_mm / 2 + fudge,
                Slit_Width_mm,
                totalHeight + 2 * fudge
            ]);
    }
}

module singleInsert() {
    tpuInsert(Fit, _fitIndex(Fit) + 1);
}

module fitSet() {
    for (index = [0 : 2]) {
        fit = ["loose", "medium", "tight"][index];
        translate([(index - 1) * 20, 0, 0])
            tpuInsert(fit, index + 1);
    }
}

_validateParameters() {
    if (Part == "single")
        singleInsert();
    else if (Part == "fit_set")
        fitSet();
    else
        assert(false, str("Unsupported Part: ", Part));
}
```

- [ ] **Step 4: Render the two modes and the three individual fits**

Run OpenSCAD with `--backend Manifold --hardwarnings --export-format binstl` for:

```text
Part="single", Fit="loose"
Part="single", Fit="medium"
Part="single", Fit="tight"
Part="fit_set"
```

Write these diagnostic files under `/tmp/tpu-rebar-insert/`. Expected: all four renders exit 0, every top-level object reports `manifold: NoError`, and no warning is emitted.

- [ ] **Step 5: Inspect the diagnostic meshes**

Use a one-off Python standard-library inspector to verify:

- all coordinates are finite;
- every STL has positive signed volume magnitude;
- minimum Z is within 0.001 mm of zero;
- each single insert is 27.2 mm tall;
- `fit_set` contains three spatially separated parts and is narrower than 60 mm;
- loose/medium/tight sleeve outer diameters are 12.2/12.1/12.0 mm before marker and flange geometry.

- [ ] **Step 6: Render and inspect a visual preview**

Render `Part="fit_set"` to `/tmp/tpu-rebar-insert/fit_set.png` at 1600×1200 with an orthographic three-quarter camera. Inspect that all three sleeves are vertical, each slit is continuous, the radial marker bumps read as one/two/three, and no parts intersect.

- [ ] **Step 7: Commit Task 1**

```bash
git add rebar_insert.scad
git commit -m "Add TPU rebar insert model"
```

Expected: clean worktree after the commit.

---

### Task 2: Add reproducible exports and print guidance

**Files:**
- Create: `scripts/render_rebar_insert.sh`
- Modify: `.gitignore`
- Modify: `REBAR_CONNECTORS.md`
- Generate: `build/tpu_insert_loose.stl`
- Generate: `build/tpu_insert_medium.stl`
- Generate: `build/tpu_insert_tight.stl`
- Generate: `build/tpu_insert_fit_set.stl`
- Generate: `build/tpu_insert_fit_set.png`

**Interfaces:**
- Consumes: `Part` and `Fit` from `rebar_insert.scad`.
- Produces: four printable STL artifacts, one visual PNG, and documented Bambu Studio settings.

- [ ] **Step 1: Add the export script**

Create `scripts/render_rebar_insert.sh` with:

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

for fit in loose medium tight; do
    run_scad \
        --backend Manifold \
        --hardwarnings \
        --export-format binstl \
        -D 'Part="single"' \
        -D "Fit=\"$fit\"" \
        -o "$ROOT/build/tpu_insert_$fit.stl" \
        "$ROOT/rebar_insert.scad"
done

run_scad \
    --backend Manifold \
    --hardwarnings \
    --export-format binstl \
    -D 'Part="fit_set"' \
    -o "$ROOT/build/tpu_insert_fit_set.stl" \
    "$ROOT/rebar_insert.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 70,-90,65,0,0,12 \
    -D 'Part="fit_set"' \
    -o "$ROOT/build/tpu_insert_fit_set.png" \
    "$ROOT/rebar_insert.scad"
```

Make it executable:

```bash
chmod +x scripts/render_rebar_insert.sh
```

- [ ] **Step 2: Track only the final insert artifacts**

Append these exceptions after `build/*` in `.gitignore`:

```gitignore
!build/tpu_insert_loose.stl
!build/tpu_insert_medium.stl
!build/tpu_insert_tight.stl
!build/tpu_insert_fit_set.stl
!build/tpu_insert_fit_set.png
```

- [ ] **Step 3: Document installation and printing**

Add `## TPU-вкладыши для арматуры 11,3 мм` to `REBAR_CONNECTORS.md`. Include:

- the purpose of `rebar_insert.scad`;
- one/two/three marker mapping to loose/medium/tight;
- the instruction to print `fit_set` first and test it in a real connector;
- Bambu TPU for AMS 68D, dried before use;
- 0.4 mm nozzle, 0.20 mm layer, Arachne wall generator, supports disabled;
- mandatory slicer-preview check that the 0.45 mm sleeve is one continuous perimeter;
- flange-down orientation;
- the statement that cut lengths from `rebar_cut_list.py` do not change because the insert bore is through-going;
- the export command `scripts/render_rebar_insert.sh` and the five generated artifact names.

- [ ] **Step 4: Generate the final artifacts**

Run:

```bash
scripts/render_rebar_insert.sh
```

Expected: all four STL files and the PNG are non-empty; OpenSCAD reports no errors or warnings.

- [ ] **Step 5: Run full verification**

Run:

```bash
PYTHONPATH=tests python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n scripts/render_rebar_insert.sh
test -x scripts/render_rebar_insert.sh
scripts/rebar_cut_list.py --diameter 3000 --height 2000
```

Expected: 6/6 tests pass, Bash syntax is valid, the exporter is executable, and the cut list remains 32 pieces totaling 47.331 m for the example.

Repeat the Task 1 mesh inspection on the five final artifacts. Inspect `build/tpu_insert_fit_set.png` and confirm the visual acceptance criteria.

- [ ] **Step 6: Commit Task 2**

```bash
git add .gitignore REBAR_CONNECTORS.md scripts/render_rebar_insert.sh \
    build/tpu_insert_loose.stl build/tpu_insert_medium.stl \
    build/tpu_insert_tight.stl build/tpu_insert_fit_set.stl \
    build/tpu_insert_fit_set.png
git commit -m "Add TPU insert exports and print guide"
```

Expected: clean feature worktree with two implementation commits after the design/plan commits.

---

## Completion Criteria

- The OpenSCAD model exposes `single` and `fit_set` modes and three fit levels.
- The default dimensions match the approved 11.3 mm rebar and 12.2 mm socket design.
- Every sleeve has a continuous 1.0 mm longitudinal slit and a retaining flange.
- One/two/three marker bumps distinguish loose/medium/tight without interfering with the slit or seating face.
- All final STL meshes render through Manifold with positive volume and minimum Z=0.
- The fit set contains three separate, nonintersecting parts.
- The 0.45 mm wall is documented as requiring one continuous Arachne perimeter in slicer preview.
- Existing connector tests and the cut-list example remain unchanged.
- User-owned `3way.stl` remains untouched and untracked in the primary checkout.
