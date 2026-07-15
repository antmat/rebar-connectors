include <../rebar_insert.scad>

Probe = "reference"; // [reference, slot_void, band_solid, entry_reference_low, entry_void, entry_reference_high, entry_wall, cap_reference, cap_solid, below_cap_reference, below_cap_void, below_cap_slots_reference, below_cap_slots_void, driver_bore_reference, driver_bore_void]

probeDiameter = 0.3;
probeZ = Helix_Lead_mm / 8;
probeRadius = (_coreBoreDiameter() + _cageDiameter("medium")) / 4;
rightHandAngle = 360 * probeZ / Helix_Lead_mm;
entryProbeRadius = 5.2;
entryLowZ = 0.1;
entryHighZ = Flange_Thickness_mm - 0.1;
capProbeZ = Flange_Thickness_mm + Full_Length_mm + Cap_Thickness_mm / 2;
belowCapProbeZ = Flange_Thickness_mm + Full_Length_mm - 0.2;
belowCapSlotsProbeZ =
    Flange_Thickness_mm + Full_Length_mm - capJoinOverlap / 2;
driverNearProbeZ = 0.2;
driverFarProbeZ = Driver_Length_mm - 0.2;

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

module axialProbe(z) {
    translate([0, 0, z])
        sphere(d=probeDiameter, $fn=48);
}

module probePairAt(z, angleOffset, diameter=probeDiameter) {
    angle = 360 * z / Helix_Lead_mm;
    for (start = [0 : 1])
        rotate([0, 0, angle + start * 180 + angleOffset])
            translate([probeRadius, 0, z])
                sphere(d=diameter, $fn=48);
}

module capProbeSet() {
    axialProbe(capProbeZ);
    probePairAt(capProbeZ, 0);
}

module driverBoreProbeSet() {
    axialProbe(driverNearProbeZ);
    axialProbe(driverFarProbeZ);
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
else if (Probe == "cap_reference")
    capProbeSet();
else if (Probe == "cap_solid")
    intersection() {
        capProbeSet();
        fullInsert();
    }
else if (Probe == "below_cap_reference")
    axialProbe(belowCapProbeZ);
else if (Probe == "below_cap_void")
    difference() {
        axialProbe(belowCapProbeZ);
        fullInsert();
    }
else if (Probe == "below_cap_slots_reference")
    probePairAt(
        belowCapSlotsProbeZ,
        0,
        diameter=capJoinOverlap / 2
    );
else if (Probe == "below_cap_slots_void")
    difference() {
        probePairAt(
            belowCapSlotsProbeZ,
            0,
            diameter=capJoinOverlap / 2
        );
        fullInsert();
    }
else if (Probe == "driver_bore_reference")
    driverBoreProbeSet();
else if (Probe == "driver_bore_void")
    difference() {
        driverBoreProbeSet();
        driverTool();
    }
else
    assert(false, str("Unsupported Probe: ", Probe));
