# ZUBoard-1CG Bare-Metal BNN FCC Accelerator

This repository contains a bare-metal Zynq UltraScale+ demo for a binary neural
network fully connected classifier (`bnn_fcc`). The original accelerator remains
in `rtl/bnn_fcc.sv`; the board flow adds an AXI4-Lite MMIO wrapper so the Zynq
PS can send model configuration data and MNIST image data from C++.

The target board is the Avnet ZUBoard-1CG. The demo does not require Linux,
PetaLinux, or a softcore processor. It uses the hard Zynq PS, Vivado, XSCT, and
a bare-metal A53 application.

## Design Overview

The `bnn_fcc` module classifies MNIST-style 8-bit pixel images into one of ten
digits. The network topology used by the ZUBoard flow is:

```text
784 -> 256 -> 256 -> 10
```

The accelerator consumes:

- A configuration stream containing weights and thresholds.
- An image input stream containing 8-bit pixels.
- An output stream containing the predicted class.

All three accelerator-facing interfaces use AXI4-Stream-style
ready/valid/keep/last handshakes.

The RTL binarizes image pixels by comparing each 8-bit value against `128`:

```text
pixel >= 128 -> 1
pixel <  128 -> 0
```

Hidden-layer neurons output one bit. Output-layer neurons produce population
counts, and the BNN applies argmax to choose the predicted digit.

## ZUBoard Wrapper

The board-facing wrapper is:

```text
rtl/bnn_fcc_axi_lite.sv
```

Vivado instantiates it through:

```text
vivado/hdl/bnn_fcc_vivado_axi_lite_small.v
```

The wrapper exposes a 32-bit AXI4-Lite slave at:

```text
0xA0000000
```

It converts MMIO writes into the existing `bnn_fcc` streams:

- `config_*` for weights and thresholds.
- `data_in_*` for MNIST image pixels.
- `data_out_*` for classification results.

Small FIFOs/skid stages hold stream `valid` high until `bnn_fcc` asserts
`ready`. Output packets are captured into a small output FIFO that software
polls through status and output registers.

The small ZUBoard build uses:

| Parameter | Value |
| --- | --- |
| `PARALLEL_INPUTS` | `8` |
| `PARALLEL_NEURONS` | `{8, 8, 10}` |
| `TOPOLOGY` | `{784, 256, 256, 10}` |
| Config bus | 64-bit |
| Image bus | 64-bit |
| Output bus | 8-bit |

## Register Map

The AXI4-Lite register map is byte-addressed from the accelerator base address.

| Offset | Name | Description |
| --- | --- | --- |
| `0x00` | `CONTROL` | `[0]` reset pulse, `[1]` clear output FIFO, `[2]` clear sticky errors, `[3]` clear cycle counter |
| `0x04` | `STATUS` | `[0]` cfg full, `[1]` image full, `[2]` output valid, `[3]` busy, `[4]` cfg empty, `[5]` image empty, `[6]` cfg overflow, `[7]` image overflow, `[8]` output full |
| `0x08` | `CFG_DATA_LO` | `config_data[31:0]` |
| `0x0c` | `CFG_DATA_HI` | `config_data[63:32]` |
| `0x10` | `CFG_META` | `[7:0]` config keep, `[8]` config last, `[16]` push config beat |
| `0x14` | `IMG_DATA_LO` | `data_in_data[31:0]` |
| `0x18` | `IMG_DATA_HI` | `data_in_data[63:32]` |
| `0x1c` | `IMG_META` | `[7:0]` image keep, `[8]` image last, `[16]` push image beat |
| `0x20` | `OUT_DATA` | Classification result at output FIFO head |
| `0x24` | `OUT_CTRL` | `[0]` pop result, `[1]` clear output FIFO |
| `0x28` | `CYCLE_COUNT` | Counts cycles while the wrapper reports busy |

The configuration stream format follows `rtl/README.md` and the little-endian
packing used by `verification/bnn_fcc_tb_pkg.sv`.

## Software Organization

The bare-metal software is under:

```text
sw/src
```

It follows the same class organization style as the referenced convolve example,
but without Linux `mmap`, `/dev/mem`, sysfs, or `/dev/xdevcfg`.

| Class/File | Purpose |
| --- | --- |
| `Board` | Low-level MMIO reads/writes using `Xil_In32` and `Xil_Out32` |
| `App` | Typed helper layer above `Board` |
| `BnnFcc` | Accelerator-specific register protocol |
| `main.cpp` | Reset, send model config, send MNIST images, poll results, print timing |
| `bnn_model_data.h` | Compiled-in model configuration beats |
| `bnn_test_data.h` | Compiled-in MNIST image/test-label data |

## Hardware Connections

Connect the board before running the demo:

```text
J15 USB-C:     USB-C PD power supply with 15V support
J16 micro-USB: PC connection for onboard JTAG/UART
SW2 boot mode: ON-ON-ON-ON for JTAG
```

The board does not need exactly 45 W, but the USB-C supply must support the
15 V USB-C Power Delivery profile. A 45 W or 65 W USB-C PD charger is fine if
its label lists `15V`. Do not rely on the micro-USB JTAG/UART port for board
power.

Useful LEDs:

