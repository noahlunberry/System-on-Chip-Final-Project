# Openflex 

We are using the openflex tool to collect timing and area results, in addition to performing the final verification tests for the contest.

## Installation and Initialization Instructions

[To install openflex follow the instructions here](https://github.com/wespiard/openflex). However, I'd recommend the following changes to install it into ~/envs/openflex:

```bash
python -m venv ~/envs/openflex
source ~envs/openflex/bin/activate
pip install -U pip        
pip install openflex     
```

When logging back into your account after installing, you can reactivate the openflex environment with:

```bash
source ~envs/openflex/bin/activate
```

To deactivate at any time:

```bash
deactivate
```

## Collecting Timing and Area Results

Openflex uses a YAML file to specify the details of the project. I have provided the [bnn_fcc_timing.yml YAML file](bnn_fcc_timing.yml) for collecting timing and area results.
However, to use it you must first modify the file to specify all of your source files.

For out-of-context timing analysis, it is usually a good idea to ensure that the I/O is registered. I provide this for you in [rtl/bnn_fcc_timing.sv](rtl/bnn_fcc_timing.sv), which will be the top-level module for synthesis when collecting results.

IMPORTANT: modify the implementation-specific default parameter values in [rtl/bnn_fcc_timing.sv](rtl/bnn_fcc_timing.sv). All other parameter values are specified by the the YAML file.

Run openflex to collecting timing results with the following:

```bash
openflex bnn_fcc_timing.yml -c bnn_fcc.csv
```

This command will create a Vivado project, execute Vivado to synthesize, place, and route your design, and will then report maximum clock frequency and area numbers in bnn_fcc.csv.
You can see an example in [example.csv](example.csv).

If you get errors when running openflex here, make sure that Vivado is in your PATH, that the YAML file contains all required source files, and that openflex is activated.

## Recovering A Failed Route On Windows

If Vivado crashes during router physical synthesis but `build_vivado/outputs/post_place.dcp` exists, you can finish the run and still generate the normal OpenFlex CSV row with:

```powershell
.\resume_openflex_route.ps1 -Csv final6.csv
```

This helper:

- copies [route_from_post_place_openflex_finish.tcl](route_from_post_place_openflex_finish.tcl) into `build_vivado`
- reruns routing from `post_place.dcp` with `route_design -no_psir`
- regenerates the standard OpenFlex outputs such as `post_route_timing_summary.rpt`, `route_paths.rpt`, `route_vios.rpt`, and `vivado_report.txt`
- appends the CSV row using OpenFlex's own `process_vivado_results()` logic

You can override the defaults if needed:

```powershell
.\resume_openflex_route.ps1 -Yaml bnn_fcc_timing.yml -Csv bnn_fcc.csv -DriveLetter Y:
```

This script assumes the OpenFlex Python environment is active, or that `python.exe` from the OpenFlex install is available at `~/envs/openflex/Scripts/python.exe`.

## Verification

For verifying your final design, update the [bnn_fcc_verification.yml](bnn_fcc_verification.yml) file with your design sources like before. You do not need bnn_fcc_timing.sv here.

You could potentially verify your design like this:

```bash
openflex bnn_fcc_verify.yml
```

But, this requires you to manually scan the output and verify correctness. I've automated that with the simple bash script [verify.sh](verify.sh). To run it, simply do:

```bash
./verify.sh
```

If it doesn't run, first try:

```bash
chmod +x verify.sh
```

If your simulation is successful, it will report:

```bash
Verification PASSED
```

If your simulation fails, it will report:

```bash
Verification FAILED (see run.log)
```

where run.log contains the output from the simulation.






