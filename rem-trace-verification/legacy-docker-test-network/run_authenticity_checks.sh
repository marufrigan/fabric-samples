#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/rem-trace-verification/evidence"

mkdir -p "${OUT_DIR}"

cd "${ROOT_DIR}"

git status > "${OUT_DIR}/git_status.txt"
git diff -- rem-trace-chaincode > "${OUT_DIR}/git_diff_rem_trace_chaincode.patch"

export FABRIC_CFG_PATH="${ROOT_DIR}/config"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

PEER_BIN="${ROOT_DIR}/bin/peer"
ORDERER_CA="${ROOT_DIR}/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
ORG1_CA="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_CA="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

"${PEER_BIN}" lifecycle chaincode queryinstalled > "${OUT_DIR}/queryinstalled_org1.txt"
"${PEER_BIN}" lifecycle chaincode querycommitted --channelID mychannel --name remtrace > "${OUT_DIR}/querycommitted_remtrace.txt"

"${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["queryBatch","BATCH_DRONE_001"]}' > "${OUT_DIR}/query_batch_drone.txt"
"${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["getBatchHistory","BATCH_DRONE_001"]}' > "${OUT_DIR}/query_history_drone.txt"
"${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["verifyCompliance","BATCH_DRONE_001"]}' > "${OUT_DIR}/query_compliance_drone.txt"
"${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["traceToOrigin","BATCH_DRONE_001"]}' > "${OUT_DIR}/query_trace_origin_drone.txt"
"${PEER_BIN}" chaincode query -C mychannel -n remtrace -c '{"Args":["verifyFullLineageCompliance","BATCH_DRONE_001"]}' > "${OUT_DIR}/query_full_lineage_drone.txt"

"${PEER_BIN}" chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" -C mychannel -n remtrace \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${ORG1_CA}" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "${ORG2_CA}" \
  -c '{"function":"registerBatch","Args":["BATCH_ORE_001","","MineCorp","ore","Australia","QmOreDocHash123","true"]}' \
  > "${OUT_DIR}/negative_duplicate_batch.txt" 2>&1 || true

"${PEER_BIN}" chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" -C mychannel -n remtrace \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${ORG1_CA}" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "${ORG2_CA}" \
  -c '{"function":"registerBatch","Args":["BATCH_BAD_MATERIAL","","MineCorp","badtype","Australia","QmHash","true"]}' \
  > "${OUT_DIR}/negative_invalid_material.txt" 2>&1 || true

"${PEER_BIN}" chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
  --tls --cafile "${ORDERER_CA}" -C mychannel -n remtrace \
  --peerAddresses localhost:7051 --tlsRootCertFiles "${ORG1_CA}" \
  --peerAddresses localhost:9051 --tlsRootCertFiles "${ORG2_CA}" \
  -c '{"function":"registerBatch","Args":["BATCH_BAD_PARENT","NOT_EXISTING_PARENT","RefineCorp","refined","Japan","QmHash","true"]}' \
  > "${OUT_DIR}/negative_missing_parent.txt" 2>&1 || true

echo "Verification complete. Evidence saved in: ${OUT_DIR}"
