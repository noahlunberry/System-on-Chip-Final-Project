#!/usr/bin/env python3
"""Generate bare-metal C++ headers for the BNN FCC AXI-Lite driver."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable


TOPOLOGY = [784, 256, 256, 10]
BUS_BYTES = 8


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, default=repo_root / "python" / "model_data")
    parser.add_argument("--inputs", type=Path, default=repo_root / "python" / "test_vectors" / "inputs.hex")
    parser.add_argument(
        "--expected",
        type=Path,
        default=repo_root / "python" / "test_vectors" / "expected_outputs.txt",
    )
    parser.add_argument("--out-dir", type=Path, default=repo_root / "sw" / "src")
    parser.add_argument("--num-images", type=int, default=-1)
    return parser.parse_args()


def read_weight_rows(path: Path) -> list[list[int]]:
    rows: list[list[int]] = []
    for line in path.read_text().splitlines():
        bits = [1 if ch == "1" else 0 for ch in line.strip() if ch in "01"]
        if bits:
            rows.append(bits)
    return rows


def read_thresholds(path: Path) -> list[int]:
    values: list[int] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            values.append(int(line, 10))
    return values


def append_u32_le(out: list[int], value: int) -> None:
    value &= 0xFFFFFFFF
    for i in range(4):
        out.append((value >> (8 * i)) & 0xFF)


def append_header(
    out: list[int],
    msg_type: int,
    layer_idx: int,
    layer_inputs: int,
    num_neurons: int,
    bytes_per_neuron: int,
    total_payload_bytes: int,
) -> None:
    header = 0
    header |= (msg_type & 0xFF) << 0
    header |= (layer_idx & 0xFF) << 8
    header |= (layer_inputs & 0xFFFF) << 16
    header |= (num_neurons & 0xFFFF) << 32
    header |= (bytes_per_neuron & 0xFFFF) << 48
    header |= (total_payload_bytes & 0xFFFFFFFF) << 64

    for i in range(16):
        out.append((header >> (8 * i)) & 0xFF)


def append_weight_message(out: list[int], layer_idx: int, rows: list[list[int]]) -> None:
    fan_in = TOPOLOGY[layer_idx]
    num_neurons = TOPOLOGY[layer_idx + 1]
    bytes_per_neuron = (fan_in + 7) // 8
    total_payload_bytes = bytes_per_neuron * num_neurons

    if len(rows) != num_neurons:
        raise ValueError(f"layer {layer_idx} has {len(rows)} weight rows, expected {num_neurons}")

    append_header(out, 0, layer_idx, fan_in, num_neurons, bytes_per_neuron, total_payload_bytes)

    for neuron, bits in enumerate(rows):
        if len(bits) != fan_in:
            raise ValueError(
                f"layer {layer_idx} neuron {neuron} has {len(bits)} weights, expected {fan_in}"
            )

        weight_idx = 0
        for _ in range(bytes_per_neuron):
            byte_value = 0
            for bit_idx in range(8):
                if weight_idx < fan_in:
                    bit_value = bits[weight_idx]
                else:
                    bit_value = 1
                byte_value |= bit_value << bit_idx
                weight_idx += 1
            out.append(byte_value)


def append_threshold_message(out: list[int], layer_idx: int, thresholds: list[int]) -> None:
    num_neurons = TOPOLOGY[layer_idx + 1]
    bytes_per_neuron = 4
    total_payload_bytes = bytes_per_neuron * num_neurons

    if len(thresholds) != num_neurons:
        raise ValueError(
            f"layer {layer_idx} has {len(thresholds)} thresholds, expected {num_neurons}"
        )

    append_header(out, 1, layer_idx, 32, num_neurons, bytes_per_neuron, total_payload_bytes)

    for value in thresholds:
        append_u32_le(out, value)


def pack_config_beats(model_dir: Path) -> list[tuple[int, int, int]]:
    stream_bytes: list[int] = []
    num_layers = len(TOPOLOGY) - 1

    for layer_idx in range(num_layers):
        rows = read_weight_rows(model_dir / f"l{layer_idx}_weights.txt")
        append_weight_message(stream_bytes, layer_idx, rows)

        if layer_idx < num_layers - 1:
            thresholds = read_thresholds(model_dir / f"l{layer_idx}_thresholds.txt")
            append_threshold_message(stream_bytes, layer_idx, thresholds)

    beats: list[tuple[int, int, int]] = []
    for offset in range(0, len(stream_bytes), BUS_BYTES):
        chunk = stream_bytes[offset : offset + BUS_BYTES]
        data = 0
        keep = 0
        for lane, byte_value in enumerate(chunk):
            data |= byte_value << (8 * lane)
            keep |= 1 << lane
        beats.append((data, keep, 0))

    if beats:
        data, keep, _ = beats[-1]
        beats[-1] = (data, keep, 1)

    return beats


def read_images(path: Path, num_images: int) -> list[list[int]]:
    images: list[list[int]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if num_images >= 0 and len(images) >= num_images:
            break
        image = list(bytes.fromhex(line))
        if len(image) != TOPOLOGY[0]:
            raise ValueError(f"image has {len(image)} bytes, expected {TOPOLOGY[0]}")
        images.append(image)
    return images


def read_expected(path: Path, count: int) -> list[int]:
    values: list[int] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            values.append(int(line, 10))
        if len(values) == count:
            break
    if len(values) != count:
        raise ValueError(f"expected output file has {len(values)} rows, expected {count}")
    return values


def chunks(values: list[int], width: int) -> Iterable[list[int]]:
    for offset in range(0, len(values), width):
        yield values[offset : offset + width]


def write_model_header(path: Path, beats: list[tuple[int, int, int]]) -> None:
    lines: list[str] = [
        "#pragma once",
        "",
        '#include "BnnFcc.h"',
        "",
        "namespace bnn_data {",
        f"constexpr unsigned kConfigBeatCount = {len(beats)}u;",
        "static const BnnFccBeat kConfigBeats[kConfigBeatCount] = {",
    ]

    for data, keep, last in beats:
        lines.append(f"    {{0x{data:016x}ull, 0x{keep:02x}u, {last}u}},")

    lines.extend(["};", "", "} // namespace bnn_data", ""])
    path.write_text("\n".join(lines))


def write_test_header(path: Path, images: list[list[int]], expected: list[int]) -> None:
    lines: list[str] = [
        "#pragma once",
        "",
        "#include <cstdint>",
        "",
        "namespace bnn_data {",
        f"constexpr unsigned kImageCount = {len(images)}u;",
        f"constexpr unsigned kImageBytes = {TOPOLOGY[0]}u;",
        "static const std::uint8_t kImages[kImageCount][kImageBytes] = {",
    ]

    for image in images:
        lines.append("    {")
        for chunk in chunks(image, 16):
            values = ", ".join(f"0x{value:02x}u" for value in chunk)
            lines.append(f"        {values},")
        lines.append("    },")

    lines.extend(["};", "", "static const std::uint8_t kExpectedOutputs[kImageCount] = {"])
    for chunk in chunks(expected, 16):
        values = ", ".join(f"{value}u" for value in chunk)
        lines.append(f"    {values},")
    lines.extend(["};", "", "} // namespace bnn_data", ""])
    path.write_text("\n".join(lines))


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    beats = pack_config_beats(args.model_dir)
    images = read_images(args.inputs, args.num_images)
    expected = read_expected(args.expected, len(images))

    write_model_header(args.out_dir / "bnn_model_data.h", beats)
    write_test_header(args.out_dir / "bnn_test_data.h", images, expected)

    print(f"wrote {len(beats)} config beats")
    print(f"wrote {len(images)} images")


if __name__ == "__main__":
    main()
