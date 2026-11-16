#!/usr/bin/env bash
# Runs the full REM traceability test sequence against the running network and
# writes one transcript (command + raw output) per test under evidence/.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${HERE}/../test-network-nano-bash/env.sh"
export FABRIC_LOGGING_SPEC=INFO
EV="${HERE}/evidence"; OFF="${HERE}/offchain"; mkdir -p "$EV" "$OFF"
PEERS='--peerAddresses 127.0.0.1:7051 --tlsRootCertFiles $ORG1_CA --peerAddresses 127.0.0.1:7055 --tlsRootCertFiles $ORG2_CA'
INV='peer chaincode invoke -o 127.0.0.1:6050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA -C mychannel -n remtrace '"$PEERS"' --waitForEvent -c'
QRY='peer chaincode query -C mychannel -n remtrace -c'
ev() {   # ev <file> <org> <command string>
  local f="$EV/$1" org="$2"; shift 2
  $org
  local who=admin; case "$CORE_PEER_MSPCONFIGPATH" in *User1@*) who=User1;; esac
  { echo "# identity: ${CORE_PEER_LOCALMSPID} ${who}"; echo "\$ $*"; eval "$*" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g; s/^[0-9-]+ [0-9:.]+ [A-Z]+ [0-9a-f]+ (INFO|WARN|ERRO) //'; echo; } >> "$f"
}

# ---- off-chain sample evidence documents, anchored by SHA-256
for s in ORE REF MAG MOTOR DRONE; do
  printf 'SAMPLE EVIDENCE DOCUMENT (research prototype, not a real certificate)\nBatch: BATCH_%s_001\nDocument type: origin and processing declaration\n' "$s" > "$OFF/BATCH_${s}_001_evidence.txt"
done
h() { sha256sum "$OFF/BATCH_$1_001_evidence.txt" | cut -d' ' -f1; }

# ---- 01 lifecycle
ev 01_lifecycle.txt org1 'peer lifecycle chaincode queryinstalled'
ev 01_lifecycle.txt org1 'peer lifecycle chaincode querycommitted --channelID mychannel --name remtrace'

# ---- 02 governance: regulator role is ledger state, set once at deployment
ev 02_governance.txt org1 "$INV"' '"'"'{"function":"setGovernancePolicy","Args":["RegulatorMSP"]}'"'"
ev 02_governance.txt org1 "$QRY"' '"'"'{"Args":["getGovernancePolicy"]}'"'"
ev 02_governance.txt org1 "$INV"' '"'"'{"function":"setGovernancePolicy","Args":["Org1MSP"]}'"'"                                   # non-regulator tries to take the role
ev 02_governance.txt org1 "$INV"' '"'"'{"function":"setRestrictedCountriesPolicy","Args":["[\"NOWHERE\"]"]}'"'"                 # non-regulator organisation
ev 02_governance.txt regulatoruser "$INV"' '"'"'{"function":"setRestrictedCountriesPolicy","Args":["[\"NOWHERE\"]"]}'"'"       # regulator member without admin role

# ---- 02 policies
ev 02_policies.txt regulator "$INV"' '"'"'{"function":"setMaterialRegistrationPolicy","Args":["{\"ore\":{\"mspId\":\"Org1MSP\",\"owner\":\"MineOrg\"},\"refined\":{\"mspId\":\"Org1MSP\",\"owner\":\"RefineryOrg\"},\"magnet\":{\"mspId\":\"Org1MSP\",\"owner\":\"MagnetFactoryOrg\"},\"motor\":{\"mspId\":\"Org2MSP\",\"owner\":\"MotorFactoryOrg\"},\"drone\":{\"mspId\":\"Org2MSP\",\"owner\":\"DroneFactoryOrg\"}}"]}'"'"
ev 02_policies.txt regulator "$INV"' '"'"'{"function":"setRestrictedCountriesPolicy","Args":["[\"BANNEDSTATE\",\"RESTRICTEDLAND\"]"]}'"'"

