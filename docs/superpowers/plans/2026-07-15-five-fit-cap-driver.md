# Five-Fit Capped Insert and Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Добавить пять степеней посадки с маркировкой 1–5, постоянную крышку 0,5 мм, цельную посадочную трубку и практический раскрой с округлением до целых миллиметров.

**Architecture:** `rebar_insert.scad` остаётся источником геометрии втулки и нового режима `driver`; крышка добавляется после существующей рабочей длины, не меняя спираль и вход. Python-тесты проверяют диагностические размеры, реальные Manifold STL и торцевые пробы. `scripts/rebar_cut_list.py` сохраняет точные внутренние вычисления, но применяет новый отступ упора и формирует целочисленную ведомость.

**Tech Stack:** OpenSCAD Manifold, Python 3 `unittest`, Bash-экспорт, бинарные STL и PNG.

## Global Constraints

- `vloose/loose/medium/tight/vtight` дают стенки 1.1/1.2/1.3/1.4/1.5 мм и наружные диаметры 12.0/12.2/12.4/12.6/12.8 мм.
- Маркировка сохраняется выступами: от одного у `vloose` до пяти у `vtight`.
- Правая двухзаходная спираль, отверстие 9.8 мм, прорезь 3.5 мм и вход 10.8→9.8 мм не меняются.
- `Cap_Thickness_mm = 0.5`; крышка постоянная, печатается сверху мостом, втулка остаётся буртиком на столе.
- Рабочая часть полной втулки 29 мм плюс крышка 0.5 мм; арматура останавливается на 1 мм раньше прежнего упора глубиной 30 мм.
- Посадочная трубка открыта с двух сторон, давит на буртик со стороны корпуса и имеет Ø13.4/22 × 35 мм.
- Длины раскроя округляются до ближайшего целого миллиметра, половина округляется вверх; допуск реза ±1 мм.
- Пользовательские `3way.stl`, `rebar_insert.stl` и `stash@{0}` в основном checkout не изменять.

---

### Task 1: Расширить Fit и маркировку до пяти вариантов

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `rebar_insert.scad`

**Interfaces:**
- Consumes: `_fitIndex(fit)`, `_wallThickness(fit)`, `_cageDiameter(fit)`, `calibrationSet()`.
- Produces: поддержка `vloose|loose|medium|tight|vtight`, пять деталей с 1–5 выступами.

- [ ] **Step 1: Написать падающие тесты пяти размеров и пяти компонентов**

Заменить таблицу на:

```python
FIT_DIMENSIONS = {
    "vloose": (1.1, 12.0),
    "loose": (1.2, 12.2),
    "medium": (1.3, 12.4),
    "tight": (1.4, 12.6),
    "vtight": (1.5, 12.8),
}
```

Переименовать тест набора и ожидать `stats.components == 5` и
`stats.dimensions[0] < 100.0`. Диагностический тест должен пройти все пять ключей
и для каждого по порядку проверить `metrics["marker_count"] == 1…5`.

- [ ] **Step 2: Подтвердить RED**

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: FAIL для `vloose`, `vtight` и числа компонентов, потому что модель знает
только три варианта.

- [ ] **Step 3: Реализовать симметричный индекс**

```scad
Fit = "medium"; // [vloose, loose, medium, tight, vtight]

function _fitIndex(fit) =
    fit == "vloose" ? 0
    : fit == "loose" ? 1
    : fit == "medium" ? 2
    : fit == "tight" ? 3
    : fit == "vtight" ? 4
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _wallThickness(fit) =
    Wall_Thickness_mm + (_fitIndex(fit) - 2) * fitWallStep;
```

Валидация использует `_wallThickness("vloose")`, `_cageDiameter("vloose")` и
`_cageDiameter("vtight")`. `calibrationSet()` перебирает пять имён, размещает их
как `(index - 2) * 20` и передаёт `markerCount=index + 1`. Диагностика выводит
`marker_count=_fitIndex(Fit) + 1`.

