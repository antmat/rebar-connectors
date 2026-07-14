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
