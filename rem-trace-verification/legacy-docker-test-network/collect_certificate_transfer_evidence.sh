#!/usr/bin/env bash
# Populates certificate and batch-transfer evidence files (requires updated chaincode deployed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_peer_common.sh"

mkdir -p "${SCRIPT_DIR}/evidence"

CERT_HASH="aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"
DRONE_BATCH="${DRONE_BATCH:-BATCH_DRONE_001}"
ORE_BATCH="${ORE_BATCH:-BATCH_ORE_001}"

POS_CERT="CERT_EVID_POS_$(date +%s)_$$"
NEG_CERT="CERT_EVID_NEG_$(date +%s)_$$"

pos_out="${SCRIPT_DIR}/evidence/certificate_validation_positive.txt"
neg_out="${SCRIPT_DIR}/evidence/certificate_validation_negative.txt"
xfer_pos="${SCRIPT_DIR}/evidence/batch_transfer_positive.txt"
xfer_neg="${SCRIPT_DIR}/evidence/batch_transfer_negative.txt"

{
  echo "Certificate validation — positive path"
  echo "Commands run from: ${ROOT_DIR}"
  echo ""
  echo "== registerCertificate (VALID, future expiry) =="
} >"${pos_out}"

reg_pos='{"function":"registerCertificate","Args":["'"${DRONE_BATCH}"'","'"${POS_CERT}"'","PURITY_LAB_REPORT","AccreditedLabEU","2024-06-01T00:00:00.000Z","2030-06-01T00:00:00.000Z","'"${CERT_HASH}"'","VALID"]}'
set +e
out_reg=$(peer_invoke_both_orgs "${reg_pos}" 2>&1)
rc_reg=$?
set -e
{
  echo "${out_reg}"
  echo "exit_code: ${rc_reg}"
  echo ""
  echo "== verifyCertificate (query) =="
} >>"${pos_out}"

set +e
out_ver=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace \
  -c '{"Args":["verifyCertificate","'"${DRONE_BATCH}"'","'"${POS_CERT}"'"]}' 2>&1)
rc_ver=$?
set -e
{
  echo "${out_ver}"
  echo "exit_code: ${rc_ver}"
} >>"${pos_out}"

{
  echo "Certificate validation — negative path (REVOKED metadata)"
  echo ""
  echo "== registerCertificate (REVOKED) =="
} >"${neg_out}"

reg_neg='{"function":"registerCertificate","Args":["'"${DRONE_BATCH}"'","'"${NEG_CERT}"'","EXPORT_LICENSE","GovCA","2024-01-01T00:00:00.000Z","2032-01-01T00:00:00.000Z","'"${CERT_HASH}"'","REVOKED"]}'
set +e
out_rn=$(peer_invoke_both_orgs "${reg_neg}" 2>&1)
rc_rn=$?
set -e
{
  echo "${out_rn}"
  echo "exit_code: ${rc_rn}"
  echo ""
  echo "== verifyCertificate (query, expect isValid false) =="
} >>"${neg_out}"

set +e
out_nv=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace \
  -c '{"Args":["verifyCertificate","'"${DRONE_BATCH}"'","'"${NEG_CERT}"'"]}' 2>&1)
rc_nv=$?
set -e
{
  echo "${out_nv}"
  echo "exit_code: ${rc_nv}"
} >>"${neg_out}"

{
  echo "Batch transfer — positive path (toggle ore batch custodian for idempotent re-runs)"
  echo "Target batch: ${ORE_BATCH}"
  echo ""
  echo "== queryBatch (before) =="
} >"${xfer_pos}"

set +e
before=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["queryBatch","'"${ORE_BATCH}"'"]}' 2>&1)
rc_b=$?
set -e
{
  echo "${before}"
  echo "exit_code: ${rc_b}"
} >>"${xfer_pos}"

owner_to=$(echo "${before}" | python3 -c "import sys,json
raw=sys.stdin.read()
try:
    b=json.loads(raw)
    o=b.get('owner','')
    print('MineOrgLogistics' if o=='MineOrg' else 'MineOrg')
except Exception:
    print('MineOrgLogistics')")

{
  echo ""
  echo "== transferBatch -> ${owner_to} =="
} >>"${xfer_pos}"

xfer='{"function":"transferBatch","Args":["'"${ORE_BATCH}"'","'"${owner_to}"'"]}'
set +e
out_x=$(peer_invoke_both_orgs "${xfer}" 2>&1)
rc_x=$?
set -e
{
  echo "${out_x}"
  echo "exit_code: ${rc_x}"
  echo ""
  echo "== queryBatch (after) =="
} >>"${xfer_pos}"

set +e
after=$("${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["queryBatch","'"${ORE_BATCH}"'"]}' 2>&1)
rc_a=$?
set -e
{
  echo "${after}"
  echo "exit_code: ${rc_a}"
} >>"${xfer_pos}"

{
  echo "Batch transfer — negative path (empty newOwner)"
  echo ""
} >"${xfer_neg}"

xfer_bad='{"function":"transferBatch","Args":["'"${ORE_BATCH}"'",""]}'
set +e
out_bad=$(peer_invoke_both_orgs "${xfer_bad}" 2>&1)
rc_bad=$?
set -e
{
  echo "${out_bad}"
  echo "exit_code: ${rc_bad}"
} >>"${xfer_neg}"

echo "Evidence written:"
echo "  ${pos_out}"
echo "  ${neg_out}"
echo "  ${xfer_pos}"
echo "  ${xfer_neg}"
