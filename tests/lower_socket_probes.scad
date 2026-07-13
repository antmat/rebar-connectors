_Rebar_Connectors_Suppress_Output = true;

include <rebar_connectors.scad>

Probe = "go"; // [go, no_go, stop]

Probe_Directions = [
    [cos(67.5), sin(67.5), 0],
    [cos(67.5), -sin(67.5), 0],
    [0, 0, 1]
];
Probe_Stop_Offset_mm =
    (12.2 + 3) / (2 * sin(90 / 2)) + 0.5;
Go_Gauge_D_mm = 12.0;
No_Go_Gauge_D_mm = 12.6;
Go_Stop_Clearance_mm = 0.2;
Go_Outside_Extension_mm = 2;
No_Go_End_Margin_mm = 1;
Stop_Probe_Gap_mm = 0.2;
Stop_Probe_Length_mm = 0.5;

module _testProbeCylinder(direction, start, length, diameter) {
    move(direction * start)
        cyl(
            l=length,
            d=diameter,
            anchor=BOT,
            orient=direction
        );
}

module _testAllProbeCylinders(start, length, diameter) {
    for (direction = Probe_Directions)
        _testProbeCylinder(direction, start, length, diameter);
}

module _testGoGauges() {
    start = Probe_Stop_Offset_mm + Go_Stop_Clearance_mm;
    length = 30 - Go_Stop_Clearance_mm + Go_Outside_Extension_mm;
    difference() {
        _testAllProbeCylinders(start, length, Go_Gauge_D_mm);
        lower3way();
    }
}

module _testNoGoWallIntersections() {
    start = Probe_Stop_Offset_mm + No_Go_End_Margin_mm;
    length = 30 - 1 - 2 * No_Go_End_Margin_mm;
    intersection() {
        lower3way();
        _testAllProbeCylinders(start, length, No_Go_Gauge_D_mm);
    }
}

module _testBlindStopIntersections() {
    start =
        Probe_Stop_Offset_mm
        - Stop_Probe_Gap_mm
        - Stop_Probe_Length_mm;
    intersection() {
        lower3way();
        _testAllProbeCylinders(
            start,
            Stop_Probe_Length_mm,
            Go_Gauge_D_mm
        );
    }
}

if (Probe == "go")
    _testGoGauges();
else if (Probe == "no_go")
    _testNoGoWallIntersections();
else if (Probe == "stop")
    _testBlindStopIntersections();
else
    assert(false, str("Unsupported Probe: ", Probe));
