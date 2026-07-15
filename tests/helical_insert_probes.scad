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
