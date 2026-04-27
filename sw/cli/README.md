# No-GUI BNN Demo Flow

This directory builds and runs the ZUBoard BNN bare-metal demo without opening
the Vitis GUI.

The scripts still use AMD command-line tools from Vitis 2024.2:

- `xsct.bat` for project/app build, JTAG programming, and ELF download.

## Hardware Connections

Connect:

- USB-C 15 V / 45 W power supply to ZUBoard connector `J15`.
- micro-USB cable from the PC to ZUBoard `J16` for onboard JTAG/UART.

Open a serial terminal on the FTDI USB serial port at `115200 8N1`.

On Windows, this can help find the COM port:

```powershell
Get-CimInstance Win32_SerialPort |
    Where-Object { $_.Name -match "USB|FTDI|UART|Serial" } |
    Select-Object DeviceID,Name
```

## Build Hardware

If the Vivado bitstream/XSA are not already built:

```powershell
vivado -mode batch -source C:/Users/pawin/UF/spring26/SoC-Design/System-on-Chip-Final-Project/vivado/create_zuboard_bnn_project.tcl -tclargs -build_bitstream -jobs 4
```

Expected files:

- `build/vivado/zuboard_bnn_fcc/zuboard_bnn_fcc.xsa`
- `build/vivado/zuboard_bnn_fcc/zuboard_bnn_fcc.runs/impl_1/zuboard_bnn_fcc_bd_wrapper.bit`

## Build Software

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\build_app.ps1
```

The generated ELF is placed under:

```text
build/vitis_cli
```

## Program and Run

With the board powered and `J16` connected:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\run_jtag.ps1
```

Watch the serial terminal. A successful demo prints lines like:

```text
BNN FCC bare-metal test
Sending <N> configuration beats
image 0: pred=<digit> expected=<digit> PASS
...
Passed <N>/<N> images
Accelerator busy cycles: <nonzero>
```

## SD Card Demo Without JTAG

If `hw_server` cannot see the JTAG chain, use microSD boot instead. This still
demonstrates the same hardware design on the ZUBoard: FSBL configures the PS,
loads the PL bitstream, and starts the bare-metal BNN demo ELF.

Build the boot image:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\make_sd_boot.ps1
```

The generated boot image is:

```text
build\sd_boot\BOOT.BIN
```

Copy `BOOT.BIN` to a FAT32-formatted microSD card. You can also let the script
copy it by passing the SD card drive letter:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\make_sd_boot.ps1 -SdDrive E:
```

Set the ZUBoard boot DIP switch `SW2` for SD boot:

```text
SW2 = OFF-ON-OFF-ON
```

Insert the microSD card, keep `J15` power connected, keep `J16` connected for
UART, and open the serial terminal on the USB serial port at `115200 8N1`.
Power-cycle the board. The same `BNN FCC bare-metal test` output should print
over UART.

## Overrides

Use these if your install or generated files are in different locations:

```powershell
powershell -ExecutionPolicy Bypass -File .\sw\cli\build_app.ps1 `
    -VitisRoot C:\Xilinx\Vitis\2024.2 `
    -Xsa C:\path\to\zuboard_bnn_fcc.xsa `
    -Workspace C:\path\to\vitis_cli_workspace

powershell -ExecutionPolicy Bypass -File .\sw\cli\run_jtag.ps1 `
    -VitisRoot C:\Xilinx\Vitis\2024.2 `
    -Bit C:\path\to\zuboard_bnn_fcc_bd_wrapper.bit `
    -Elf C:\path\to\bnn_fcc_demo.elf `
    -PsuInit C:\path\to\psu_init.tcl

powershell -ExecutionPolicy Bypass -File .\sw\cli\make_sd_boot.ps1 `
    -VitisRoot C:\Xilinx\Vitis\2024.2 `
    -Bit C:\path\to\zuboard_bnn_fcc_bd_wrapper.bit `
    -Elf C:\path\to\bnn_fcc_demo.elf `
    -Fsbl C:\path\to\fsbl.elf `
    -Pmufw C:\path\to\pmufw.elf `
    -OutputDir C:\path\to\sd_boot
```
