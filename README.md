# REMTrace: Rare Earth Magnet Traceability on Hyperledger Fabric

REMTrace is a Hyperledger Fabric chaincode and test suite for batch-level traceability of rare earth magnets through a drone supply chain:

```
ore -> refined material -> magnet -> motor -> drone
```

Each stage is recorded as a batch on a permissioned ledger and linked to its parent batch, so a finished drone batch can be traced back to the ore it came from and checked against a restricted-country policy across the whole lineage. Certificates, laboratory reports and other evidence stay off-chain and are anchored on the ledger by hash.

This is a research prototype. It demonstrates the design on a local Fabric test network and is not a production system.

## What the chaincode enforces

| Rule | Where |
|---|---|
| Batch identifiers are unique | `registerBatch` |
| Only `ore`, `refined`, `magnet`, `motor`, `drone` are valid stages | `registerBatch` |
| Stages must follow the sequence above; only ore may have no parent | `registerBatch` |
| Each stage can be written only by the organisation named in the material registration policy | `registerBatch` |
| Evidence references must be a CID or a 64 to 128 character hex digest | `registerBatch`, `registerCertificate` |
| The regulator role is ledger state, not a hard-coded organisation | `setGovernancePolicy` |
| Policies and certificates can be written only by an administrator of the regulator organisation | `setRestrictedCountriesPolicy`, `setMaterialRegistrationPolicy`, `registerCertificate` |
| Custody can be offered only by the identity that holds the batch, and accepted only by the receiving organisation | `transferBatch`, `acceptTransfer` |

## Chaincode functions

| Function | Type | Purpose |
|---|---|---|
| `setGovernancePolicy(regulatorMSP)` | invoke | Set the regulator organisation. Open once at deployment, afterwards only the current regulator can change it. |
| `getGovernancePolicy()` | query | Read the governance policy. |
| `setMaterialRegistrationPolicy(policyJSON)` | invoke | Map each stage to the MSP and owner allowed to register it. |
| `setRestrictedCountriesPolicy(countriesJSON)` | invoke | Set the list of restricted countries. |
| `registerBatch(batchID, parentBatchID, owner, materialType, country, propertiesHash, complianceFlag)` | invoke | Register a batch after all checks pass. |
| `queryBatch(batchID)` | query | Current record of a batch. |
| `getBatchHistory(batchID)` | query | All ledger changes to a batch. |
| `traceToOrigin(batchID)` | query | Lineage from a batch back to its ore batch. |
| `verifyCompliance(batchID)` | query | Batch-level compliance check. |
| `verifyFullLineageCompliance(batchID)` | query | Compliance and structure check over the whole lineage, with a list of issues. |
| `registerCertificate(batchID, certificateID, type, issuer, issueDate, expiryDate, certificateHash, status)` | invoke | Record certificate metadata and the hash of the certificate document. |
| `verifyCertificate(batchID, certificateID)` | query | Check that a certificate record exists, is `VALID` and has not expired. |
| `transferBatch(batchID, newOwner, newOwnerMSP)` | invoke | Offer a batch to another organisation (pending until accepted). |
| `acceptTransfer(batchID)` | invoke | Accept a pending transfer and take custody. |

## Repository layout

```
rem-trace-chaincode/        Node.js chaincode (lib/contract.js)
rem-trace-verification/
  run_all_tests.sh          Full test sequence; writes one transcript per test
  evidence/                 Transcripts (command and raw output) from the last run
  offchain/                 Sample evidence documents whose SHA-256 digests are anchored on-chain
  caliper/                  Hyperledger Caliper configuration, workloads and results
  figures/                  Figures rendered from the transcripts
  make_figures.py           Renders the transcript figures
  plot_benchmark.py         Plots the benchmark chart
test-network-nano-bash/     Network configuration (three organisations) and the env.sh helper
```

## Running it

