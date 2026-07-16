# `vvloose` Insert Fit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить шестую посадку `vvloose` со стенкой 1,0 мм, наружным диаметром 11,8 мм и без маркировочных выступов.

**Architecture:** Существующая симметричная индексная шкала расширяется до значений 0…5; базовый `medium` остаётся 1,3 мм, число выступов равно индексу. OpenSCAD остаётся единственным источником геометрии, а тесты проверяют диагностические значения, реальный Manifold STL, калибровочный набор, экспорт и готовые артефакты.

**Tech Stack:** OpenSCAD Manifold, Python 3 `unittest`, Bash-экспорт, бинарные STL и PNG.

## Global Constraints

- Порядок Fit: `vvloose`, `vloose`, `loose`, `medium`, `tight`, `vtight`.
- Толщины: 1.0/1.1/1.2/1.3/1.4/1.5 мм; наружные диаметры: 11.8/12.0/12.2/12.4/12.6/12.8 мм.
- Количество выступов: 0/1/2/3/4/5.
- Правая спираль, отверстие 9,8 мм, прорезь 3,5 мм, крышка Ø11,8 × 0,5 мм и трубка не меняются.
- Калибровочный набор содержит шесть отдельных деталей с центрами `-50, -30, -10, 10, 30, 50 мм`.
- Локальные пользовательские значения `Fit="tight"`, `Driver_Length_mm=29` и неотслеживаемые STL в основном checkout не включать в feature-коммиты и сохранить при интеграции.

---

### Task 1: Расширить модель и калибровочный набор до шести Fit

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `rebar_insert.scad`

**Interfaces:**
- Consumes: `_fitIndex(fit)`, `_wallThickness(fit)`, `_markerBumps(count)`, `calibrationSingle()`, `calibrationSet()`, `fullInsert()`.
- Produces: `Fit="vvloose"`, индексы 0…5, маркировку 0…5 и шестикомпонентный калибровочный набор.

- [ ] **Step 1: Написать падающие тесты размеров, маркировки и набора**

В `tests/test_helical_rebar_insert.py` заменить таблицу на:

```python
FIT_DIMENSIONS = {
    "vvloose": (1.0, 11.8),
    "vloose": (1.1, 12.0),
    "loose": (1.2, 12.2),
    "medium": (1.3, 12.4),
    "tight": (1.4, 12.6),
    "vtight": (1.5, 12.8),
}
```

В `test_calibration_metrics_match_measured_rebar` перечислять метки с нуля:

```python
for marker_count, (
    fit,
    (expected_wall, expected_cage),
) in enumerate(FIT_DIMENSIONS.items()):
```

Переименовать тест набора и ожидать шесть компонентов и ширину 115 мм:

```python
def test_calibration_set_contains_six_separate_parts(self) -> None:
    with tempfile.TemporaryDirectory() as directory:
        result, output = render_model("calibration_set", directory)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stats = inspect_binary_stl(output)
    self.assertEqual(stats.nonmanifold_edges, 0)
    self.assertEqual(stats.components, 6)
    self.assertAlmostEqual(stats.bounds_min[2], 0.0, places=3)
    self.assertAlmostEqual(stats.dimensions[0], 115.0, places=3)
    self.assertAlmostEqual(stats.dimensions[2], 14.9, places=3)
```

Добавить геометрическую проверку отсутствия выступов:

```python
def test_vvloose_has_no_marker_bumps(self) -> None:
    with tempfile.TemporaryDirectory() as directory:
        result, output = render_model(
            "calibration_single",
            directory,
            fit="vvloose",
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        stats = inspect_binary_stl(output)
    self.assertEqual(stats.nonmanifold_edges, 0)
    self.assertEqual(stats.components, 1)
    self.assertAlmostEqual(stats.dimensions[0], 15.0, places=3)
    self.assertAlmostEqual(stats.dimensions[1], 15.0, places=3)
```

- [ ] **Step 2: Запустить RED-проверку**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: FAIL для неизвестного `vvloose`, неверных числа компонентов/ширины и отсутствующей диагностической метки 0.

- [ ] **Step 3: Реализовать индекс, нулевую маркировку и набор**

В `rebar_insert.scad` обновить Customizer и функции:

```scad
Fit = "medium"; // [vvloose, vloose, loose, medium, tight, vtight]

function _fitIndex(fit) =
    fit == "vvloose" ? 0
    : fit == "vloose" ? 1
    : fit == "loose" ? 2
    : fit == "medium" ? 3
    : fit == "tight" ? 4
    : fit == "vtight" ? 5
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _wallThickness(fit) =
    Wall_Thickness_mm + (_fitIndex(fit) - 3) * fitWallStep;
```

Минимальные проверки и ограничение крышки должны использовать `vvloose`:

```scad
assert(_wallThickness("vvloose") > 0,
    "Every fit must have positive wall thickness");
assert(_cageDiameter("vvloose") > _coreBoreDiameter(),
    "Every cage diameter must exceed the core bore");
assert(_grooveOuterRadius("vvloose") < _cageDiameter("vvloose") / 2,
    "Radial rib clearance must stay inside every cage diameter");
assert(Cap_D_mm <= _cageDiameter("vvloose") + fudge,
    "Cap_D_mm must not exceed the smallest cage diameter");
```