| LED | Meaning |
| --- | --- |
| `D14` | 15 V present |
| `D16` | 5 V present |
| `D17` | USB-C sink enabled |
| `D23` | Power good |

If the board gets hot quickly, unplug it and verify the charger/cable before
continuing.

## UART Terminal

Open a serial terminal before running the JTAG demo.

Use Tera Term or PuTTY:

```text
Port: COM4
Baud: 115200
Data: 8
Parity: none
Stop: 1
Flow control: none
```

If your COM port is different, find it with:

```powershell
Get-CimInstance Win32_SerialPort |
    Where-Object { $_.Name -match "USB|FTDI|UART|Serial" } |
    Select-Object DeviceID,Name
```

Close other serial tools if the terminal reports that the COM port is busy.

## One-Time Driver Setup

If Vivado or XSCT cannot see the board, install Xilinx cable drivers from an
Administrator PowerShell:

```powershell
cd C:\Xilinx\Vivado\2024.2\data\xicom\cable_drivers\nt64
.\install_drivers_wrapper.bat
```

Then unplug/replug `J16` and power-cycle the board.

## Build Hardware

From the repository root:

```powershell
cd C:\Users\pawin\UF\spring26\SoC-Design\System-on-Chip-Final-Project
C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source .\vivado\create_zuboard_bnn_project.tcl -tclargs -build_bitstream -jobs 4
```

Expected outputs:

```text
build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.xsa
build\vivado\zuboard_bnn_fcc\zuboard_bnn_fcc.runs\impl_1\zuboard_bnn_fcc_bd_wrapper.bit
```

The checked build met timing and passed routed DRC.

## Build Software

From the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\build_app.ps1
```

Expected ELF:

```text
build\vitis_cli\bnn_fcc_demo\Debug\bnn_fcc_demo.elf
```

## Connect With Vivado Hardware Manager

This matches the class workflow: confirm the board in Vivado Hardware Manager
before running the software.

Batch check:

```powershell
C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source .\vivado\check_jtag_targets.tcl
type .\build\jtag_check\vivado_jtag_targets.txt
```

Expected devices:

```text
xczu1_0
arm_dap_1
```

To open the Vivado GUI directly into Hardware Manager:

```powershell
C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode gui -source .\vivado\open_hw_manager_connected.tcl
```

## Run The JTAG Demo

Keep the UART terminal open, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\run_jtag.ps1
```

The script initializes the PS, programs the PL bitstream, downloads the
bare-metal ELF to Cortex-A53 #0, and starts the program.

Expected UART output begins with:

```text
BNN FCC bare-metal test
Sending 4466 configuration beats
```

The validated demo output ends with:

```text
Passed 100/100 images
Accelerator busy cycles: 443200
PS timer ticks: 0x0000000001B99CBE
```

This proves the board is running the bitstream and bare-metal C++ application:
the PS sends model data and image packets through AXI4-Lite, the wrapper
converts them to BNN streams, and the accelerator returns the predicted class.

## DAP Error Recovery

If XSCT reports a stale DAP error like:

```text
DAP (AXI AP transaction error, DAP status 0x30000021)
```

try:

```powershell
C:\Xilinx\Vitis\2024.2\bin\xsct.bat .\sw\cli\clear_dap_error.tcl
```

Then rerun:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\run_jtag.ps1
```

If the error remains, power-cycle the board:

1. Unplug/replug `J15` USB-C power.
2. Keep `SW2 = ON-ON-ON-ON`.
3. Press `SW7` if needed.
4. Confirm `D23` is on.
5. Run the demo again.

## Optional SD-Card Boot

If JTAG is unavailable and you have a microSD card, build a boot image:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\make_sd_boot.ps1
```

Generated file:

```text
build\sd_boot\BOOT.BIN
```

Copy `BOOT.BIN` to a FAT32 microSD card, set:

```text
SW2 = OFF-ON-OFF-ON
```

Then insert the card, keep UART open at `115200 8N1`, and power-cycle the
board.

## Simulation And Verification

The original simulation flow remains available:

```powershell
make compile
make sim UVM_TESTNAME=bnn_fcc_single_beat_test
make regress
make sim-coverage
make coverage-sweep-report
```

Useful directed tests:

```powershell
make sim-bnn_fcc_tkeep_packet_test
make sim-bnn_fcc_input_tkeep_packet_test
make sim-bnn_fcc_weights_only_reconfig_test
make sim-bnn_fcc_thresh_only_reconfig_test
make sim-bnn_fcc_partial_reconfig_test
make sim-bnn_fcc_delay_gap_profile_test
make sim-bnn_fcc_density_extremes_test
make sim-bnn_fcc_threshold_abs_extremes_test
make sim-bnn_fcc_pixel_values_directed_test
```

## Directory Structure

```text
rtl/                 SystemVerilog accelerator and AXI4-Lite wrapper
vivado/              ZUBoard Vivado project scripts and block-design wrapper
sw/src/              Bare-metal C++ application
sw/cli/              No-GUI build, JTAG run, DAP recovery, and SD boot scripts
verification/        Legacy and UVM testbenches
python/model_data/   Weights and thresholds
python/test_vectors/ Reference inputs and expected outputs
openflex/            Previous timing/resource exploration artifacts
report/              Project report source
```
