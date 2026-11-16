#!/usr/bin/env bash
# Shared Fabric peer CLI environment for rem-trace-verification scripts.
# shellcheck source=/dev/null

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export FABRIC_CFG_PATH="${ROOT_DIR}/config"
export PATH="${ROOT_DIR}/bin:${PATH}"
export CORE_PEER_TLS_ENABLED=true
export CORE_PEER_LOCALMSPID="Org1MSP"
export CORE_PEER_TLS_ROOTCERT_FILE="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export CORE_PEER_MSPCONFIGPATH="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
export CORE_PEER_ADDRESS=localhost:7051

export PEER_BIN="${ROOT_DIR}/bin/peer"
export ORDERER_CA="${ROOT_DIR}/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem"
export ORG1_CA="${ROOT_DIR}/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
export ORG2_CA="${ROOT_DIR}/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

peer_invoke_both_orgs() {
  local payload="$1"
  "${PEER_BIN}" chaincode invoke -o localhost:7050 --ordererTLSHostnameOverride orderer.example.com \
    --tls --cafile "${ORDERER_CA}" -C mychannel -n remtrace \
    --peerAddresses localhost:7051 --tlsRootCertFiles "${ORG1_CA}" \
    --peerAddresses localhost:9051 --tlsRootCertFiles "${ORG2_CA}" \
    -c "${payload}"
}
