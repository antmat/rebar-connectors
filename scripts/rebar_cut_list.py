#!/usr/bin/env python3

import argparse
import math

LOWER_STOP_MM = 11.248023074035522
UPPER_STOP_MM = 13.6446737856353
APEX_STOP_MM = 23.432072176330976
INSERT_STOP_GAP_MM = 1.0
ROOF_ANGLE_DEG = 30.0


def positive_mm(value: str) -> float:
    try:
        number = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "ожидается число в миллиметрах"
        ) from error
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError(
            "значение должно быть положительным числом"
        )
    return number


def cut_groups(
    diameter_mm: float,
    height_mm: float,
) -> list[tuple[str, int, float]]:
    octagon_side_mm = diameter_mm * math.sin(math.radians(22.5))
    roof_centerline_mm = diameter_mm / (
        2 * math.cos(math.radians(ROOF_ANGLE_DEG))
    )
    return [
        (
            "Нижний восьмиугольник",
            8,
            octagon_side_mm - 2 * (LOWER_STOP_MM + INSERT_STOP_GAP_MM),
        ),
        (
            "Верхний восьмиугольник",
            8,
            octagon_side_mm - 2 * (UPPER_STOP_MM + INSERT_STOP_GAP_MM),
        ),
        (
            "Вертикальные стойки",
            8,
            height_mm
            - (LOWER_STOP_MM + INSERT_STOP_GAP_MM)
            - (UPPER_STOP_MM + INSERT_STOP_GAP_MM),
        ),
        (
            "Лучи крыши",
            8,
            roof_centerline_mm
            - (UPPER_STOP_MM + INSERT_STOP_GAP_MM)
            - (APEX_STOP_MM + INSERT_STOP_GAP_MM),
        ),
    ]


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


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description=(
            "Расчёт раскроя арматуры для восьмиугольной "
            "конструкции"
        )
    )
    result.add_argument(
        "--diameter",
        required=True,
        type=positive_mm,
        metavar="ММ",
        help="диаметр между центрами противоположных вершин",
    )
    result.add_argument(
        "--height",
        required=True,
        type=positive_mm,
        metavar="ММ",
        help="высота между центрами нижних и верхних креплений",
    )
    return result


def main() -> None:
    argument_parser = parser()
    arguments = argument_parser.parse_args()
    exact_groups = cut_groups(arguments.diameter, arguments.height)
    invalid = [
        (name, length)
        for name, _, length in exact_groups
        if length <= 0
    ]
    if invalid:
        details = ", ".join(
            f"{name}: {length:.1f} мм"
            for name, length in invalid
        )
        argument_parser.error(
            "размеры конструкции дают неположительные длины: "
            + details
        )

    groups = rounded_cut_groups(arguments.diameter, arguments.height)
    piece_count = sum(count for _, count, _ in groups)
    total_mm = sum(count * length for _, count, length in groups)
    if not math.isfinite(total_mm):
        argument_parser.error(
            "суммарная длина выходит за допустимый диапазон"
        )

    print(f"Диаметр по вершинам: {arguments.diameter:.1f} мм")
    print(f"Высота конструкции:  {arguments.height:.1f} мм")
    print()
    for name, count, length in groups:
        print(f"{name:<24}: {count} шт. × {length} мм")

    print()
    print("Рекомендуемый допуск реза: ±1 мм")
    print(f"Всего: {piece_count} отрезка, {total_mm / 1000:.3f} м")


if __name__ == "__main__":
    main()
