#!/usr/bin/env bash
# Basic local failure / recovery observation for the Fabric test network.
# Does not claim production availability or SLA.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_peer_common.sh"

OUT="${SCRIPT_DIR}/evidence/availability_test_results.txt"
PEER_CONTAINER="${PEER_CONTAINER:-peer0.org1.example.com}"
QUERY_SPEC='{"Args":["queryBatch","BATCH_DRONE_001"]}'
mkdir -p "${SCRIPT_DIR}/evidence"

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"
}

{
  log "REM trace availability probe (local Docker test network)"
  log "FABRIC_ROOT=${ROOT_DIR}"
  log "Target peer container: ${PEER_CONTAINER}"
  echo ""
} | tee "${OUT}"

run_query_step() {
  local label="$1"
  {
    echo "--- ${label} ---"
    set +e
    out=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace -c "${QUERY_SPEC}" 2>&1)
    rc=$?
    set -e
    echo "exit_code: ${rc}"
    echo "stdout/stderr (truncated to 800 chars):"
    echo "${out}" | head -c 800
    echo ""
    echo ""
  } | tee -a "${OUT}"
}

run_query_step "1) Query with both peers up (Org1 CLI -> peer0.org1)"

if ! docker info >/dev/null 2>&1; then
  {
    echo "Docker not available; skipping stop/start steps."
    echo "Run this script on a host with Docker and an up test network."
  } | tee -a "${OUT}"
  exit 0
fi

log "Stopping ${PEER_CONTAINER}..."
docker stop "${PEER_CONTAINER}" >>"${OUT}" 2>&1 || true

run_query_step "2) Query after stopping Org1 peer container (expected failure or endorsement error)"

log "Starting ${PEER_CONTAINER}..."
docker start "${PEER_CONTAINER}" >>"${OUT}" 2>&1 || true

log "Waiting for peer process (15s)..."
sleep 15

run_query_step "3) Query after peer restart (expected success once peer is ready)"

{
  echo ""
  echo "Summary:"
  echo "- This script documents a single-machine Docker behaviour, not cloud HA."
  echo "- Queries in this prototype use the Org1 peer CLI target; stopping peer0.org1 breaks that path."
  echo "- Ordering service (orderer) was left running; only one peer was cycled."
} | tee -a "${OUT}"

echo "Wrote ${OUT}"
