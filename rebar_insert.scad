$fn = $preview ? 64 : 128;

/* [Output] */

Part = "full"; // [calibration_single, calibration_set, full, driver, assembly_preview]
Fit = "medium"; // [vvloose, vloose, loose, medium, tight, vtight]
Diagnostics = false;

/* [Measured rebar] */

Core_D_mm = 9.1; // [5:0.1:20]
Core_Diametral_Clearance_mm = 0.7; // [0.1:0.1:2]
Rebar_Max_D_mm = 11.3; // [5:0.1:25]
Rib_Width_mm = 2.5; // [0.5:0.1:6]
Helix_Lead_mm = 45; // [10:1:100]
Helix_Starts = 2; // [1:1:4]
Helix_Hand = "right"; // [right, left]

/* [Insert fit] */

Wall_Thickness_mm = 1.3; // [0.4:0.1:3]
Rib_Slot_Width_mm = 3.5; // [2.5:0.1:6]
Entry_Extra_Clearance_mm = 1.0; // [0.1:0.1:3]

/* [Socket reference and dimensions] */

Socket_D_mm = 12.4; // [5:0.1:30]
Socket_Depth_mm = 30; // [5:1:50]
Full_Length_mm = 29; // [5:1:40]
Calibration_Length_mm = 12; // [5:1:20]
Flange_D_mm = 15; // [10:0.5:25]
Flange_Thickness_mm = 2.4; // [0.8:0.2:5]

/* [Cap and seating driver] */

Cap_Thickness_mm = 0.5; // [0.2:0.1:2]
Cap_D_mm = 11.8; // [10:0.1:14]
Driver_Diametral_Clearance_mm = 0.6; // [0.2:0.1:2]
Driver_Outer_D_mm = 22; // [16:0.5:35]
Driver_Length_mm = 35; // [30:1:80]

/* [Hidden] */

Render_Model = true;
Rib_Radial_Clearance_mm = 0.3;
fitWallStep = 0.1;
fudge = 0.02;
minimumGrooveOuterSkin = 0.1;
capJoinOverlap = 0.1;
markerDiameter = 1.2;
markerRadius = Flange_D_mm / 2;
previewSocketWall = 4;

function _fitIndex(fit) =
    fit == "vvloose" ? 0
    : fit == "vloose" ? 1
    : fit == "loose" ? 2
    : fit == "medium" ? 3
    : fit == "tight" ? 4
    : fit == "vtight" ? 5
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _coreBoreDiameter() =
    Core_D_mm + Core_Diametral_Clearance_mm;
function _wallThickness(fit) =
    Wall_Thickness_mm + (_fitIndex(fit) - 3) * fitWallStep;
function _cageDiameter(fit) =
    _coreBoreDiameter() + 2 * _wallThickness(fit);
function _entryDiameter() =
    _coreBoreDiameter() + Entry_Extra_Clearance_mm;
function _driverInnerDiameter() =
    _cageDiameter("vtight") + Driver_Diametral_Clearance_mm;
// OpenSCAD twist turns opposite to rotate(), so right-hand geometry needs -1.
function _openscadTwistSign() =
    Helix_Hand == "right" ? -1
    : Helix_Hand == "left" ? 1
    : assert(false, str("Unsupported Helix_Hand: ", Helix_Hand)) 0;
function _twist(height) =
    _openscadTwistSign() * 360 * height / Helix_Lead_mm;
function _slices(height) = max(32, ceil(height / 0.25));
function _grooveOuterRadius(fit) = min(
    Rebar_Max_D_mm / 2 + Rib_Radial_Clearance_mm,
    _cageDiameter(fit) / 2 - minimumGrooveOuterSkin
);
function _selectedWorkingLength() =
    Part == "calibration_single" || Part == "calibration_set"
    ? Calibration_Length_mm
    : Full_Length_mm;

