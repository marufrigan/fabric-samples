#!/usr/bin/env bash
# Measures actual query/invoke latency against the local Fabric test network.
# Does not assert any TPS target; results are environment-specific.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_peer_common.sh"

OUT="${SCRIPT_DIR}/evidence/performance_results.txt"
mkdir -p "${SCRIPT_DIR}/evidence"

NUM_QUERIES="${NUM_QUERIES:-25}"
NUM_INVOKES="${NUM_INVOKES:-5}"
BATCH_ID="${BATCH_ID:-BATCH_DRONE_001}"
CERT_HASH="aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

QUERY_SPEC='{"Args":["queryBatch","'"${BATCH_ID}"'"]}'

q_success=0
q_fail=0
q_total_ms=0

i_success=0
i_fail=0
i_total_ms=0

: >"${OUT}.log"

start_all=$(python3 -c 'import time; print(time.perf_counter())')

run_query() {
  local t0 t1 elapsed_ms rc out
  t0=$(python3 -c 'import time; print(time.perf_counter())')
  set +e
  out=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace -c "${QUERY_SPEC}" 2>&1)
  rc=$?
  set -e
  t1=$(python3 -c 'import time; print(time.perf_counter())')
  elapsed_ms=$(python3 -c "print(int((${t1} - ${t0}) * 1000))")
  if [[ "${rc}" -eq 0 ]]; then
    q_success=$((q_success + 1))
    q_total_ms=$((q_total_ms + elapsed_ms))
  else
    q_fail=$((q_fail + 1))
    echo "QUERY_FAIL rc=${rc} ms=${elapsed_ms} out=${out}" >>"${OUT}.log"
  fi
}

run_invoke() {
  local cert_id="$1"
  local payload
  payload='{"function":"registerCertificate","Args":["'"${BATCH_ID}"'","'"${cert_id}"'","EXPORT_LICENSE","RegulatorCA","2024-01-01T00:00:00.000Z","2035-12-31T23:59:59.000Z","'"${CERT_HASH}"'","VALID"]}'
  local t0 t1 elapsed_ms rc out
  t0=$(python3 -c 'import time; print(time.perf_counter())')
  set +e
  out=$(peer_invoke_both_orgs "${payload}" 2>&1)
  rc=$?
  set -e
  t1=$(python3 -c 'import time; print(time.perf_counter())')
  elapsed_ms=$(python3 -c "print(int((${t1} - ${t0}) * 1000))")
  if [[ "${rc}" -eq 0 ]]; then
    i_success=$((i_success + 1))
    i_total_ms=$((i_total_ms + elapsed_ms))
  else
    i_fail=$((i_fail + 1))
    echo "INVOKE_FAIL rc=${rc} ms=${elapsed_ms} cert=${cert_id} out=${out}" >>"${OUT}.log"
  fi
}

{
  echo "REM trace performance measurement (local test network)"
  echo "Timestamp (UTC): $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "FABRIC_ROOT: ${ROOT_DIR}"
  echo "Batch for queries: ${BATCH_ID}"
  echo "Planned queries: ${NUM_QUERIES}"
  echo "Planned invokes: ${NUM_INVOKES} (registerCertificate, Org1MSP)"
  echo ""
} >"${OUT}"

for ((n = 1; n <= NUM_QUERIES; n++)); do
  run_query
done

for ((n = 1; n <= NUM_INVOKES; n++)); do
  run_invoke "CERT_PERF_$(date +%s)_${n}_$$"
done

end_all=$(python3 -c 'import time; print(time.perf_counter())')
duration_ms=$(python3 -c "print(int((${end_all} - ${start_all}) * 1000))")

avg_q=0
if [[ "${q_success}" -gt 0 ]]; then
  avg_q=$(python3 -c "print(int(${q_total_ms} / ${q_success}))")
fi

avg_i=0
if [[ "${i_success}" -gt 0 ]]; then
  avg_i=$(python3 -c "print(int(${i_total_ms} / ${i_success}))")
fi

{
  echo "--- Results ---"
  echo "successful_query_operations: ${q_success}"
  echo "failed_query_operations: ${q_fail}"
  echo "average_query_latency_ms: ${avg_q}"
  echo "successful_invoke_operations: ${i_success}"
  echo "failed_invoke_operations: ${i_fail}"
  echo "average_invoke_latency_ms: ${avg_i}"
  echo "total_test_duration_ms: ${duration_ms}"
  echo ""
  echo "Notes:"
  echo "- Latencies include peer CLI startup and local Docker I/O; they are not bare chaincode-only timings."
  echo "- Invokes use registerCertificate (requires updated remtrace chaincode deployed)."
  echo "- See performance_results.txt.log for per-failure stderr."
} >>"${OUT}"

echo "Wrote ${OUT}"
