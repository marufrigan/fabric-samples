# Helper: source env.sh, then call org1 | org2 | org1user | org2user | regulator | regulatoruser
# to select the identity used by the peer CLI.
export NB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$NB/../bin:$PATH" FABRIC_CFG_PATH="$NB/../config" FABRIC_LOGGING_SPEC=ERROR CORE_PEER_TLS_ENABLED=true
export ORDERER_CA=$NB/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt
export ORG1_CA=$NB/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
export ORG2_CA=$NB/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
org1(){ export CORE_PEER_LOCALMSPID=Org1MSP CORE_PEER_ADDRESS=127.0.0.1:${1:-7051} CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_CA CORE_PEER_MSPCONFIGPATH=$NB/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp; }
org2(){ export CORE_PEER_LOCALMSPID=Org2MSP CORE_PEER_ADDRESS=127.0.0.1:${1:-7055} CORE_PEER_TLS_ROOTCERT_FILE=$ORG2_CA CORE_PEER_MSPCONFIGPATH=$NB/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp; }
_u(){ echo $NB/crypto-config/peerOrganizations/$1.example.com/users/$2@$1.example.com/msp; }
org1user(){ org1; export CORE_PEER_MSPCONFIGPATH=$(_u org1 User1); }
org2user(){ org2; export CORE_PEER_MSPCONFIGPATH=$(_u org2 User1); }
# The regulator organisation has no peers; its clients submit through the peers of Org1 and Org2.
regulator(){ export CORE_PEER_LOCALMSPID=RegulatorMSP CORE_PEER_ADDRESS=127.0.0.1:7051 CORE_PEER_TLS_ROOTCERT_FILE=$ORG1_CA CORE_PEER_MSPCONFIGPATH=$(_u regulator Admin); }
regulatoruser(){ regulator; export CORE_PEER_MSPCONFIGPATH=$(_u regulator User1); }
ORD="-o 127.0.0.1:6050 --ordererTLSHostnameOverride orderer.example.com --tls --cafile $ORDERER_CA"
