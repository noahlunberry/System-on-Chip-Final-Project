# BNN FCC AXI4-Lite Bare-Metal Interface

This directory contains a bare-metal Vitis C++ driver skeleton for
`rtl/bnn_fcc_axi_lite.sv`. The design uses the Zynq PS as the only processor:
no Linux, no `/dev/mem`, no sysfs, and no softcore.

## Register Map

All registers are 32-bit AXI4-Lite words. Config and image stream data are
64-bit beats staged through low/high data registers, then committed by writing
the corresponding META register with `push` set.

| Offset | Name | Bits |
| --- | --- | --- |
| `0x00` | `CONTROL` | `[0]` accelerator reset pulse, `[1]` clear output FIFO, `[2]` clear sticky errors, `[3]` clear cycle counter |
| `0x04` | `STATUS` | `[0]` cfg_full, `[1]` img_full, `[2]` out_valid, `[3]` busy, `[4]` cfg_empty, `[5]` img_empty, `[6]` cfg_overflow, `[7]` img_overflow, `[8]` out_full, `[31:16]` in-flight image packets |
| `0x08` | `CFG_DATA_LO` | `config_data[31:0]` |
| `0x0c` | `CFG_DATA_HI` | `config_data[63:32]` |
| `0x10` | `CFG_META` | `[7:0]` config_keep, `[8]` config_last, `[16]` push_cfg |
| `0x14` | `IMG_DATA_LO` | `data_in_data[31:0]` |
| `0x18` | `IMG_DATA_HI` | `data_in_data[63:32]` |
| `0x1c` | `IMG_META` | `[7:0]` data_in_keep, `[8]` data_in_last, `[16]` push_img |
| `0x20` | `OUT_DATA` | zero-extended classification result at output FIFO head |
| `0x24` | `OUT_CTRL` | `[0]` pop output FIFO, `[1]` clear output FIFO |
| `0x28` | `CYCLE_COUNT` | increments while `STATUS.busy` is high |

## Data Packing

Config beats must match `rtl/README.md` and
`verification/bnn_fcc_tb_pkg.sv::get_layer_config()`:

- 128-bit config headers are emitted little-endian byte by byte.
- Weight bits are packed with weight 0 in payload byte bit 0.
- Weight payloads are padded with ones to a byte boundary per neuron.
- Thresholds are 32-bit little-endian words.
- The generated full-model stream follows the existing testbench order:
  weights for layer 0, thresholds for layer 0, weights for layer 1,
  thresholds for layer 1, then weights for the output layer.

Image beats pack eight 8-bit pixels per 64-bit word, with pixel 0 in bits
`[7:0]`. `data_in_last` is asserted on the last beat of each image.

## Vitis Notes

Add `sw/src/*.cpp` and generated headers from `sw/src` to a bare-metal Vitis
application. The provided Vivado Tcl names the RTL module-reference cell
`bnn_accel_0` and maps it at `0xA0000000`; `main.cpp` checks the common
`xparameters.h` macros for that cell. If your Vivado block has a different
name, define `BNN_FCC_BASEADDR` in the application build settings.

For a no-GUI command-line flow, use the scripts in `sw/cli`:

```sh
powershell -ExecutionPolicy Bypass -File .\sw\cli\build_app.ps1
powershell -ExecutionPolicy Bypass -File .\sw\cli\run_jtag.ps1
```

Regenerate the compiled-in data after changing the model or test vectors:

```sh
python sw/tools/generate_bnn_headers.py
```
