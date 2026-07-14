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
markerRadius = Flange_D_mm / 2;

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
        angle = 270 + (index - (count - 1) / 2) * 18;
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