# ---- 03 registration of the five-stage lineage
reg() { ev "$1" "$2" "$INV"' '"'"'{"function":"registerBatch","Args":["'"$3"'","'"$4"'","'"$5"'","'"$6"'","'"$7"'","'"$8"'","'"$9"'"]}'"'"; }
reg 03_register_lineage.txt org1 BATCH_ORE_001 "" MineOrg ore Australia "$(h ORE)" true
reg 03_register_lineage.txt org1 BATCH_REF_001 BATCH_ORE_001 RefineryOrg refined Japan "$(h REF)" true
reg 03_register_lineage.txt org1 BATCH_MAG_001 BATCH_REF_001 MagnetFactoryOrg magnet Germany "$(h MAG)" true
reg 03_register_lineage.txt org2 BATCH_MOTOR_001 BATCH_MAG_001 MotorFactoryOrg motor "South Korea" "$(h MOTOR)" true
reg 03_register_lineage.txt org2 BATCH_DRONE_001 BATCH_MOTOR_001 DroneFactoryOrg drone USA "$(h DRONE)" true

# ---- 04 queries
q() { ev "$1" "$2" "$QRY"' '"'"'{"Args":["'"$3"'","'"$4"'"'"${5:+,\"$5\"}"']}'"'"; }
q 04_query_batch.txt org2 queryBatch BATCH_DRONE_001
q 05_trace_to_origin.txt org2 traceToOrigin BATCH_DRONE_001
q 06_compliance.txt org2 verifyCompliance BATCH_DRONE_001
q 06_compliance.txt org2 verifyFullLineageCompliance BATCH_DRONE_001
q 07_history_before_transfer.txt org2 getBatchHistory BATCH_DRONE_001

# ---- 08 negative tests (all must be rejected)
reg 08_negative.txt org1 BATCH_ORE_001 "" MineOrg ore Australia "$(h ORE)" true                     # duplicate
reg 08_negative.txt org1 BATCH_BAD_MATERIAL "" MineOrg badtype Australia "$(h ORE)" true            # invalid material type
reg 08_negative.txt org1 BATCH_BAD_OWNER BATCH_ORE_001 RefineCorp refined Japan "$(h REF)" true     # owner / policy mismatch
reg 08_negative.txt org2 BATCH_BAD_MSP "" MineOrg ore Australia "$(h ORE)" true                     # unauthorised MSP
reg 08_negative.txt org1 BATCH_BAD_PARENT NOT_EXISTING_PARENT RefineryOrg refined Japan "$(h REF)" true   # missing parent
reg 08_negative.txt org2 BATCH_BAD_STAGE BATCH_ORE_001 DroneFactoryOrg drone USA "$(h DRONE)" true  # invalid stage transition
reg 08_negative.txt org1 BATCH_NO_PARENT "" RefineryOrg refined Japan "$(h REF)" true               # non-ore without parent
reg 08_negative.txt org1 BATCH_BAD_HASH "" MineOrg ore Australia not-a-hash true                    # invalid evidence hash

# ---- 09 restricted-origin fraud scenario: second lineage with ore from a restricted country
reg 09_restricted_lineage.txt org1 BATCH_ORE_002 "" MineOrg ore Restrictedland "$(h ORE)" true
reg 09_restricted_lineage.txt org1 BATCH_REF_002 BATCH_ORE_002 RefineryOrg refined Japan "$(h REF)" true
reg 09_restricted_lineage.txt org1 BATCH_MAG_002 BATCH_REF_002 MagnetFactoryOrg magnet Germany "$(h MAG)" true
reg 09_restricted_lineage.txt org2 BATCH_MOTOR_002 BATCH_MAG_002 MotorFactoryOrg motor "South Korea" "$(h MOTOR)" true
reg 09_restricted_lineage.txt org2 BATCH_DRONE_002 BATCH_MOTOR_002 DroneFactoryOrg drone USA "$(h DRONE)" true
q 10_restricted_compliance.txt org2 verifyCompliance BATCH_DRONE_002
q 10_restricted_compliance.txt org2 verifyCompliance BATCH_ORE_002
q 10_restricted_compliance.txt org2 verifyFullLineageCompliance BATCH_DRONE_002