The network is the `test-network-nano-bash` sample from [hyperledger/fabric-samples](https://github.com/hyperledger/fabric-samples), which runs the Fabric binaries directly without Docker containers for the nodes.

**Prerequisites:** Fabric v2.5 binaries and config (`bin/`, `config/`), Node.js 20 or later, `jq`.

1. Get `fabric-samples` and the Fabric binaries, then copy the three directories of this repository into the `fabric-samples` folder. The files under `test-network-nano-bash/` replace `configtx.yaml` and `crypto-config.yaml` and add `env.sh`.

2. Start the network and enable the Node.js external builder:

   ```bash
   cd test-network-nano-bash
   ./configureExternalBuilders.sh
   ./network.sh start          # leave running; use another terminal for the next steps
   ```

3. Package, install, approve and commit the chaincode:

   ```bash
   cd ..
   source test-network-nano-bash/env.sh
   org1
   peer lifecycle chaincode package remtrace.tar.gz --path rem-trace-chaincode --lang node --label remtrace_1.0
   PKG=$(peer lifecycle chaincode calculatepackageid remtrace.tar.gz)

   for p in "org1 7051" "org1 7053" "org2 7055" "org2 7057"; do $p; peer lifecycle chaincode install remtrace.tar.gz; done
   for o in org1 org2; do $o; peer lifecycle chaincode approveformyorg $ORD --channelID mychannel --name remtrace --version 1.0 --package-id $PKG --sequence 1; done

   org1
   peer lifecycle chaincode commit $ORD --channelID mychannel --name remtrace --version 1.0 --sequence 1 \
     --peerAddresses 127.0.0.1:7051 --tlsRootCertFiles $ORG1_CA \
     --peerAddresses 127.0.0.1:7055 --tlsRootCertFiles $ORG2_CA
   ```

4. Run the tests:

   ```bash
   ./rem-trace-verification/run_all_tests.sh
   ```

   Transcripts are written to `rem-trace-verification/evidence/`. Run the script against a freshly deployed network, because it registers fixed batch identifiers.

5. Optional benchmark with [Hyperledger Caliper](https://hyperledger.github.io/caliper/) 0.6.0:

   ```bash
   cd rem-trace-verification/caliper
   npm install --omit=dev @hyperledger/caliper-cli@0.6.0
   npx caliper bind --caliper-bind-sut fabric:fabric-gateway
   npx caliper launch manager --caliper-workspace . --caliper-networkconfig network.yaml \
     --caliper-benchconfig benchmark.yaml --caliper-flow-only-test --caliper-fabric-gateway-enabled
   ```

## Network used for the recorded results

- Hyperledger Fabric v2.5.15, three-node Raft ordering service
- `Org1MSP` and `Org2MSP`, two peers each; `RegulatorMSP` with client identities only
- Channel `mychannel`, endorsement policy `MAJORITY Endorsement` (peers of Org1MSP and Org2MSP)
- Org1MSP registers ore, refined and magnet batches; Org2MSP registers motor and drone batches; RegulatorMSP sets policies and registers certificates
- Single host: Ubuntu 24.04, 2 virtual CPU cores, 8 GB memory

## What the test sequence covers

| Transcript | Test |
|---|---|
| `01_lifecycle` | Installed package and committed chaincode definition |
| `02_governance` | Regulator role set at deployment; takeover and non-regulator policy updates rejected |
| `02_policies` | Material registration and restricted-country policies |
| `03_register_lineage` | Five-stage lineage registered and committed on both organisations' peers |
| `04` to `07` | Batch query, lineage trace, compliance checks, history |
| `08_negative` | Eight invalid registrations, all rejected at endorsement |
| `09`, `10` | Lineage with ore from a restricted country, detected by the full-lineage check |
| `11`, `12` | Certificate registration and verification, including revoked, expired and unknown certificates |
| `13`, `14` | Two-step custody transfer with rejected callers, and the resulting history |
| `15` | Off-chain evidence integrity check against the on-chain hash |

## Benchmark summary

Caliper, two workers, fixed send rate, on the host described above:

| Workload | Rate | Throughput | Average latency |
|---|---|---|---|
| `registerBatch` | 50 TPS | 50.0 TPS | 0.17 s |
| `registerBatch` | 100 TPS (saturated) | 75.7 TPS | 2.43 s |
| `queryBatch`, `traceToOrigin`, `verifyFullLineageCompliance` | 200 TPS | 200 TPS | 0.01 s |

Full results are in `rem-trace-verification/caliper/results_table.txt`. All nodes, chaincode processes and the benchmark client share one two-core machine, so these numbers describe the prototype, not production capacity.

## Limitations

- The ledger records and checks claims; it cannot prove that the physical material matches the record. Audits, laboratory testing and physical tagging are still needed.
- Certificate verification covers ledger metadata (existence, status, expiry, hash). It does not validate the certificate document or its signature.
- The first `setGovernancePolicy` call is protected by the channel endorsement policy and should be made as part of deployment.
- Private data collections and separate channels are not used; all channel members can read all batch records.
- A lost custodian key has no recovery path yet; a regulator-approved reassignment would be needed in practice.

## License

Apache-2.0
