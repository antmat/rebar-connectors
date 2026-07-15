include <../rebar_insert.scad>

Probe = "reference"; // [reference, slot_void, band_solid, entry_reference_low, entry_void, entry_reference_high, entry_wall]

probeDiameter = 0.3;
probeZ = Helix_Lead_mm / 8;
probeRadius = (_coreBoreDiameter() + _cageDiameter("medium")) / 4;
rightHandAngle = 360 * probeZ / Helix_Lead_mm;
entryProbeRadius = 5.2;
entryLowZ = 0.1;
entryHighZ = Flange_Thickness_mm - 0.1;

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
        fit="medium",
        workingLength=Full_Length_mm,
        markerCount=2
    );
}

module entryProbe(z) {
    angle = 360 * z / Helix_Lead_mm + 90;
    rotate([0, 0, angle])
        translate([entryProbeRadius, 0, z])
            sphere(d=probeDiameter, $fn=48);
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
else if (Probe == "entry_reference_low")
    entryProbe(entryLowZ);
else if (Probe == "entry_void")
    difference() {
        entryProbe(entryLowZ);
        fullInsert();
    }
else if (Probe == "entry_reference_high")
    entryProbe(entryHighZ);
else if (Probe == "entry_wall")
    intersection() {
        entryProbe(entryHighZ);
        fullInsert();
    }
else
    assert(false, str("Unsupported Probe: ", Probe));
