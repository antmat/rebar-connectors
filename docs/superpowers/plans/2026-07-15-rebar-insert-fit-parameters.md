# Rebar Insert Fit Parameters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Перевести посадку винтовой PETG-втулки с вариантов ширины прорези на понятные параметры сердцевины, диаметрального зазора и толщины стенки, одновременно добавить увеличенный конический вход в буртике.

**Architecture:** `rebar_insert.scad` остаётся единственным источником геометрии: диаметр отверстия, толщина ленты, наружный диаметр и вход вычисляются функциями из параметров Customizer. Python-тесты читают диагностический вывод OpenSCAD и проверяют реальные STL, а отдельная SCAD-проба проверяет материал у конического входа и направление спирали. Скрипт экспорта и пользовательская документация используют те же имена `loose/medium/tight`.

**Tech Stack:** OpenSCAD с backend Manifold, Python `unittest`, shell-скрипт экспорта, бинарные STL и PNG.

## Global Constraints

- `Core_D_mm = 9.1`, `Core_Diametral_Clearance_mm = 0.7`, рабочее отверстие 9.8 мм.
- `Wall_Thickness_mm = 1.3`; `loose/medium/tight` дают 1.2/1.3/1.4 мм и наружные диаметры 12.2/12.4/12.6 мм.
- `Rib_Slot_Width_mm = 3.5` одинаков для всех вариантов.
- `Entry_Extra_Clearance_mm = 1.0`; вход буртика сужается 10.8→9.8 мм.
- `Socket_D_mm = 12.4` используется только как справочный размер и для preview; наружный диаметр втулки не обязан быть меньше него.
- Правое направление остаётся `twist_sign = -1`; ход 45 мм, два захода, сдвиг 180°.
- Пользовательские незакоммиченные изменения в основном checkout не изменять и не удалять.

---

### Task 1: Зафиксировать новый интерфейс и геометрию тестами

**Files:**
- Modify: `tests/test_helical_rebar_insert.py`
- Modify: `tests/helical_insert_probes.scad`

**Interfaces:**
- Consumes: существующие `run_openscad()`, `inspect_binary_stl()` и публичные модули `helicalInsert()`/`fullInsert()`.
- Produces: ожидаемые диагностические поля `core_clearance`, `bore_d`, `wall_t`, `cage_d`, `slot_width`, `entry_d`; SCAD-пробы `entry_void` и `entry_wall`.

- [ ] **Step 1: Написать падающие проверки вычисляемых размеров**

Заменить таблицу ширин таблицей толщин:

```python
FIT_DIMENSIONS = {
    "loose": (1.2, 12.2),
    "medium": (1.3, 12.4),
    "tight": (1.4, 12.6),
}
```

В `test_calibration_metrics_match_measured_rebar` для каждого варианта проверить:

```python
self.assertAlmostEqual(metrics["core_d"], 9.1)
self.assertAlmostEqual(metrics["core_clearance"], 0.7)
self.assertAlmostEqual(metrics["bore_d"], 9.8)
self.assertAlmostEqual(metrics["wall_t"], expected_wall)
self.assertAlmostEqual(metrics["cage_d"], expected_cage)
self.assertAlmostEqual(metrics["slot_width"], 3.5)
self.assertAlmostEqual(metrics["entry_d"], 10.8)
```

Добавить тест, который рендерит `Fit="tight"` при `Socket_D_mm=12.4` и требует успешный результат: это доказывает удаление старого ограничения `cage_d < Socket_D_mm`.

- [ ] **Step 2: Написать падающие SCAD-пробы конического входа**

Расширить `Probe` значениями `entry_reference_low`, `entry_void`,
`entry_reference_high` и `entry_wall`; добавить сферу диаметром 0.3 мм на радиусе
5.2 мм. Поворачивать её в середину ленты, на угол
`360 * z / Helix_Lead_mm + 90`, чтобы внутренний винтовой канал не маскировал
проверку входа. Для `entry_void` расположить сферу на `z=0.1` и вычесть полную
втулку — объём сферы должен сохраниться. Для `entry_wall` расположить её на
`z=Flange_Thickness_mm-0.1` и пересечь с полной втулкой — объём должен сохраниться.

В Python добавить общий тест, сравнивающий `entry_void` с `entry_reference_low`, а
`entry_wall` с `entry_reference_high` с допуском 5%, `components == 1` и
`nonmanifold_edges == 0`.