module _validateParameters() {
    assert(Core_D_mm > 0, "Core_D_mm must be positive");
    assert(Core_Diametral_Clearance_mm > 0,
        "Core_Diametral_Clearance_mm must be positive");
    assert(Rebar_Max_D_mm > Core_D_mm,
        "Rebar_Max_D_mm must exceed Core_D_mm");
    assert(Rib_Width_mm > 0, "Rib_Width_mm must be positive");
    assert(Rib_Radial_Clearance_mm > 0,
        "Rib_Radial_Clearance_mm must be positive");
    assert(Rib_Slot_Width_mm > Rib_Width_mm,
        "Rib_Slot_Width_mm must exceed Rib_Width_mm");
    assert(Helix_Lead_mm > 0, "Helix_Lead_mm must be positive");
    assert(Helix_Starts >= 1, "Helix_Starts must be at least one");
    assert(Helix_Hand == "right" || Helix_Hand == "left",
        "Helix_Hand must be right or left");
    assert(Socket_D_mm > 0, "Socket_D_mm must be positive");
    assert(_wallThickness("vvloose") > 0,
        "Every fit must have positive wall thickness");
    assert(_cageDiameter("vvloose") > _coreBoreDiameter(),
        "Every cage diameter must exceed the core bore");
    assert(_grooveOuterRadius("vvloose") < _cageDiameter("vvloose") / 2,
        "Radial rib clearance must stay inside every cage diameter");
    assert(Full_Length_mm > 0 && Full_Length_mm < Socket_Depth_mm,
        "Full_Length_mm must be positive and shorter than the socket");
    assert(Calibration_Length_mm > 0
        && Calibration_Length_mm < Socket_Depth_mm,
        "Calibration_Length_mm must be positive and shorter than the socket");
    assert(Full_Length_mm + Cap_Thickness_mm <= Socket_Depth_mm,
        "Capped full body must fit Socket_Depth_mm");
    assert(Calibration_Length_mm + Cap_Thickness_mm <= Socket_Depth_mm,
        "Capped calibration body must fit Socket_Depth_mm");
    assert(Flange_D_mm > _cageDiameter("vtight"),
        "Flange_D_mm must exceed every cage diameter");
    assert(Flange_Thickness_mm > 0,
        "Flange_Thickness_mm must be positive");
    assert(Entry_Extra_Clearance_mm > 0,
        "Entry_Extra_Clearance_mm must be positive");
    assert(_entryDiameter() >= _coreBoreDiameter(),
        "Entry diameter must not be smaller than the core bore");
    assert(_entryDiameter() < Flange_D_mm,
        "Entry diameter must stay inside Flange_D_mm");
    assert(Cap_Thickness_mm > 0,
        "Cap_Thickness_mm must be positive");
    assert(Cap_D_mm > _coreBoreDiameter(),
        "Cap_D_mm must exceed the core bore diameter");
    assert(Cap_D_mm <= _cageDiameter("vvloose") + fudge,
        "Cap_D_mm must not exceed the smallest cage diameter");
    assert(Driver_Diametral_Clearance_mm > 0,
        "Driver_Diametral_Clearance_mm must be positive");
    assert(_driverInnerDiameter() > _cageDiameter("vtight"),
        "Driver inner diameter must exceed the largest cage diameter");
    assert(Driver_Outer_D_mm > _driverInnerDiameter(),
        "Driver outer diameter must exceed its inner diameter");
    assert(Driver_Length_mm > Full_Length_mm + Cap_Thickness_mm,
        "Driver length must exceed the capped sleeve body length");
    assert(_fitIndex(Fit) >= 0);
    children();
}