- [ ] **Step 4: Получить GREEN и закоммитить**

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
git add rebar_insert.scad tests/test_helical_rebar_insert.py
git commit -m "Expand insert calibration to five fits"
```

Expected: focused suite PASS; набор содержит пять компонентов.

---

### Task 2: Добавить постоянную крышку и посадочную трубку

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `tests/helical_insert_probes.scad`
- Modify: `rebar_insert.scad`

**Interfaces:**
- Consumes: `helicalInsert(fit, workingLength, markerCount)`, `fullInsert()` и `render_model()`.
- Produces: `Cap_Thickness_mm`, `_driverInnerDiameter()`, `driverTool()`, режим `Part="driver"`, пробы `cap_reference`, `cap_solid`, `below_cap_void`.

- [ ] **Step 1: Написать падающие тесты крышки**

В диагностике ожидать `cap_t=0.5`. Изменить ожидаемую высоту полной детали на
31.9 мм, калибровочной — на 14.9 мм. В `tests/helical_insert_probes.scad`
добавить центральную сферу и пару сфер на радиусе винтовых прорезей:

```scad
capProbeZ = Flange_Thickness_mm + Full_Length_mm + Cap_Thickness_mm / 2;
belowCapProbeZ = Flange_Thickness_mm + Full_Length_mm - 0.2;

module capProbeSet() {
    axialProbe(capProbeZ);
    probePairAt(capProbeZ, 0);
}

module axialProbe(z) {
    translate([0, 0, z])
        sphere(d=probeDiameter, $fn=48);
}

module probePairAt(z, angleOffset) {
    angle = 360 * z / Helix_Lead_mm;
    for (start = [0 : 1])
        rotate([0, 0, angle + start * 180 + angleOffset])
            translate([probeRadius, 0, z])
                sphere(d=probeDiameter, $fn=48);
}
```

`probePairAt(z, angleOffset)` вычисляет фазу как `360 * z / Helix_Lead_mm` и
ставит две сферы с шагом 180°. `cap_reference` выводит `capProbeSet()`;
`cap_solid` пересекает его с `fullInsert()`. `below_cap_reference` выводит
центральную сферу ниже крышки; `below_cap_void` вычитает `fullInsert()` из неё.
Python сравнивает объёмы с допуском 5%, требует 3 компонента у крышки, 1 ниже
крышки и 0 non-manifold рёбер.

- [ ] **Step 2: Написать падающий тест трубки**

Рендер `Part="driver"` должен завершаться успешно и давать один компонент,
0 non-manifold рёбер, габариты `(22.0, 22.0, 35.0)`. Диагностика режима должна
содержать:

```python
self.assertAlmostEqual(metrics["driver_inner_d"], 13.4)
self.assertAlmostEqual(metrics["driver_outer_d"], 22.0)
self.assertAlmostEqual(metrics["driver_length"], 35.0)
```

- [ ] **Step 3: Подтвердить RED**

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: FAIL по отсутствующим параметрам, режиму `driver`, старой высоте и
открытому свободному торцу.

- [ ] **Step 4: Реализовать крышку без изменения спирали**

Добавить параметры:

```scad
Cap_Thickness_mm = 0.5; // [0.2:0.1:2]
Driver_Diametral_Clearance_mm = 0.6; // [0.2:0.1:2]
Driver_Outer_D_mm = 22; // [16:0.5:35]
Driver_Length_mm = 35; // [30:1:80]
```

Сохранить существующие вычитания без изменения и обернуть их вместе с крышкой в
наружный `union()`. Полный модуль принимает вид:

```scad
module helicalInsert(fit, workingLength, markerCount) {
    totalHeight = Flange_Thickness_mm + workingLength;
    cageDiameter = _cageDiameter(fit);
    union() {
        difference() {
            union() {
                cylinder(d=Flange_D_mm, h=Flange_Thickness_mm);
                translate([0, 0, Flange_Thickness_mm - fudge])
                    cylinder(d=cageDiameter, h=workingLength + fudge);
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
                outerRadius=_grooveOuterRadius()
            );
            _throughSlots(
                slotWidth=Rib_Slot_Width_mm,
                totalHeight=totalHeight,
                cageDiameter=cageDiameter
            );
        }
        translate([0, 0, totalHeight])
            cylinder(d=cageDiameter, h=Cap_Thickness_mm);
    }
}
```

Крышка не попадает под центральное или винтовое вычитание. Диагностика выводит
`cap_t`.

- [ ] **Step 5: Реализовать цельную трубку и валидацию**

```scad
function _driverInnerDiameter() =
    _cageDiameter("vtight") + Driver_Diametral_Clearance_mm;

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
```

Проверить `Cap_Thickness_mm > 0`, `Driver_Diametral_Clearance_mm > 0`,
`_driverInnerDiameter() > _cageDiameter("vtight")`,
`Driver_Outer_D_mm > _driverInnerDiameter()` и
`Driver_Length_mm > Full_Length_mm + Cap_Thickness_mm`. Добавить `driver` в
список `Part`, диагностику и top-level dispatch.

- [ ] **Step 6: Получить GREEN и закоммитить**

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
python3 -m unittest discover -s tests -v
git add rebar_insert.scad tests/helical_insert_probes.scad tests/test_helical_rebar_insert.py
git commit -m "Add permanent insert cap and seating driver"
```

