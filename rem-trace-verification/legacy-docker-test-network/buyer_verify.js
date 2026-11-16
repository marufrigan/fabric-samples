#!/usr/bin/env node
'use strict';

/**
 * CLI buyer-side verification prototype for REM traceability.
 * Uses the Fabric peer binary (same as bash evidence scripts); not a mobile app.
 *
 * Usage:
 *   FABRIC_SAMPLES_ROOT=/path/to/fabric-samples node buyer_verify.js BATCH_DRONE_001
 */

const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = process.env.FABRIC_SAMPLES_ROOT || path.resolve(__dirname, '..');
const batchId = process.argv[2];

if (!batchId || batchId.startsWith('-')) {
  process.stderr.write(
    'Usage: node buyer_verify.js <BATCH_ID>\nExample: node buyer_verify.js BATCH_DRONE_001\n'
  );
  process.exit(1);
}

const peerEnv = {
  ...process.env,
  FABRIC_CFG_PATH: path.join(ROOT, 'config'),
  PATH: `${path.join(ROOT, 'bin')}${path.delimiter}${process.env.PATH || ''}`,
  CORE_PEER_TLS_ENABLED: 'true',
  CORE_PEER_LOCALMSPID: 'Org1MSP',
  CORE_PEER_TLS_ROOTCERT_FILE: path.join(
    ROOT,
    'test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt'
  ),
  CORE_PEER_MSPCONFIGPATH: path.join(
    ROOT,
    'test-network/organizations/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp'
  ),
  CORE_PEER_ADDRESS: 'localhost:7051'
};

function peerQuery(args) {
  const payload = JSON.stringify({ Args: args });
  return execFileSync(
    'peer',
    ['chaincode', 'query', '-C', 'mychannel', '-n', 'remtrace', '-c', payload],
    { encoding: 'utf8', env: peerEnv }
  ).trim();
}

function safeJson(label, text) {
  try {
    return JSON.parse(text);
  } catch (e) {
    throw new Error(`${label}: expected JSON from peer, got: ${text.slice(0, 200)}`);
  }
}

let lineage;
let lineageCompliance;
let droneBatch;

try {
  droneBatch = safeJson('queryBatch', peerQuery(['queryBatch', batchId]));
  lineage = safeJson('traceToOrigin', peerQuery(['traceToOrigin', batchId]));
  lineageCompliance = safeJson(
    'verifyFullLineageCompliance',
    peerQuery(['verifyFullLineageCompliance', batchId])
  );
} catch (err) {
  process.stderr.write(String(err.message || err) + '\n');
  process.exit(2);
}

const singleCompliance = safeJson('verifyCompliance', peerQuery(['verifyCompliance', batchId]));

const hashes = lineage.map((b) => ({
  batchID: b.batchID,
  materialType: b.materialType,
  propertiesHash: b.propertiesHash
}));

const lines = [];
lines.push('=== REM Trace — Buyer verification report (prototype) ===');
lines.push(`Drone / leaf batch ID: ${batchId}`);
lines.push('');
lines.push('--- Full lineage (leaf → origin) ---');
lineage.forEach((b, i) => {
  lines.push(
    `${i + 1}. ${b.batchID} | ${b.materialType} | owner=${b.owner} | country=${b.country} | complianceFlag=${b.complianceFlag}`
  );
});
lines.push('');
lines.push('--- Lineage compliance (chaincode) ---');
lines.push(JSON.stringify(lineageCompliance, null, 2));
lines.push('');
lines.push('--- Leaf batch compliance (policy + flag) ---');
lines.push(JSON.stringify(singleCompliance, null, 2));
lines.push('');
lines.push('--- Summary ---');
lines.push(`Lineage depth: ${lineageCompliance.lineageDepth}`);
lines.push(`Lineage compliant: ${lineageCompliance.isCompliant}`);
if (lineageCompliance.issues && lineageCompliance.issues.length) {
  lines.push('Issues:');
  lineageCompliance.issues.forEach((x) => lines.push(`  - ${x}`));
} else {
  lines.push('Issues: none reported by verifyFullLineageCompliance');
}
lines.push('');
lines.push('--- propertiesHash values (off-chain evidence anchors) ---');
hashes.forEach((h) => lines.push(`${h.batchID} [${h.materialType}]: ${h.propertiesHash}`));
lines.push('');
lines.push(
  'Note: This script uses the Fabric peer CLI. A production buyer UI or QR workflow would wrap the same queries via an SDK or gateway.'
);

process.stdout.write(lines.join('\n') + '\n');
