#!/usr/bin/env bash
# run_all.sh (robust)
# Run unit tests, optional fuzz tests, trimmed benchmark, and perf comparison.
set -euo pipefail

PYTHON=${PYTHON:-python3}
PIP=${PIP:-pip}

BASELINE_FILE="perf/baseline_perf.json"
OUT_FILE="perf/out.json"
DELTA=0.15   # 15% allowed regression
TIMEOUT_FUZZ=${TIMEOUT_FUZZ:-600}  # seconds timeout for fuzz pytest (overall)

echo "=== Environment ==="
echo "Python: $($PYTHON --version 2>&1)"
echo "Pip: $($PIP --version 2>&1)"
echo "SKIP_FUZZ: ${SKIP_FUZZ:-0}"
echo "Baseline: $BASELINE_FILE"
echo

mkdir -p perf

echo "Installing pytest if missing..."
$PIP install --quiet pytest >/dev/null 2>&1 || true

echo
echo "=== Running unit tests ==="
if ! $PYTHON -m pytest -q tests/test_dispatcher_unit.py::test_T1_T2_trace_equivalence -q; then
  echo "Unit smoke test failed."
  exit 1
fi

if ! $PYTHON -m pytest -q tests/test_dispatcher_unit.py -q; then
  echo "Unit tests failed."
  exit 1
fi
echo "Unit tests passed."

if [ "${SKIP_FUZZ:-0}" = "1" ]; then
  echo
  echo "=== Skipping fuzz tests (SKIP_FUZZ=1) ==="
else
  echo
  echo "=== Running fuzz tests (this may take a while) ==="
  if command -v timeout >/dev/null 2>&1; then
    if ! timeout "${TIMEOUT_FUZZ}" $PYTHON -m pytest -q tests/test_dispatcher_fuzz.py -q; then
      echo "Fuzz tests failed or timed out."
      exit 1
    fi
  else
    if ! $PYTHON -m pytest -q tests/test_dispatcher_fuzz.py -q; then
      echo "Fuzz tests failed."
      exit 1
    fi
  fi
  echo "Fuzz tests passed."
fi

echo
echo "=== Running trimmed benchmark (tools/benchmark_trimmed.py) ==="
if [ ! -f tools/benchmark_trimmed.py ]; then
  echo "ERROR: tools/benchmark_trimmed.py not found."
  exit 1
fi

# Ensure repo root is on PYTHONPATH so local module ee.py can be imported
export PYTHONPATH="${PYTHONPATH:-}:$(pwd)"
# Run benchmark and capture JSON
$PYTHON tools/benchmark_trimmed.py > "$OUT_FILE" 2>&1 || true
echo "Benchmark output saved to $OUT_FILE"
echo "---- perf/out.json ----"
sed -n '1,200p' "$OUT_FILE" || true
echo "-----------------------"

# Parse median_time_s robustly (use jq if available, else Python)
median=""
if command -v jq >/dev/null 2>&1; then
  median=$(jq -r '.median_time_s // empty' "$OUT_FILE" 2>/dev/null || true)
fi

if [ -z "$median" ]; then
  # fallback to Python parsing
  median=$($PYTHON - <<PY
import json,sys
p="$OUT_FILE"
try:
    with open(p) as f:
        j=json.load(f)
    m=j.get("median_time_s")
    if m is None:
        sys.exit(2)
    print(m)
except Exception as e:
    # print nothing and exit non-zero
    sys.exit(2)
PY
) || true
fi

if [ -z "$median" ]; then
  echo "ERROR: Could not parse median_time_s from $OUT_FILE"
  echo "Please inspect $OUT_FILE for errors (traceback or invalid JSON)."
  exit 2
fi

echo
echo "=== Comparing benchmark to baseline ==="
echo "Current median_time_s: $median"

if [ ! -f "$BASELINE_FILE" ] || [ "$(wc -c < "$BASELINE_FILE" || echo 0)" -eq 0 ]; then
  echo "Baseline missing or empty. Creating baseline at $BASELINE_FILE with median_time_s=$median"
  mkdir -p "$(dirname "$BASELINE_FILE")"
  $PYTHON - <<PY > "$BASELINE_FILE"
import json
print(json.dumps({"median_time_s": float($median)}))
PY
  echo "Baseline created. Exiting OK."
  exit 0
fi

base_median=$($PYTHON - <<PY
import json,sys
p="$BASELINE_FILE"
try:
    with open(p) as f:
        j=json.load(f)
    m=j.get("median_time_s")
    if m is None:
        sys.exit(2)
    print(m)
except Exception as e:
    sys.exit(2)
PY
) || true

if [ -z "$base_median" ]; then
  echo "ERROR: Could not read median_time_s from baseline $BASELINE_FILE"
  exit 2
fi

threshold=$($PYTHON - <<PY
base=float($base_median)
delta=float($DELTA)
print(base*(1.0+delta))
PY
)

echo "Baseline median: $base_median"
echo "Threshold (base * (1 + ${DELTA})): $threshold"

cmp=$($PYTHON - <<PY
base=float($base_median)
median=float($median)
threshold=base*(1.0+$DELTA)
if median > threshold:
    print("regress")
else:
    print("ok")
PY
)

if [ "$cmp" = "regress" ]; then
  echo "PERFORMANCE REGRESSION: median ($median) > threshold ($threshold)"
  exit 2
fi

echo "Performance within threshold."
echo "All checks passed."
exit 0
