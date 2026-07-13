#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OPENSCAD_BIN=${OPENSCAD_BIN:-/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD}
export OPENSCADPATH="$ROOT${OPENSCADPATH:+:$OPENSCADPATH}"

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

for part in lower_3way upper_4way apex_8way; do
    run_scad \
        --backend Manifold \
        --hardwarnings \
        --export-format binstl \
        -D "Part=\"$part\"" \
        -D 'Print_Ready=true' \
        -o "$ROOT/build/$part.stl" \
        "$ROOT/rebar_connectors.scad"
done

for part in fit_test print_set; do
    run_scad \
        --backend Manifold \
        --hardwarnings \
        --export-format binstl \
        -D "Part=\"$part\"" \
        -o "$ROOT/build/$part.stl" \
        "$ROOT/rebar_connectors.scad"
done

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection p \
    --camera 1200,-1500,1100,0,0,350 \
    -D 'Part="assembly_preview"' \
    -o "$ROOT/build/assembly_preview.png" \
    "$ROOT/rebar_connectors.scad"

run_scad \
    --backend Manifold \
    --hardwarnings \
    --render \
    --imgsize 1600,1200 \
    --autocenter \
    --viewall \
    --projection o \
    --camera 1600,0,350,0,0,350 \
    -D 'Part="assembly_preview"' \
    -o "$ROOT/build/assembly_preview_side.png" \
    "$ROOT/rebar_connectors.scad"