# ---- 11 certificate metadata
CH=$(printf 'SAMPLE EXPORT LICENCE (research prototype)\nBatch: BATCH_DRONE_001\n' | tee "$OFF/CERT_DRONE_001.txt" | sha256sum | cut -d' ' -f1)
cert() { ev "$1" "$2" "$INV"' '"'"'{"function":"registerCertificate","Args":["'"$3"'","'"$4"'","EXPORT_LICENCE","RegulatorCA","2026-01-01T00:00:00.000Z","'"$5"'","'"$CH"'","'"$6"'"]}'"'"; }
cert 11_certificate.txt regulator BATCH_DRONE_001 CERT_DRONE_001 2030-12-31T23:59:59.000Z VALID
q 11_certificate.txt org2 verifyCertificate BATCH_DRONE_001 CERT_DRONE_001
cert 12_certificate_negative.txt org2 BATCH_DRONE_001 CERT_DRONE_002 2030-12-31T23:59:59.000Z VALID     # non-regulator MSP
cert 12_certificate_negative.txt regulator BATCH_DRONE_001 CERT_DRONE_001 2030-12-31T23:59:59.000Z VALID     # duplicate certificate
cert 12_certificate_negative.txt regulator BATCH_DRONE_001 CERT_DRONE_REVOKED 2030-12-31T23:59:59.000Z REVOKED
q 12_certificate_negative.txt org2 verifyCertificate BATCH_DRONE_001 CERT_DRONE_REVOKED
cert 12_certificate_negative.txt regulator BATCH_DRONE_001 CERT_DRONE_EXPIRED 2026-06-30T23:59:59.000Z VALID
q 12_certificate_negative.txt org2 verifyCertificate BATCH_DRONE_001 CERT_DRONE_EXPIRED
q 12_certificate_negative.txt org2 verifyCertificate BATCH_DRONE_001 CERT_UNKNOWN

# ---- 13 custody transfer: two-step, bound to the identity that holds custody
tr() { ev 13_transfer.txt "$1" "$INV"' '"'"'{"function":"transferBatch","Args":["BATCH_DRONE_001","'"$2"'","'"$3"'"]}'"'"; }
ac() { ev 13_transfer.txt "$1" "$INV"' '"'"'{"function":"acceptTransfer","Args":["BATCH_DRONE_001"]}'"'"; }
tr org1 AttackerOrg Org1MSP           # another organisation: rejected
tr org2user AttackerOrg Org2MSP       # same organisation, different user: rejected
tr org2 DefenceBuyerOrg Org1MSP       # custodian identity offers the batch to the buyer organisation
ac org2                               # offering organisation cannot accept on the buyer's behalf: rejected
ac org1user                           # an identity of the receiving organisation accepts
tr org2 ThirdPartyOrg Org2MSP         # former custodian: rejected
q 14_history_after_transfer.txt org2 getBatchHistory BATCH_DRONE_001

# ---- 15 off-chain evidence integrity check
{
  ON=$( org2; peer chaincode query -C mychannel -n remtrace -c '{"Args":["queryBatch","BATCH_ORE_001"]}' 2>/dev/null | jq -r .propertiesHash )
  echo "on-chain propertiesHash (BATCH_ORE_001): $ON"
  echo "\$ sha256sum offchain/BATCH_ORE_001_evidence.txt"; A=$(h ORE); echo "$A"
  [ "$A" = "$ON" ] && echo "RESULT: MATCH (document unchanged)" || echo "RESULT: MISMATCH"
  cp "$OFF/BATCH_ORE_001_evidence.txt" "$OFF/BATCH_ORE_001_evidence_TAMPERED.txt"
  sed -i 's/origin/ORIGIN-EDITED/' "$OFF/BATCH_ORE_001_evidence_TAMPERED.txt"
  echo "\$ sha256sum offchain/BATCH_ORE_001_evidence_TAMPERED.txt"; B=$(sha256sum "$OFF/BATCH_ORE_001_evidence_TAMPERED.txt" | cut -d' ' -f1); echo "$B"
  [ "$B" = "$ON" ] && echo "RESULT: MATCH" || echo "RESULT: MISMATCH (tampering detected)"
} > "$EV/15_evidence_integrity.txt" 2>&1
echo done
