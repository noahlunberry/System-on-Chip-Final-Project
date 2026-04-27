# Vivado Build Flow

This folder creates a ZUBoard-1CG Vivado project for the bare-metal BNN FCC
accelerator.

Install the ZUBoard board files into Vivado's user XHub board store:

```sh
vivado -mode batch -source vivado/install_zuboard_board_files.tcl
```

Run from the repository root:

```sh
vivado -mode batch -source vivado/create_zuboard_bnn_project.tcl
```

On Windows, Vivado Tcl can mis-handle a current working directory containing
backslash escape sequences such as `\U`. If Vivado fails during Tcl startup from
this repo path, launch it from another directory and pass the script with
forward slashes:

```sh
vivado -mode batch -source C:/Users/pawin/UF/spring26/SoC-Design/System-on-Chip-Final-Project/vivado/create_zuboard_bnn_project.tcl
```

To run synthesis, implementation, bitstream generation, and export an XSA for
Vitis:

```sh
vivado -mode batch -source vivado/create_zuboard_bnn_project.tcl -tclargs -build_bitstream
```

The Tcl flow maps the accelerator AXI4-Lite slave at `0xA0000000` with a 64 KiB
address range. The Vitis app in `sw/src/main.cpp` can use the generated
`xparameters.h` base-address macro, or you can define:

```c
#define BNN_FCC_BASEADDR 0xA0000000u
```

## Small Accelerator Configuration

The Vivado-facing wrapper is `vivado/hdl/bnn_fcc_vivado_axi_lite_small.v`.
It is plain Verilog so Vivado can use it as a block-design module reference,
while the implementation remains SystemVerilog. The wrapper uses:

| Parameter | Value |
| --- | --- |
| `PARALLEL_INPUTS` | `8` |
| `PARALLEL_NEURONS` | `'{8, 8, 10}` |
| `TOPOLOGY` | `'{784, 256, 256, 10}` |
| Config bus | 64-bit |
| Image bus | 64-bit |

## Board Files

The script targets the ZUBoard-1CG device part `xczu1cg-sbva484-1-e`, matching
the Avnet ZUBoard-1CG device `XCZU1CG-1SBVA484E`. If Vivado has the ZUBoard
board definition installed, the script applies the board preset for PS DDR/MIO.
If not, it still creates a part-only project, but the Zynq PS settings should be
reviewed manually before exporting hardware for Vitis.