Expected: полный suite PASS; крышка замкнута, трубка Ø22 × 35 мм, правая спираль
остаётся корректной.

---

### Task 3: Обновить поправку и точность ведомости раскроя

**Files:**
- Create: `tests/test_rebar_cut_list.py`
- Modify: `scripts/rebar_cut_list.py`

**Interfaces:**
- Consumes: прежние `LOWER_STOP_MM`, `UPPER_STOP_MM`, `APEX_STOP_MM`, `cut_groups()`.
- Produces: `INSERT_STOP_GAP_MM = 1.0`, `round_cut_mm(value) -> int`, целочисленный CLI-вывод.

- [ ] **Step 1: Написать падающие unit- и CLI-тесты**

Загрузить исполняемый скрипт через `importlib.util.spec_from_file_location`.
Сначала проверить наличие новых функций через `assertTrue(hasattr(...))`, затем:

```python
self.assertEqual(module.round_cut_mm(10.49), 10)
self.assertEqual(module.round_cut_mm(10.5), 11)
self.assertEqual(module.round_cut_mm(10.51), 11)
self.assertEqual(
    [length for _, _, length in module.rounded_cut_groups(3000, 2000)],
    [1124, 1119, 1973, 1693],
)
```

Запуск `scripts/rebar_cut_list.py --diameter 3000 --height 2000` должен содержать
`8 шт. × 1124 мм`, `8 шт. × 1119 мм`, `8 шт. × 1973 мм`, `8 шт. × 1693 мм`,
`допуск реза: ±1 мм` и `47.272 м`.

- [ ] **Step 2: Подтвердить RED**

```bash
python3 -m unittest discover -s tests -p 'test_rebar_cut_list.py' -v
```

Expected: FAIL по `hasattr` и старому CLI-выводу, потому что функций округления и
новой поправки ещё нет.

- [ ] **Step 3: Реализовать поправку и округление половин вверх**

```python
INSERT_STOP_GAP_MM = 1.0

def round_cut_mm(value: float) -> int:
    return math.floor(value + 0.5)

def rounded_cut_groups(
    diameter_mm: float,
    height_mm: float,
) -> list[tuple[str, int, int]]:
    return [
        (name, count, round_cut_mm(length))
        for name, count, length in cut_groups(diameter_mm, height_mm)
    ]
```

В `cut_groups()` использовать эффективные смещения
`LOWER_STOP_MM + INSERT_STOP_GAP_MM`, `UPPER_STOP_MM + INSERT_STOP_GAP_MM`,
`APEX_STOP_MM + INSERT_STOP_GAP_MM`. В `main()` печатать `rounded_cut_groups`,
целые миллиметры, строку допуска и считать метраж по округлённым длинам.

- [ ] **Step 4: Получить GREEN и закоммитить**

