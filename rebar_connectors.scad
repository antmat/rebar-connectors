include <BOSL2/std.scad>

$fa = $preview ? 12 : 1;
$fs = $preview ? 2 : 0.4;

/* [Output] */

// Выводимая деталь или режим
Part = "lower_3way"; // [lower_3way, upper_4way, apex_8way, print_set, assembly_preview, fit_test]

// Диагностические размеры для автоматической проверки
Diagnostics = false;

// Показывать половинный разрез детали для контроля каналов
Section_View = false;

/* [Geometry] */

// Номинальный диаметр канала
Hole_D_mm = 12.2; // [5:0.1:30]

// Глубина посадки от внешней плоскости до упора
Socket_Depth_mm = 30; // [30]

// Радиальная толщина стенки стакана
Socket_Wall_mm = 4; // [2:0.2:10]

// Длина входной фаски 45 градусов
Entry_Chamfer_mm = 1; // [0.2:0.1:3]

// Минимальная перемычка между соседними каналами
Min_Web_mm = 3; // [1:0.2:8]

// Угол лучей крыши к горизонтали
Roof_Angle_deg = 30; // [10:1:60]

/* [Preview] */

// Сторона условного восьмиугольника
Preview_Side_mm = 300; // [100:10:1000]

// Высота условных вертикальных стоек
Preview_Height_mm = 500; // [100:10:2000]

/* [Hidden] */

Print_Ready = false;
fudge = 0.05;
geometryMargin = 0.5;
outerDiameter = Hole_D_mm + 2 * Socket_Wall_mm;
blendRadius = min(2, Socket_Wall_mm / 2);

function _dot(a, b) =
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
function _length(v) = sqrt(_dot(v, v));
function _unit(v) = v / _length(v);
function _angle(a, b) =
    acos(max(-1, min(1, _dot(_unit(a), _unit(b)))));
function _pairAngles(directions) = [
    for (i = [0 : len(directions) - 2])
        for (j = [i + 1 : len(directions) - 1])
            _angle(directions[i], directions[j])
];
function _minAngle(directions) = min(_pairAngles(directions));
function _stopOffset(directions) =
    (Hole_D_mm + Min_Web_mm)
        / (2 * sin(_minAngle(directions) / 2))
    + geometryMargin;
function _actualWeb(directions) =
    2 * _stopOffset(directions)
        * sin(_minAngle(directions) / 2)
    - Hole_D_mm;
function _coreRadius(directions) =
    sqrt(
        pow(_stopOffset(directions), 2)
        + pow(Hole_D_mm / 2, 2)
    )
    + Socket_Wall_mm;

function _cornerDirections() = [
    [cos(67.5), sin(67.5), 0],
    [cos(67.5), -sin(67.5), 0]
];
function _lowerDirections() = concat(
    _cornerDirections(),
    [[0, 0, 1]]
);
function _upperDirections() = concat(
    _cornerDirections(),
    [
        [0, 0, -1],
        [cos(Roof_Angle_deg), 0, sin(Roof_Angle_deg)]
    ]
);
function _apexDirections() = [
    for (azimuth = [0 : 45 : 315])
        [
            cos(Roof_Angle_deg) * cos(azimuth),
            cos(Roof_Angle_deg) * sin(azimuth),
            -sin(Roof_Angle_deg)
        ]
];
function _ringRadius() =
    Preview_Side_mm / (2 * sin(180 / 8));
function _ringPoint(index, height) = [
    _ringRadius() * cos(index * 45),
    _ringRadius() * sin(index * 45),
    height
];
function _roofHeight() =
    _ringRadius() * tan(Roof_Angle_deg);