- [ ] **Step 3: Запустить тесты и подтвердить RED**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
```

Expected: FAIL, потому что `loose/tight` ещё не поддерживаются, диагностических полей нет, а вход в буртике цилиндрический.

---

### Task 2: Реализовать толщину стенки и конический вход

**Files:**
- Modify: `rebar_insert.scad`
- Test: `tests/test_helical_rebar_insert.py`
- Test: `tests/helical_insert_probes.scad`

**Interfaces:**
- Consumes: ожидания Task 1.
- Produces: функции `_coreBoreDiameter()`, `_wallThickness(fit)`, `_cageDiameter(fit)`, `_entryDiameter()`; модуль `helicalInsert(fit, workingLength, markerCount)`.

- [ ] **Step 1: Заменить основные и вторичные параметры**

Использовать следующие публичные значения:

```scad
Part = "full";
Fit = "medium"; // [loose, medium, tight]
Core_D_mm = 9.1;
Core_Diametral_Clearance_mm = 0.7;
Wall_Thickness_mm = 1.3;
Rib_Slot_Width_mm = 3.5;
Entry_Extra_Clearance_mm = 1.0;
Socket_D_mm = 12.4;
Rib_Radial_Clearance_mm = 0.3;
fitWallStep = 0.1;
```

Удалить `Core_Clearance_mm`, `Cage_D_mm`, `fitClearanceStart` и `fitClearanceStep`.

- [ ] **Step 2: Реализовать производные размеры и новую семантику Fit**

```scad
function _fitIndex(fit) =
    fit == "loose" ? 0
    : fit == "medium" ? 1
    : fit == "tight" ? 2
    : assert(false, str("Unsupported Fit: ", fit)) 0;
function _coreBoreDiameter() =
    Core_D_mm + Core_Diametral_Clearance_mm;
function _wallThickness(fit) =
    Wall_Thickness_mm + (_fitIndex(fit) - 1) * fitWallStep;
function _cageDiameter(fit) =
    _coreBoreDiameter() + 2 * _wallThickness(fit);
function _entryDiameter() =
    _coreBoreDiameter() + Entry_Extra_Clearance_mm;
