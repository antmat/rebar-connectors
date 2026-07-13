# BOSL2 — справочник и правила применения

> Цель документа — дать LLM и человеку компактную выжимку правил библиотеки
> **BOSL2 (Belfry OpenSCAD Library v2)**, принятой в репозитории `cads`.
> Фокус: ориентация/анкеринг, базовые примитивы, ключевые приёмы.
> Общие правила стиля и структуры файлов см. в [CONVENTIONS.md](./CONVENTIONS.md).
> Полная подпись функций — в [CheatSheet](https://github.com/BelfrySCAD/BOSL2/wiki/CheatSheet).

---

## Детальные справочники (подгружать при необходимости)

Этот документ — **верхний уровень** (выжимка). Для углублённой работы подгружайте нужный модуль:

* **Примитивы:** [cuboid](./BOSL2/cuboid.md) · [cyl](./BOSL2/cyl.md) · [prismoid](./BOSL2/prismoid.md) · [tube](./BOSL2/tube.md)
* **Концепции:** [attachments — анкеринг, `edges=`/`corners=`](./BOSL2/attachments.md)
* **Приёмы:** [tagging — `diff`/`tag`](./BOSL2/tagging.md) · [rounding-masks — скругления и маски](./BOSL2/rounding-masks.md)

---

## 0. Когда использовать BOSL2

* **Обязательно**, как только появляются: множественные симметрии/паттерны, скругления/фаски,
  параметризованные примитивы (трубы, призмоиды), относительное позиционирование, вычитание с тегами,
  текстуры, резьбы, шестерни, петли.
* **Допустимо** писать на чистом OpenSCAD (`cube/cylinder/translate/rotate`) для тривиальных деталей,
  где BOSL2 не даёт выигрыша.
* Подключение: `include <BOSL2/std.scad>` (даёт константы + весь базовый набор).
  Доп. модули по необходимости: `BOSL2/joiners.scad`, `BOSL2/sliders.scad`, `BOSL2/threading.scad`,
  `BOSL2/gears.scad`, `BOSL2/screws.scad`, `BOSL2/hinges.scad`, `BOSL2/rounding.scad`, `BOSL2/skin.scad`.
  Разница `include` vs `use` — см. CONVENTIONS §2.

---

## 1. Система координат и ориентация (КРИТИЧНО)

### 1.1. Система координат
* **Правосторонняя**, ось **Z — вверх** (это направление «слоёв печати» по умолчанию).
* `+X` — вправо, `+Y` — назад (от зрителя), `+Z` — вверх.

### 1.2. Векторные константы направления (`constants.scad`)
Используйте именованные константы **вместо** рукописных `[0,0,1]`:

| Константа | Значение | Алиасы |
|-----------|----------|--------|
| `RIGHT`  | `[1,0,0]`  | — |
| `LEFT`   | `[-1,0,0]` | — |
| `BACK`   | `[0,1,0]`  | — |
| `FRONT`  | `[0,-1,0]` | `FWD`, `FORWARD` |
| `UP`     | `[0,0,1]`  | `TOP` |
| `DOWN`   | `[0,0,-1]` | `BOTTOM`, `BOT` |
| `CENTER` | `[0,0,0]`  | `CTR`, `CENTRE` |

Прочее: `$slop` (зазор подгонки, по умолчанию 0.2), `INCH = 25.4`, `IDENT` (единичная матрица 4×4),
`SEGMENT`/`RAY`/`LINE` — спецификаторы линий.

### 1.3. Анкеринг — три параметра: `anchor`, `spin`, `orient`
Почти каждый примитив BOSL2 принимает (и возвращает) три параметра позиционирования:

* **`anchor=`** — **точка на объекте**, которая помещается в начало координат родителя.
  Это **вектор направления**, и анкеры **складываются**:
  * грань (face) = одно направление: `TOP`, `BOTTOM`, `LEFT`, `RIGHT`, `FRONT`, `BACK`;
  * ребро (edge) = два направления: `TOP+RIGHT`, `BOTTOM+FRONT`;
  * угол (corner) = три направления: `TOP+RIGHT+BACK`.
  * Сервисные функции: `EDGE(i)` — анкер ребра по индексу, `FACE(i)` — анкер грани.
* **`spin=`** — поворот **вокруг оси Z** (после установки anchor), в градусах.
* **`orient=`** — вектор направления, вдоль которого ориентируется «верх» (TOP) объекта.
  Напр. `orient=RIGHT` кладёт объект на бок так, что его верх смотрит в `+X`.

### 1.4. Анкер по умолчанию (ЧАСТАЯ ОШИБКА)
Большинство примитивов BOSL2 **центрированы по умолчанию** (`anchor=CENTER`).

| По умолчанию `CENTER` | По умолчанию `BOTTOM` |
|-----------------------|------------------------|
| `cube`, `cuboid`, `cyl`, `xcyl/ycyl/zcyl`, `tube`, `spheroid`, `torus`, `teardrop`, `onion`, `regular_prism`, `pie_slice`, все 2D-примитивы | **`prismoid`**, **`cylinder`** (нативная обёртка) |

* Типичная ошибка — **предполагать**, что 3D-объект «стоит на плоскости». Чаще всего он центрирован
  (напр. `cuboid(10)` занимает `z=-5..5`). Поставить на основание: `anchor=BOT` или `center=true`.
* И наоборот: `prismoid(...)` **уже** стоит на `z=0` (BOTTOM) — не добавляйте лишний сдвиг вверх.
* Полная таблица дефолтов и система `edges=` — в [attachments.md](./BOSL2/attachments.md).

### 1.5. Правила анкеринга для LLM
1. Не смешивайте `translate()` и `attach()` для одной и той же цели — выберите одно.
   Для позиционирования дочерних деталей **относительно родителя** используйте attach-модули (§6.1),
   для сдвига внутри — `move/xmove/ymove/zmove`.
2. Задавая размер, помните про дефолтный анкер: большинство примитивов **`CENTER`** (центрированы),
   `prismoid`/`cylinder` — **`BOTTOM`** (стоят на z=0). Указывайте анкер явно, если поведение важно.
3. `anchor` позиционирует объект, **а не** точку внутри него: объект сдвигается так, чтобы анкерная точка
   оказалась в начале координат.
4. `spin` всегда вокруг Z. Для поворота вокруг других осей внутри attach-контекста передавайте `spin` модулям
   `orient/align/attach`, либо используйте `rot()` перед примитивом.

---

## 2. Базовые трансформации (`transforms.scad`)

Каждая работает и как **модуль** (`move(v) CHILDREN;`), и как **функция** над точками
(`p2 = move(v, p=points);`), и возвращает **матрицу** (`M = move(v);`), которую применяет `apply(M, points)`.

| Модуль | Действие |
|--------|----------|
| `move(v)` / `xmove(d)` / `ymove(d)` / `zmove(d)` | сдвиг |
| `left/right/fwd/back/up/down(x)` | сдвиг по соответствующей оси |
| `rot(a)` / `rot([X,Y,Z])` / `rot(a,v)` / `rot(from=,to=)` | поворот (от вектора к вектору — очень полезно) |
| `xrot/yrot/zrot(a, [cp=])` | поворот вокруг оси |
| `tilt(to)` | наклонить так, чтобы TOP смотрел на `to` |
| `scale(v)` / `xscale/yscale/zscale` | масштабирование (`cp=` — центр, `dir=` — по направлению) |
| `mirror(v)` / `xflip/yflip/zflip([x=])` | отражение |
| `frame_map(v1,v2,v3)` | отображение одной системы координат в другую |
| `skew(sxy=, ...)` | сдвиг/скашивание |
| `apply(M, points)` | применить матрицу трансформации к списку точек |

---

## 3. Дистрибуции — копии без `for` (`distributors.scad`)

Предпочитайте эти модули ручным циклам `for`. Все имеют формы `copies=f(p=)` и `mats=f()`.

* **Линейные:** `xcopies/spacing,[n])`, `ycopies`, `zcopies`, `line_copies([spacing],[n])`,
  `move_copies(list_of_vectors)`.
* **Сетка:** `grid_copies(spacing|n=, size=, [stagger=], [inside=])`.
* **Вращательные:** `rot_copies(rots|n=, [v=])`, `xrot_copies/yrot_copies/zrot_copies`,
  `arc_copies(n, r|d=, [sa=],[ea=])`, `sphere_copies(n, ...)`.
* **По пути:** `path_copies(path, [n],[spacing])`.
* **Отражающие:** `xflip_copy/yflip_copy/zflip_copy([x])`, `mirror_copy(v, [cp])` — ребёнок + его зеркальная копия.
* **Разные дети в ряд:** `xdistribute/ydistribute/zdistribute(spacing|l=)`, `distribute([dir=])`.

---

## 4. Базовые 2D-примитивы (`shapes2d.scad`)

По умолчанию `anchor=CENTER`. Каждый доступен и как модуль `[ATTACHMENTS]`, и как функция `path = f(...)`.

* **Прямоугольники/круги:** `square`, `rect(size, [rounding=],[chamfer=])`, `circle(r|d=)`, `ellipse(r|d=)`.
* **Многоугольники:** `regular_ngon(n, r|d=|or=|od=|ir=|id=|side=)`, `pentagon`, `hexagon`, `octagon`,
  `right_triangle`, `trapezoid(h,w1,w2,[shift=])`, `star(n,r,ir|step=)`.
* **Кривые формы:** `teardrop2d`, `egg`, `ring`, `glued_circles`, `squircle`, `keyhole`,
  `reuleaux_polygon`, `supershape`.
* **Текст:** `text(...)`.
* **Скругление 2D:** `round2d(r|or=|ir=)`, `shell2d(thickness, [or],[ir])`.

---

## 5. Базовые 3D-примитивы (`shapes3d.scad`)

По умолчанию `anchor=CENTER` (исключения: `prismoid` и `cylinder` — `BOTTOM`). Доступны как модуль `[ATTACHMENTS]` и как функция `vnf = f(...)`.

### Кубоиды и призмы
* `cube(size, [center])` — обёртка над нативным.
* **`cuboid(size, [rounding=],[chamfer=],[edges=],[except=])`** — основной прямоугольный параллелепипед
  со скруглением/фаской выбранных рёбер. `p1=/p2=` — по двум углам. → [детально](./BOSL2/cuboid.md)
* **`prismoid(size1, size2, h|l=, [shift=],[rounding=],[chamfer=])`** — усечённая призма (разные сечения снизу/сверху). → [детально](./BOSL2/prismoid.md)
* `regular_prism(n, h=, r=|d=|side=, [rounding=],[texture=])`, `rect_tube`, `wedge`, `octahedron`.

### Цилиндры и трубы
* `cylinder(h, r|d=, [center])` — обёртка.
* **`cyl(l|h=, r|d=, [chamfer=],[rounding=],[texture=])`** — основной цилиндр со скруглением/фаской/текстурой. → [детально](./BOSL2/cyl.md)
* **`xcyl/ycyl/zcyl(l, r|d=)`** — цилиндр, ориентированный вдоль соответствующей оси (без `rot`).
* **`tube(h, or|ir|wall=, [rounding=],[chamfer=])`** — полый цилиндр (труба). → [детально](./BOSL2/tube.md)
* `pie_slice(l, r, ang)`.

### Круглые тела
* `sphere(r|d=)`, **`spheroid(r|d=, [style=])`** (контроль триангуляции),
  **`torus(r_maj, r_min | or=,ir=)`**, `teardrop(h,r,[ang],[cap_h])` (для печати без поддержек),
  `onion(r|d=,[ang],[cap_h])`.

### Прочее
* **Текст 3D:** `text3d(text, [h],[size],[font])`, `path_text(path, text, ...)` (текст вдоль пути).
* `fillet(l, r|d=, [ang=])`, `ruler(...)`, `plot3d(f,x,y)`, `plot_revolution(...)`.

### Аргументы рёбер/граней (важно для `cuboid`/`cyl`)
* `edges=` — какие рёбра скруглять (`TOP`, `BOTTOM`, `LEFT+RIGHT`, `EXCEPT(...)`, `"X"` и т.п.);
* `except=` — исключить; `trimcorners=` — сопряжение в углах; `teardrop=` — скругление «каплей» для печати.

---

## 6. Ключевые приёмы

### 6.1. Attachments — относительное позиционирование (`attachments.scad`) → [детально](./BOSL2/attachments.md)
Применяются **после родителя** в виде `PARENT() module(...) CHILDREN;`:

* `position(at)` — поставить детей в точку-анкер `at` родителя (без изменения ориентации детей).
* `orient(anchor, [spin])` — ориентировать детей на направление `anchor` родителя.
* `align(anchor, [align=], [inside=],[inset=],[overlap=])` — прижать анкер ребёнка к анкеру родителя.
* **`attach(parent, child, [overlap=],[spin=],[inside=])`** — позиция + ориентация:
  анкер `child` ребёнка стыкуется к анкеру `parent` родителя, ребёнок разворачивается по нормали.
  Форма с одним аргументом: `attach(parent)` — дети «растут» из этой грани родителя наружу.
* `attach_part(name, [ind])` — доступ к именованной части родителя.

### 6.2. Тэгирование и чистые булевы операции → [детально](./BOSL2/tagging.md)
Вместо громоздкого `difference() {...}`:

* `tag("remove") CHILDREN;` / `tag("keep")` / `force_tag` / `default_tag` / `tag_scope`.
* **`diff([remove], [keep]) PARENT() CHILDREN;`** — вычесть из родителя всё с тегом «remove».
* **`intersect([intersect], [keep]) PARENT() CHILDREN;`** — оставить пересечение.
* `conv_hull([keep])`, `hide(tags)`, `show_only(tags)`, `hide_this()`.
* Синонимы с явным тегом: `tag_diff`, `tag_intersect`, `tag_conv_hull`.

### 6.3. Связывание с объектами-описаниями (для расчётов)
`parent()`, `parent_part(name)`, `restore(desc)`, `desc_point`, `desc_dist`, `transform_desc`,
`desc_copies(transforms)`, `is_description(desc)` — позволяют измерять/копировать по описанию родителя.

### 6.4. Скругление и маски → [детально](./BOSL2/rounding-masks.md)
* **2D-маски** (`masks.scad`): `mask2d_roundover`, `mask2d_chamfer`, `mask2d_teardrop`, `mask2d_cove`,
  `mask2d_dovetail`, `mask2d_rabbet`, `mask2d_smooth`, `mask2d_ogee`.
* **Применение масок:** `edge_profile([edges],[except]) CHILDREN;` (профиль по рёбрам),
  `face_profile(faces, r|d=)`, `corner_profile([corners])`.
* **3D-маски рёбер/углов:** `chamfer_edge_mask`, `round_edge_mask`, `round_corner_mask` и т.д.
* **Общее:** `round2d(r)`, `round3d(r|or=,ir=)`, `offset3d(r)`, `offset_sweep`, `rounded_prism(...)`,
  `round_corners(path, [radius=]|[cut=]|[joint=])`.

### 6.5. Hull и смещения
* `hull()` — стандартный; **`chain_hull() CHILDREN;`** — последовательный hull между парами детей
  (плавные переходы между сечениями). **Ресурсоёмко при рендере — применять обдуманно.**
* `bounding_box()`, `minkowski_difference()`, `half_of(v,[cp])` / `left_half/right_half/top_half/...`,
  `partition(...)` (разрез на сцепляющиеся половины).

### 6.6. Выдавливание и заметание (`skin.scad`, `miscellaneous.scad`)
* `linear_sweep(region, h, [twist=],[scale=],[texture=])` — выдавливание 2D-области.
* `rotate_sweep(shape, [angle])` — вращение 2D-профиля вокруг Z (тела вращения).
* `path_sweep(shape, path, [normal=],[twist=],[scale=])` — заметание 2D-сечения вдоль 3D-пути.
* `skin(profiles, [slices=],[method=])` — обтянутая оболочка по стеку сечений.
* `spiral_sweep`, `path_sweep2d`, `sweep(shape, transforms)`.
* Низкоуровневые: `extrude_from_to(pt1,pt2)`, `path_extrude2d`, `cylindrical_extrude`.

### 6.7. VNF (Verdictized Naked Faces) — прямое построение полиэдрников (`vnf.scad`)
* Создание: `vnf_vertex_array(grid, [style=],[caps=])`, `vnf_from_polygons`, `vnf_from_region`, `vnf_join([...])`.
* Отрисовка: `vnf_polyhedron(vnf)`.
* Операции: `vnf_halfspace(plane, vnf)`, `vnf_hull(vnf)`, `vnf_volume`, `vnf_area`, `vnf_bend(vnf, r=)`,
  `vnf_quantize`, `vnf_merge_points`, `vnf_triangulate`, `vnf_validate` (отладка).

### 6.8. Рисование линий/дуг (`drawing.scad`)
`stroke(path, [width],[endcaps])`, `arc(n, r=, angle)`, `helix(...)`, `catenary(...)`, `turtle(commands)`.

### 6.9. Пути и кривые (`paths.scad`, `rounding.scad`, `beziers.scad`)
* `path_length`, `resample_path`, `subdivide_path`, `path_cut`, `polygon_parts` (разбор самопересечений).
* `round_corners`, `smooth_path`, `path_join`, `offset_stroke`.
* Безье: `bezier_curve(bez, [splinesteps])`, `bezpath_curve`, `bezier_vnf` (поверхности).

### 6.10. Цвет и отладка (`color.scad`)
`recolor(c)`, `color_this(c)`, `rainbow(list)`, `color_overlaps()`, `highlight()`/`ghost()`,
`hsl(h,s,l)`/`hsv(...)`.

---

## 7. Готовые инженерные модули (кратко, по ссылке на CheatSheet)

Подключаются отдельными файлами. Использовать готовыми, **не** переписывать вручную:

* **Резьбы** (`threading.scad`): `threaded_rod/threaded_nut`, `trapezoidal_*`, `acme_*`,
  `square_*`, `buttress_*`, `ball_screw_rod`, `thread_helix`.
* **Винты/гайки** (`screws.scad`): `screw(spec, head, drive, length=)`, `screw_hole(...)`, `nut(...)`,
  `nut_trap_side/inline`, `screw_info(...)`.
* **Шестерни** (`gears.scad`): `spur_gear(circ_pitch|mod=, teeth=, thickness=)`, `ring_gear`, `rack`,
  `worm`, `worm_gear`, `crown_gear`, `planetary_gears`.
* **Петли** (`hinges.scad`): `knuckle_hinge(length,offset,segs)`, `living_hinge_mask`,
  `apply_folding_hinges_and_snaps`, `snap_lock/snap_socket`.
* **Соединители** (`joiners.scad`): `half_joiner`, `joiner`, `dovetail(gender,...)`, `snap_pin`,
  `rabbit_clip`, `hirth`.
* **Направляющие** (`sliders.scad`): `slider(l,w,h)`, `rail(l,w,h)`.
* **Подшипники** (`linear_bearings.scad`, `ball_bearings.scad`): `lmXuu_housing`, `ball_bearing`.
* **Стенки** (`walls.scad`): `sparse_wall`, `hex_panel`, `corrugated_wall`, `thinning_wall`, `thinning_triangle`.
* **Многогранники** (`polyhedra.scad`): `regular_polyhedron(name|type=, ...)`.
* Прочее: `bottlecaps`, `cubetruss`, `modular_hose`, `nema_steppers`, `hooks`, `wiring`.

---

## 8. Чек-лист типичных ошибок

1. **«Почему объект не там, где ожидал?»** — большинство 3D-примитивов **`CENTER`** (центрированы),
   только `prismoid`/`cylinder` — `BOTTOM`. Поставить на основание: `anchor=BOT` или `center=true`.
2. **Z-fighting** на совпадающих гранях — используйте `overlap=` в `attach(...)`, либо микро-сдвиг
   `fudge=0.01..0.1` (см. CONVENTIONS §5).
3. **`spin` крутит не ту ось** — `spin` всегда вокруг Z. Для поворота вокруг X/Y берите `xrot()/yrot()`
   или `orient=`.
4. **Смешивание `translate()` и `attach()`** — выберите одно. `attach`/`align`/`position` для сборки,
   `move/xmove/...` для сдвига внутри детали.
5. **Цилиндр вдоль X/Y** — не делайте `zrot(90) cyl(...)`, используйте `xcyl(...)`/`ycyl(...)`.
6. **Ручные циклы `for` для сеток/зеркал** — заменяйте на `xcopies/grid_copies/xflip_copy/...`.
7. **Вырезание отверстий через `difference`** — предпочтите `diff(){...; tag("remove") ...;}`.
8. **Тяжёлые `hull`/`chain_hull`** — только когда не справляются `rounding`/`chamfer` или заметание.
9. **Размеры без единиц** — называйте геометрические переменные с суффиксами `_mm`/`_XY` (CONVENTIONS §4).
10. **`$fa/$fs`** — всегда подключайте адаптивную точность (CONVENTIONS §3).