function _apexPrintMinimumZ(directions) =
    let(
        reference = directions[0],
        stopOffset = _stopOffset(directions),
        coreRadius = _coreRadius(directions),
        portLength = stopOffset + Socket_Depth_mm,
        sleeveRadius = outerDiameter / 2,
        firstBlendOffset = max(0, coreRadius - 2 * blendRadius),
        secondBlendOffset = coreRadius + blendRadius,
        // После поворота reference к DOWN новая Z-компонента равна -dot.
        rotatedZ = [
            for (direction = directions)
                -_dot(direction, reference)
        ],
        cylinderMinimums = [
            for (z = rotatedZ)
                min(0, portLength * z)
                    - sleeveRadius * sqrt(max(0, 1 - z * z))
        ],
        firstBlendMinimums = [
            for (z = rotatedZ)
                firstBlendOffset * z
                    - sleeveRadius
                    - blendRadius
        ],
        secondBlendMinimums = [
            for (z = rotatedZ)
                secondBlendOffset * z - sleeveRadius
        ]
    )
    min(concat(
        [-coreRadius],
        cylinderMinimums,
        firstBlendMinimums,
        secondBlendMinimums
    ));
function _apexPrintLift(directions) =
    -_apexPrintMinimumZ(directions);

module _validateParameters() {
    assert(Hole_D_mm > 0, "Hole_D_mm must be positive");
    assert(Socket_Depth_mm == 30,
        "Socket_Depth_mm is fixed at 30 mm for the validated print layout");
    assert(Socket_Wall_mm > 0, "Socket_Wall_mm must be positive");
    assert(Entry_Chamfer_mm > 0, "Entry_Chamfer_mm must be positive");
    assert(Min_Web_mm > 0, "Min_Web_mm must be positive");
    assert(Entry_Chamfer_mm < Socket_Wall_mm,
        "Entry chamfer must fit inside the sleeve wall");
    assert(Entry_Chamfer_mm < Socket_Depth_mm,
        "Entry chamfer must fit inside the socket depth");
    assert(Roof_Angle_deg > 0 && Roof_Angle_deg < 90,
        "Roof_Angle_deg must be between 0 and 90");
    children();
}

module _outerPort(direction, stopOffset, coreRadius) {
    cyl(
        l=stopOffset + Socket_Depth_mm,
        d=outerDiameter,
        anchor=BOT,
        orient=direction
    );
    hull() {
        move(direction * max(0, coreRadius - 2 * blendRadius))
            spheroid(r=outerDiameter / 2 + blendRadius);
        move(direction * (coreRadius + blendRadius))
            spheroid(r=outerDiameter / 2);
    }
}

module _socketBore(direction, stopOffset) {
    move(direction * stopOffset)
        cyl(
            l=Socket_Depth_mm - Entry_Chamfer_mm + fudge,
            d=Hole_D_mm,
            anchor=BOT,
            orient=direction
        );
    move(
        direction
            * (
                stopOffset
                + Socket_Depth_mm
                - Entry_Chamfer_mm
                - fudge
            )
    )
        cyl(
            l=Entry_Chamfer_mm + 2 * fudge,
            d1=Hole_D_mm,
            d2=Hole_D_mm + 2 * Entry_Chamfer_mm,
            anchor=BOT,
            orient=direction
        );
}

module _node(directions) {
    stopOffset = _stopOffset(directions);
    coreRadius = _coreRadius(directions);
    actualWeb = _actualWeb(directions);
    assert(actualWeb >= Min_Web_mm,
        "Calculated channels violate Min_Web_mm");
    difference() {
        union() {
            spheroid(r=coreRadius);
            for (direction = directions)
                _outerPort(direction, stopOffset, coreRadius);
        }
        for (direction = directions)
            _socketBore(direction, stopOffset);
    }
}

module lower3way() {
    _node(_lowerDirections());
}

module upper4way() {
    _node(_upperDirections());
}

module apex8way() {
    _node(_apexDirections());
}

module _previewRod(point1, point2) {
    direction = point2 - point1;
    color("#3a9d55")
        move(point1)
            cyl(
                l=_length(direction),
                d=Hole_D_mm * 0.92,
                anchor=BOT,
                orient=direction
            );
}

module _previewRods() {
    for (index = [0 : 7]) {
        next = (index + 1) % 8;
        bottom = _ringPoint(index, 0);
        bottomNext = _ringPoint(next, 0);
        top = _ringPoint(index, Preview_Height_mm);
        topNext = _ringPoint(next, Preview_Height_mm);
        apex = [0, 0, Preview_Height_mm + _roofHeight()];
        _previewRod(bottom, bottomNext);
        _previewRod(top, topNext);
        _previewRod(bottom, top);
        _previewRod(top, apex);
    }
}