module _markerBumps(count) {
    if (count > 0)
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

module _throughSlots(slotWidth, totalHeight, cageDiameter) {
    extent = Flange_D_mm + 2;
    intersection() {
        _helicalCutters(
            slotWidth=slotWidth,
            totalHeight=totalHeight,
            outerRadius=cageDiameter / 2 + fudge
        );
        translate([
            -extent,
            -extent,
            Flange_Thickness_mm - fudge
        ])
            cube([
                2 * extent,
                2 * extent,
                totalHeight - Flange_Thickness_mm + 2 * fudge
            ]);
    }
}

module _capJoinBands(fit, totalHeight, cageDiameter) {
    difference() {
        translate([0, 0, totalHeight - capJoinOverlap])
            cylinder(
                d=Cap_D_mm,
                h=capJoinOverlap + fudge
            );
        translate([0, 0, -fudge])
            cylinder(
                d=_coreBoreDiameter(),
                h=totalHeight + 2 * fudge
            );
        _helicalCutters(
            slotWidth=Rib_Slot_Width_mm,
            totalHeight=totalHeight,
            outerRadius=_grooveOuterRadius(fit)
        );
        _throughSlots(
            slotWidth=Rib_Slot_Width_mm,
            totalHeight=totalHeight,
            cageDiameter=cageDiameter
        );
    }
}

module helicalInsert(fit, workingLength, markerCount) {
    totalHeight = Flange_Thickness_mm + workingLength;
    cageDiameter = _cageDiameter(fit);
    union() {
        difference() {
            union() {
                cylinder(d=Flange_D_mm, h=Flange_Thickness_mm);
                translate([0, 0, Flange_Thickness_mm - fudge])
                    cylinder(
                        d=cageDiameter,
                        h=workingLength + fudge
                    );
                _markerBumps(markerCount);
            }
            translate([0, 0, -fudge])
                cylinder(
                    d1=_entryDiameter(),
                    d2=_coreBoreDiameter(),
                    h=Flange_Thickness_mm + 2 * fudge
                );
            translate([0, 0, Flange_Thickness_mm - fudge])
                cylinder(
                    d=_coreBoreDiameter(),
                    h=workingLength + 2 * fudge
                );
            _helicalCutters(
                slotWidth=Rib_Slot_Width_mm,
                totalHeight=totalHeight,
                outerRadius=_grooveOuterRadius(fit)
            );
            _throughSlots(
                slotWidth=Rib_Slot_Width_mm,
                totalHeight=totalHeight,
                cageDiameter=cageDiameter
            );
        }
        _capJoinBands(
            fit=fit,
            totalHeight=totalHeight,
            cageDiameter=cageDiameter
        );
        translate([0, 0, totalHeight])
            cylinder(d=Cap_D_mm, h=Cap_Thickness_mm);
    }
}

module calibrationSingle() {
    helicalInsert(
        fit=Fit,
        workingLength=Calibration_Length_mm,
        markerCount=_fitIndex(Fit)
    );
}

module calibrationSet() {
    fits = ["vvloose", "vloose", "loose", "medium", "tight", "vtight"];
    for (index = [0 : 5])
        translate([(index - 2.5) * 20, 0, 0])
            helicalInsert(
                fit=fits[index],
                workingLength=Calibration_Length_mm,
                markerCount=index
            );
}

module fullInsert() {
    helicalInsert(
        fit=Fit,
        workingLength=Full_Length_mm,
        markerCount=_fitIndex(Fit)
    );
}

module driverTool() {
    difference() {
        cylinder(d=Driver_Outer_D_mm, h=Driver_Length_mm);
        translate([0, 0, -fudge])
            cylinder(
                d=_driverInnerDiameter(),
                h=Driver_Length_mm + 2 * fudge
            );
    }
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
            _rebarModel(totalHeight + 4);
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
            " core_clearance=", Core_Diametral_Clearance_mm,
            " bore_d=", _coreBoreDiameter(),
            " rebar_max_d=", Rebar_Max_D_mm,
            " rib_width=", Rib_Width_mm,
            " wall_t=", _wallThickness(Fit),
            " cage_d=", _cageDiameter(Fit),
            " slot_width=", Rib_Slot_Width_mm,
            " entry_d=", _entryDiameter(),
            " working_length=", _selectedWorkingLength(),
            " lead=", Helix_Lead_mm,
            " starts=", Helix_Starts,
            " twist_sign=", _openscadTwistSign(),
            " marker_count=", _fitIndex(Fit),
            " flange_d=", Flange_D_mm,
            " flange_t=", Flange_Thickness_mm,
            " cap_t=", Cap_Thickness_mm,
            " cap_d=", Cap_D_mm,
            " driver_inner_d=", _driverInnerDiameter(),
            " driver_outer_d=", Driver_Outer_D_mm,
            " driver_length=", Driver_Length_mm
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
        else if (Part == "driver")
            driverTool();
        else if (Part == "assembly_preview")
            assemblyPreview();
        else
            assert(false, str("Unsupported Part: ", Part));
    }
