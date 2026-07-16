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

for fit in vvloose vloose loose medium tight vtight; do
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
    -D 'Part="driver"' \
    -o "$ROOT/build/helical_insert_driver.stl" \
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
    --camera 65,-90,70,0,0,17 \
    -D 'Part="driver"' \
    -o "$ROOT/build/helical_insert_driver.png" \
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