module assemblyPreview() {
    _previewRods();
    for (index = [0 : 7]) {
        azimuth = index * 45;
        bottom = _ringPoint(index, 0);
        top = _ringPoint(index, Preview_Height_mm);
        move(bottom)
            zrot(azimuth + 180)
                color("#36b5a4")
                    lower3way();
        move(top)
            zrot(azimuth + 180)
                color("#36b5a4")
                    upper4way();
    }
    move([0, 0, Preview_Height_mm + _roofHeight()])
        color("#36b5a4")
            apex8way();
}

module printLower3way() {
    directions = _lowerDirections();
    stopOffset = _stopOffset(directions);
    up(stopOffset + Socket_Depth_mm)
        xrot(180)
            lower3way();
}

module printUpper4way() {
    directions = _upperDirections();
    stopOffset = _stopOffset(directions);
    up(stopOffset + Socket_Depth_mm)
        upper4way();
}

module printApex8way() {
    directions = _apexDirections();
    up(_apexPrintLift(directions))
        rot(from=directions[0], to=DOWN)
            apex8way();
}

module fitTest() {
    difference() {
        cyl(
            l=Socket_Depth_mm + Socket_Wall_mm,
            d=outerDiameter,
            anchor=BOT
        );
        up(Socket_Wall_mm)
            cyl(
                l=Socket_Depth_mm - Entry_Chamfer_mm + fudge,
                d=Hole_D_mm,
                anchor=BOT
            );
        up(
            Socket_Wall_mm
            + Socket_Depth_mm
            - Entry_Chamfer_mm
            - fudge
        )
            cyl(
                l=Entry_Chamfer_mm + 2 * fudge,
                d1=Hole_D_mm,
                d2=Hole_D_mm + 2 * Entry_Chamfer_mm,
                anchor=BOT
            );
    }
}

module printSet() {
    move([-55, -58, 0])
        printLower3way();
    move([55, -58, 0])
        printUpper4way();
    move([0, 52, 0])
        printApex8way();
}

module connectorMetrics(part) {
    directions =
        part == "lower_3way" ? _lowerDirections()
        : part == "upper_4way" ? _upperDirections()
        : part == "apex_8way" ? _apexDirections()
        : [];
    if (len(directions) > 1)
        echo(str(
            "ports=", len(directions),
            " hole_d=", Hole_D_mm,
            " depth=", Socket_Depth_mm,
            " outer_d=", outerDiameter,
            " min_angle=", _minAngle(directions),
            " stop_offset=", _stopOffset(directions),
            " core_r=", _coreRadius(directions),
            " actual_web=", _actualWeb(directions)
        ));
    else
        echo(str(
            "ports=", len(directions),
            " hole_d=", Hole_D_mm,
            " depth=", Socket_Depth_mm,
            " outer_d=", outerDiameter
        ));
}

module _selectedOutput() {
    if (Part == "lower_3way") {
        if (Print_Ready)
            printLower3way();
        else
            lower3way();
    } else if (Part == "upper_4way") {
        if (Print_Ready)
            printUpper4way();
        else
            upper4way();
    } else if (Part == "apex_8way") {
        if (Print_Ready)
            printApex8way();
        else
            apex8way();
    }
    else if (Part == "print_set")
        printSet();
    else if (Part == "assembly_preview")
        assemblyPreview();
    else if (Part == "fit_test")
        fitTest();
    else
        assert(false, str("Unsupported Part: ", Part));
}

module _applySection() {
    sectionSize = 2 * (
        Preview_Height_mm
        + Preview_Side_mm
        + Socket_Depth_mm
        + 100
    );
    if (Section_View && Part != "assembly_preview")
        intersection() {
            children();
            cuboid(sectionSize, anchor=LEFT);
        }
    else
        children();
}

if (
    is_undef(_Rebar_Connectors_Suppress_Output)
        ? true
        : !_Rebar_Connectors_Suppress_Output
)
    _validateParameters() {
        if (Diagnostics)
            connectorMetrics(Part);
        _applySection()
            _selectedOutput();
    }
