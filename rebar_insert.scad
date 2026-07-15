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
    assert(Calibration_Length_mm > 0
        && Calibration_Length_mm < Socket_Depth_mm,
        "Calibration_Length_mm must be positive and shorter than the socket");
    assert(Flange_D_mm > Socket_D_mm,
        "Flange_D_mm must retain the cage outside the socket");
    assert(Flange_Thickness_mm > 0,
        "Flange_Thickness_mm must be positive");
    assert(_slotWidth("narrow") > Rib_Width_mm,
        "Every slot must be wider than the measured rib");
    assert(_fitIndex(Fit) >= 0);
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
            Flange_Thickness_mm - fudge
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