```bash
python3 -m unittest discover -s tests -p 'test_rebar_cut_list.py' -v
python3 -m unittest discover -s tests -v
git add scripts/rebar_cut_list.py tests/test_rebar_cut_list.py
git commit -m "Round cut list for capped insert stops"
```

Expected: тесты раскроя и полный suite PASS.

---

### Task 4: Экспортировать новые детали и обновить инструкцию

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `scripts/render_rebar_insert.sh`
- Modify: `.gitignore`
- Modify: `REBAR_CONNECTORS.md`
- Create: `build/helical_insert_calibration_vloose.stl`
- Create: `build/helical_insert_calibration_vtight.stl`
- Create: `build/helical_insert_driver.stl`
- Create: `build/helical_insert_driver.png`
- Regenerate: существующие пять артефактов втулки и три PNG.

**Interfaces:**
- Consumes: пять значений `Fit`, `Part="driver"`, крышку и новый CLI-вывод.
- Produces: полный набор печатных STL/PNG и актуальную русскую инструкцию.

- [ ] **Step 1: Написать падающий контракт экспортера**

Тест должен требовать строку `for fit in vloose loose medium tight vtight`,
экспорт `Part="driver"`, `helical_insert_driver.stl` и
`helical_insert_driver.png`.

- [ ] **Step 2: Подтвердить RED**

```bash
PYTHONPATH=tests python3 -m unittest test_helical_rebar_insert.HelicalInsertTest.test_export_script_uses_wall_fit_names -v
```

Expected: FAIL, старый цикл содержит только три варианта и не экспортирует трубку.

- [ ] **Step 3: Обновить exporter, ignore и документацию**

В Bash использовать:

```bash
for fit in vloose loose medium tight vtight; do
```

Добавить Manifold STL и PNG экспорт `Part="driver"`. В `.gitignore` разрешить
два новых калибра и два файла трубки. В `REBAR_CONNECTORS.md` зафиксировать пять
толщин/диаметров и меток, крышку 0.5 мм сверху, мост без поддержек, трубку
Ø13.4/22 × 35 мм, разборку, поправку упора 1 мм и допуск реза ±1 мм.

- [ ] **Step 4: Перегенерировать и визуально проверить**

```bash
scripts/render_rebar_insert.sh
python3 -m unittest discover -s tests -v
git diff --check
```

Expected: exporter завершён без hardwarnings; все STL Manifold; тесты PASS.
Открыть `helical_insert_calibration_set.png`, `helical_insert_full_medium.png`,
`helical_insert_assembly_preview.png`, `helical_insert_driver.png`; проверить пять
меток, сплошную крышку, плоский буртик и открытую трубку.

- [ ] **Step 5: Закоммитить артефакты**

```bash
git add .gitignore REBAR_CONNECTORS.md scripts/render_rebar_insert.sh tests/test_helical_rebar_insert.py build/
git commit -m "Publish capped five-fit insert set"
```

---

### Task 5: Финальная проверка и интеграция

**Files:**
- Verify only; исправления поведения требуют нового RED-теста.

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: проверенную ветку, готовую к review, fast-forward в `main` и push.

- [ ] **Step 1: Выполнить свежую проверку**

```bash
python3 -m unittest discover -s tests -v
scripts/render_rebar_insert.sh
git diff --check
git status --short
```

Expected: тесты PASS, экспорт PASS, diff-check пуст, worktree чист.

- [ ] **Step 2: Провести независимый code review**

Использовать `superpowers:requesting-code-review` для диапазона `41b642e..HEAD`.
Исправить Critical/Important замечания через RED→GREEN и повторить Step 1.

- [ ] **Step 3: Интегрировать обычным способом**

После подтверждения пользователя использовать `superpowers:finishing-a-development-branch`.
Для обычного сценария проекта выполнить fast-forward `main`, повторить полный suite
уже из основного checkout и `git push origin main`. Не применять и не удалять
`stash@{0}`; не добавлять локальные `3way.stl` и `rebar_insert.stl`.
