#!/usr/bin/env sh

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1

openflex bnn_fcc_verify.yml > run.log 2>&1 || true

python - <<'PY'
from pathlib import Path

log_path = Path("run.log")
text = log_path.read_text(errors="ignore") if log_path.exists() else ""
lower = text.lower()

failed_tokens = ("error:", "fatal:", "failure:", "traceback")
passed = "SUCCESS:" in text
failed = any(token in lower for token in failed_tokens)

if passed and not failed:
    print("Verification PASSED")
else:
    print("Verification FAILED (see run.log)")
PY
