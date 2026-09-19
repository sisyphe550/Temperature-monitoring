#!/usr/bin/env python3
"""Black-box checks that can run on CI without claiming Air sensor coverage."""
import pathlib
import subprocess
import tempfile

binary = pathlib.Path("prototypes/sensor-probe/.build/release/sensor-probe").resolve()
with tempfile.TemporaryDirectory() as directory:
    destination = pathlib.Path(directory) / "must-not-exist"
    help_result = subprocess.run([binary, "--help"], capture_output=True, text=True)
    assert help_result.returncode == 0 and "--intervals" in help_result.stdout
    for args in [["--intervals", "25"], ["--seconds", "0"], ["--seconds"], ["--bad", "x"]]:
        result = subprocess.run([binary, "--output", str(destination), *args], capture_output=True, text=True)
        assert result.returncode == 2, (args, result.returncode, result.stderr)
        assert not destination.exists(), "Invalid CLI request created output"
    sentinel = pathlib.Path(directory) / "keep.txt"
    sentinel.write_text("existing evidence")
    result = subprocess.run([binary, "--output", directory], capture_output=True, text=True)
    assert result.returncode == 2
    assert sentinel.read_text() == "existing evidence"
print("CLI black-box: help, invalid intervals/duration/options, missing value, existing-output protection passed")