```

Проверять `Rib_Slot_Width_mm > Rib_Width_mm`, `_wallThickness(Fit) > 0`,
`_coreBoreDiameter() < _cageDiameter(Fit)`, `_entryDiameter() >= _coreBoreDiameter()`
и `_entryDiameter() < Flange_D_mm`. Не сравнивать `_cageDiameter(Fit)` с
`Socket_D_mm`.

- [ ] **Step 3: Передавать Fit в геометрию рабочей части**

Изменить сигнатуру на:

```scad
module helicalInsert(fit, workingLength, markerCount)
```

Внутри вычислить `cageDiameter = _cageDiameter(fit)`. Использовать его в цилиндре
рабочей части и передавать в `_throughSlots(slotWidth, totalHeight, cageDiameter)`.
Во всех вызовах использовать `slotWidth=Rib_Slot_Width_mm`; набор строить по
`["loose", "medium", "tight"]`.

- [ ] **Step 4: Вычесть конический вход отдельно от прямого отверстия**

В `difference()` заменить один центральный цилиндр двумя перекрывающимися телами:

```scad
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
```

Сохранить вычитание внутренних винтовых каналов и сквозных прорезей; их выход на
рабочей части должен оставаться правым.

- [ ] **Step 5: Обновить диагностику и пробы**

Вывести:

```scad
" core_clearance=", Core_Diametral_Clearance_mm,
" bore_d=", _coreBoreDiameter(),
" wall_t=", _wallThickness(Fit),
" cage_d=", _cageDiameter(Fit),
" slot_width=", Rib_Slot_Width_mm,
" entry_d=", _entryDiameter(),
```

В `tests/helical_insert_probes.scad` использовать `_cageDiameter("medium")` для
радиуса спиральных проб и новую сигнатуру `helicalInsert(fit="medium", ...)`.

- [ ] **Step 6: Запустить тесты до GREEN**

Run:

```bash
python3 -m unittest discover -s tests -p 'test_helical_rebar_insert.py' -v
python3 -m unittest discover -s tests -v
```

Expected: все тесты PASS, каждый отдельный STL имеет 0 non-manifold рёбер, набор
имеет 3 компонента, правая спираль и конический вход проходят пробы.

- [ ] **Step 7: Закоммитить модель и тесты**

```bash
git add rebar_insert.scad tests/test_helical_rebar_insert.py tests/helical_insert_probes.scad
git commit -m "Refactor insert fit around wall thickness"
```

---

### Task 3: Обновить экспорт, артефакты и инструкцию

**Files:**
- Modify: `scripts/render_rebar_insert.sh`
- Modify: `.gitignore`
- Modify: `REBAR_CONNECTORS.md`
- Delete: `build/helical_insert_calibration_narrow.stl`
- Delete: `build/helical_insert_calibration_wide.stl`
- Create: `build/helical_insert_calibration_loose.stl`
- Create: `build/helical_insert_calibration_tight.stl`
- Regenerate: `build/helical_insert_calibration_medium.stl`
- Regenerate: `build/helical_insert_calibration_set.stl`
- Regenerate: `build/helical_insert_full_medium.stl`
- Regenerate: `build/helical_insert_calibration_set.png`
- Regenerate: `build/helical_insert_full_medium.png`
- Regenerate: `build/helical_insert_assembly_preview.png`

**Interfaces:**
- Consumes: `Fit="loose|medium|tight"` и новую геометрию Task 2.
- Produces: печатные STL/PNG с однозначными именами и актуальная инструкция.

- [ ] **Step 1: Переименовать экспортируемые варианты**

В `scripts/render_rebar_insert.sh` заменить цикл на:

```bash
for fit in loose medium tight; do
```

В `.gitignore` разрешить `helical_insert_calibration_loose.stl` и
`helical_insert_calibration_tight.stl`, убрать исключения `narrow/wide`.

- [ ] **Step 2: Переписать раздел втулки в инструкции**

Зафиксировать:

- основные параметры 9.1 мм, диаметральный зазор 0.7 мм и базовую стенку 1.3 мм;
- варианты `loose/medium/tight` со стенками 1.2/1.3/1.4 мм и диаметрами
  12.2/12.4/12.6 мм;
- общую прорезь 3.5 мм;
- вход буртика 10.8→9.8 мм;
- порядок примерки от `medium`, затем `loose` при тугой посадке или `tight` при
  люфте;
- печать PETG буртиком на столе и визуальную проверку непрерывности лент.

- [ ] **Step 3: Перегенерировать все артефакты**

Run:

```bash
scripts/render_rebar_insert.sh
```

Expected: команда завершается с кодом 0 и создаёт три новых отдельных STL,
набор, полноразмерный STL и три PNG без hardwarnings.

- [ ] **Step 4: Проверить и закоммитить артефакты**

Run:

```bash
python3 -m unittest discover -s tests -v
git diff --check
```

Expected: PASS и пустой вывод `git diff --check`.

```bash
git add .gitignore REBAR_CONNECTORS.md scripts/render_rebar_insert.sh build/
git commit -m "Publish wall-thickness insert calibration set"
```

---

### Task 4: Финальная проверка ветки

**Files:**
- Verify only; production files не изменять без нового RED-теста.

**Interfaces:**
- Consumes: все результаты Tasks 1–3.
- Produces: проверенную ветку, готовую к review и интеграции без потери пользовательского WIP.

- [ ] **Step 1: Запустить свежую полную проверку**

```bash
python3 -m unittest discover -s tests -v
scripts/render_rebar_insert.sh
git diff --check
git status --short
```

Expected: все тесты PASS; экспорт PASS; `git diff --check` пуст; status содержит
только ожидаемые изменения либо чист.

- [ ] **Step 2: Просмотреть PNG и размеры STL**

Открыть три новых PNG, убедиться, что вход буртика расширен без разрыва кольца,
калибровочные детали различаются метками, а полная втулка имеет две непрерывные
правые винтовые ленты. Через `inspect_binary_stl` подтвердить 0 non-manifold рёбер,
1 компонент у отдельных деталей и 3 компонента у набора.

- [ ] **Step 3: Провести code review и подготовить интеграцию**

Использовать `superpowers:requesting-code-review`, исправить только подтверждённые
замечания и повторить полную проверку. Не сливать ветку в грязный основной checkout,
пока пользовательские изменения `rebar_insert.scad` не сохранены отдельным безопасным
способом.