Явно пропускать нулевую маркировку:

```scad
module _markerBumps(count) {
    if (count > 0)
        for (index = [0 : count - 1]) {
            angle = 270 + (index - (count - 1) / 2) * 18;
            rotate([0, 0, angle])
                translate([markerRadius, 0, 0])
                    cylinder(d=markerDiameter, h=Flange_Thickness_mm);
        }
}
```

Использовать индекс как количество выступов:

```scad
markerCount=_fitIndex(Fit)
```

для `calibrationSingle()` и `fullInsert()`, а в диагностике:

```scad
" marker_count=", _fitIndex(Fit),
```

Обновить общий набор:

```scad
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
```

- [ ] **Step 4: Получить GREEN**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: все focused-тесты PASS; `vvloose` имеет стенку 1,0 мм, Ø11,8 мм, 0 отметок, набор — шесть компонентов шириной 115 мм.

- [ ] **Step 5: Закоммитить модель и тесты**

```bash
git add rebar_insert.scad tests/test_helical_rebar_insert.py
git commit -m "Add unmarked vvloose insert fit"
```

---

### Task 2: Обновить экспорт, документацию и готовые файлы

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `scripts/render_rebar_insert.sh`
- Modify: `.gitignore`
- Modify: `REBAR_CONNECTORS.md`
- Create: `build/helical_insert_calibration_vvloose.stl`
- Regenerate: `build/helical_insert_calibration_set.stl`
- Regenerate: `build/helical_insert_calibration_set.png`

**Interfaces:**
- Consumes: `Fit="vvloose"`, шестикомпонентный `calibrationSet()`.
- Produces: отдельный STL `vvloose`, обновлённые набор и инструкцию.

- [ ] **Step 1: Написать падающий контракт экспортера**

В `test_export_script_uses_wall_fit_names` ожидать:

```python
self.assertIn(
    "for fit in vvloose vloose loose medium tight vtight",
    script,
)
self.assertIn("helical_insert_calibration_$fit.stl", script)
```

- [ ] **Step 2: Запустить RED-проверку экспортера**

Run:

```bash
PYTHONPATH=tests python3 -m unittest \
    test_helical_rebar_insert.HelicalInsertTest.test_export_script_uses_wall_fit_names \
    -v
```

Expected: FAIL, потому что цикл экспортера начинается с `vloose`.

- [ ] **Step 3: Добавить `vvloose` в экспортер и ignore**

В `scripts/render_rebar_insert.sh` заменить цикл:

```bash
for fit in vvloose vloose loose medium tight vtight; do
```

В `.gitignore` добавить рядом с остальными калибрами:

```gitignore
!build/helical_insert_calibration_vvloose.stl
```

- [ ] **Step 4: Обновить инструкцию**

В таблицу `REBAR_CONNECTORS.md` добавить первой строкой:

```markdown
| Без выступов | `vvloose` | 1,0 мм | 11,8 мм |
```

Заменить упоминания пяти вариантов и пяти образцов на шесть. Указать, что шкала
начинается с `vvloose`, а экспортер создаёт отдельные калибры для всех шести Fit.

- [ ] **Step 5: Получить GREEN контракта экспортера**

Run:

```bash
PYTHONPATH=tests python3 -m unittest \
    test_helical_rebar_insert.HelicalInsertTest.test_export_script_uses_wall_fit_names \
    -v
```

Expected: PASS.

- [ ] **Step 6: Перегенерировать STL и PNG**

Run:

```bash
scripts/render_rebar_insert.sh
```

Expected: OpenSCAD завершает все экспорты с `Status: NoError`; появляется
`build/helical_insert_calibration_vvloose.stl`, общий набор содержит шесть
деталей.

- [ ] **Step 7: Проверить артефакты и весь проект**

Run:

```bash
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=tests python3 -c '
from pathlib import Path
from scad_test_utils import inspect_binary_stl
for path in sorted(Path("build").glob("helical_insert_*.stl")):
    stats = inspect_binary_stl(path)
    print(path.name, stats.components, stats.nonmanifold_edges, stats.dimensions)
'
python3 -m unittest discover -s tests -v
bash -n scripts/render_rebar_insert.sh
git diff --check
```

Expected: все STL имеют `nonmanifold_edges=0`; отдельный `vvloose` состоит из
одного компонента, общий набор — из шести; все тесты PASS, Bash и diff clean.
Визуально открыть `build/helical_insert_calibration_set.png` и проверить ряд из
шести деталей с маркировкой 0…5.

- [ ] **Step 8: Закоммитить экспорт и документацию**

```bash
git add .gitignore REBAR_CONNECTORS.md scripts/render_rebar_insert.sh \
    tests/test_helical_rebar_insert.py \
    build/helical_insert_calibration_vvloose.stl \
    build/helical_insert_calibration_vloose.stl \
    build/helical_insert_calibration_loose.stl \
    build/helical_insert_calibration_medium.stl \
    build/helical_insert_calibration_tight.stl \
    build/helical_insert_calibration_vtight.stl \
    build/helical_insert_calibration_set.stl \
    build/helical_insert_calibration_set.png
git commit -m "Export six insert calibration fits"
```
