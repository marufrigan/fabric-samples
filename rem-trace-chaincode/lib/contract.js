'use strict';

const { Contract } = require('fabric-contract-api');

class REMTraceContract extends Contract {
  static get RESTRICTED_COUNTRIES_KEY() {
    return '_POLICY_RESTRICTED_COUNTRIES';
  }

  static get MATERIAL_POLICY_KEY() {
    return '_POLICY_MATERIAL_REGISTRATION';
  }

  static get GOVERNANCE_KEY() {
    return '_POLICY_GOVERNANCE';
  }

  static get MAX_LINEAGE_DEPTH() {
    return 25;
  }

  normalizeCountry(country) {
    return String(country || '').trim().toUpperCase();
  }

  normalizeMaterialType(materialType) {
    return String(materialType || '').trim().toLowerCase();
  }

  validatePropertiesHash(propertiesHash) {
    const hash = String(propertiesHash || '').trim();

    // Accept common research/demo formats:
    // - CIDv0: Qm...
    // - CIDv1 (base32 lowercase): b...
    // - SHA-256/512/3 style hex with optional 0x prefix
    const cidV0Regex = /^Qm[1-9A-HJ-NP-Za-km-z]{44}$/;
    const cidV1Regex = /^b[a-z2-7]{20,}$/;
    const hexHashRegex = /^(0x)?[a-fA-F0-9]{64,128}$/;

    if (!cidV0Regex.test(hash) && !cidV1Regex.test(hash) && !hexHashRegex.test(hash)) {
      throw new Error(
        'propertiesHash must be a valid CID (v0/v1) or hex hash (64-128 chars)'
      );
    }
  }

  validateAllowedMaterialType(materialType) {
    const allowedMaterialTypes = ['ore', 'refined', 'magnet', 'motor', 'drone'];
    if (!allowedMaterialTypes.includes(materialType)) {
      throw new Error(
        `Invalid materialType. Allowed values: ${allowedMaterialTypes.join(', ')}`
      );
    }
  }

  toISOStringFromFabricTimestamp(timestamp) {
    if (!timestamp || typeof timestamp !== 'object') {
      throw new Error('Missing Fabric transaction timestamp');
    }

    const secondsRaw = timestamp.seconds;
    let seconds;

    if (secondsRaw && typeof secondsRaw === 'object') {
      if (typeof secondsRaw.low === 'number') {
        seconds = secondsRaw.low;
      } else if (typeof secondsRaw.toInt === 'function') {
        seconds = secondsRaw.toInt();
      } else if (typeof secondsRaw.toNumber === 'function') {
        seconds = secondsRaw.toNumber();
      }
    } else if (typeof secondsRaw === 'string' || typeof secondsRaw === 'number') {
      seconds = Number(secondsRaw);
    }

    if (!Number.isFinite(seconds)) {
      throw new Error('Invalid Fabric timestamp seconds');
    }

    const nanos = Number(timestamp.nanos || 0);
    if (!Number.isFinite(nanos)) {
      throw new Error('Invalid Fabric timestamp nanos');
    }

    const millis = seconds * 1000 + Math.floor(nanos / 1000000);
    const iso = new Date(millis).toISOString();
    if (iso === 'Invalid Date') {
      throw new Error('Invalid Fabric transaction timestamp');
    }

    return iso;
  }

  async getDefaultMaterialRegistrationPolicy() {
    // These MSP IDs/owners are intentionally explicit for research demonstrations.
    return {
      ore: { mspId: 'MineOrgMSP', owner: 'MineOrg' },
      refined: { mspId: 'RefineryOrgMSP', owner: 'RefineryOrg' },
      magnet: { mspId: 'MagnetFactoryOrgMSP', owner: 'MagnetFactoryOrg' },
      motor: { mspId: 'MotorFactoryOrgMSP', owner: 'MotorFactoryOrg' },
      drone: { mspId: 'DroneFactoryOrgMSP', owner: 'DroneFactoryOrg' }
    };
  }

  async getMaterialRegistrationPolicy(ctx) {
    const bytes = await ctx.stub.getState(REMTraceContract.MATERIAL_POLICY_KEY);
    if (!bytes || bytes.length === 0) {
      return this.getDefaultMaterialRegistrationPolicy();
    }

    return JSON.parse(bytes.toString());
  }

  async getRestrictedCountries(ctx) {
    const bytes = await ctx.stub.getState(REMTraceContract.RESTRICTED_COUNTRIES_KEY);
    if (!bytes || bytes.length === 0) {
      return ['RESTRICTEDLAND', 'BANNEDSTATE'];
    }

    const list = JSON.parse(bytes.toString());
    if (!Array.isArray(list)) {
      throw new Error('Restricted countries policy must be an array');
    }

    return list.map((country) => this.normalizeCountry(country));
  }

  async enforceRegistrationPolicy(ctx, materialType, owner) {
    const policy = await this.getMaterialRegistrationPolicy(ctx);
    const rule = policy[materialType];
    if (!rule || !rule.mspId) {
      throw new Error(`Registration policy is missing for materialType ${materialType}`);
    }

    const clientMSP = ctx.clientIdentity.getMSPID();
    if (clientMSP !== rule.mspId) {
      throw new Error(
        `Unauthorized writer for ${materialType}. Required MSP: ${rule.mspId}, got: ${clientMSP}`
      );
    }

    if (rule.owner && String(owner).trim() !== String(rule.owner).trim()) {
      throw new Error(
        `owner must match policy owner "${rule.owner}" for materialType ${materialType}`
      );
    }
  }

  validateStageTransition(parentMaterialType, childMaterialType) {
    const allowedTransitions = {
      ore: 'refined',
      refined: 'magnet',
      magnet: 'motor',
      motor: 'drone'
    };

    const expectedChild = allowedTransitions[parentMaterialType];
    if (!expectedChild || expectedChild !== childMaterialType) {
      throw new Error(
        `Invalid stage transition: ${parentMaterialType} -> ${childMaterialType}`
      );
    }
  }

  // ---------------------------------------------------------------------
  // Governance: the regulator organisation is held as ledger state, not as a
  // hard-coded MSP. It is set once at deployment and can afterwards only be
  // changed by an administrator of the current regulator organisation.
  // ---------------------------------------------------------------------
  isAdminIdentity(ctx) {
    return ctx.clientIdentity.getID().includes('/OU=admin/');
  }

  async getRegulatorMSP(ctx) {
    const bytes = await ctx.stub.getState(REMTraceContract.GOVERNANCE_KEY);
    if (!bytes || bytes.length === 0) {
      return '';
    }
    return String(JSON.parse(bytes.toString()).regulatorMSP || '');
  }

  async requireRegulator(ctx, action) {
    const regulatorMSP = await this.getRegulatorMSP(ctx);
    if (!regulatorMSP) {
      throw new Error('Governance policy is not initialised. Call setGovernancePolicy first');
    }
    const clientMSP = ctx.clientIdentity.getMSPID();
    if (clientMSP !== regulatorMSP) {
      throw new Error(`Only the regulator MSP (${regulatorMSP}) can ${action}, got: ${clientMSP}`);
    }
    if (!this.isAdminIdentity(ctx)) {
      throw new Error(`Only an administrator identity of ${regulatorMSP} can ${action}`);
    }
  }

  async setGovernancePolicy(ctx, regulatorMSP) {
    const next = String(regulatorMSP || '').trim();
    if (!next) {
      throw new Error('regulatorMSP is required');
    }
    if (!this.isAdminIdentity(ctx)) {
      throw new Error('Only an administrator identity can set the governance policy');
    }

    const current = await this.getRegulatorMSP(ctx);
    const clientMSP = ctx.clientIdentity.getMSPID();
    if (current && clientMSP !== current) {
      throw new Error(
        `Only the current regulator MSP (${current}) can change the governance policy, got: ${clientMSP}`
      );
    }

    const policy = {
      regulatorMSP: next,
      setByMSP: clientMSP,
      setByID: ctx.clientIdentity.getID(),
      updatedAt: this.toISOStringFromFabricTimestamp(ctx.stub.getTxTimestamp())
    };
    await ctx.stub.putState(REMTraceContract.GOVERNANCE_KEY, Buffer.from(JSON.stringify(policy)));
    return JSON.stringify(policy);
  }

  async getGovernancePolicy(ctx) {
    const bytes = await ctx.stub.getState(REMTraceContract.GOVERNANCE_KEY);
    if (!bytes || bytes.length === 0) {
      throw new Error('Governance policy is not initialised');
    }
    return bytes.toString();
  }

  async setRestrictedCountriesPolicy(ctx, restrictedCountriesJSON) {
    await this.requireRegulator(ctx, 'update the restricted countries policy');

    const countries = JSON.parse(restrictedCountriesJSON);
    if (!Array.isArray(countries) || countries.length === 0) {
      throw new Error('restrictedCountriesJSON must be a non-empty JSON array');
    }

    const normalized = countries.map((country) => this.normalizeCountry(country));
    await ctx.stub.putState(
      REMTraceContract.RESTRICTED_COUNTRIES_KEY,
      Buffer.from(JSON.stringify(normalized))
    );

    return JSON.stringify(normalized);
  }

  async setMaterialRegistrationPolicy(ctx, policyJSON) {
    await this.requireRegulator(ctx, 'update the material registration policy');

    const policy = JSON.parse(policyJSON);
    const materialTypes = ['ore', 'refined', 'magnet', 'motor', 'drone'];

    for (const materialType of materialTypes) {
      if (!policy[materialType] || !policy[materialType].mspId) {
        throw new Error(`Policy missing mspId for materialType ${materialType}`);
      }
    }

    await ctx.stub.putState(
      REMTraceContract.MATERIAL_POLICY_KEY,
      Buffer.from(JSON.stringify(policy))
    );

    return JSON.stringify(policy);
  }

  async batchExists(ctx, batchID) {
    const batchBytes = await ctx.stub.getState(batchID);
    return batchBytes && batchBytes.length > 0;
  }

  async registerBatch(
    ctx,
    batchID,
    parentBatchID,
    owner,
    materialType,
    country,
    propertiesHash,
    complianceFlag
  ) {
    if (!batchID || batchID.trim() === '') {
      throw new Error('batchID is required');
    }

    const exists = await this.batchExists(ctx, batchID);
    if (exists) {
      throw new Error(`Batch ${batchID} already exists`);
    }

    if (!owner || owner.trim() === '') {
      throw new Error('owner is required');
    }

    const normalizedMaterialType = this.normalizeMaterialType(materialType);
    this.validateAllowedMaterialType(normalizedMaterialType);
    await this.enforceRegistrationPolicy(ctx, normalizedMaterialType, owner);

    if (!country || country.trim() === '') {
      throw new Error('country is required');
    }
    const normalizedCountry = this.normalizeCountry(country);

    if (!propertiesHash || propertiesHash.trim() === '') {
      throw new Error('propertiesHash is required');
    }
    this.validatePropertiesHash(propertiesHash);

    if (parentBatchID && parentBatchID.trim() !== '') {
      const parentExists = await this.batchExists(ctx, parentBatchID);
      if (!parentExists) {
        throw new Error(`Parent batch ${parentBatchID} does not exist`);
      }

      const parentBatch = JSON.parse(await this.queryBatch(ctx, parentBatchID));
      this.validateStageTransition(
        this.normalizeMaterialType(parentBatch.materialType),
        normalizedMaterialType
      );
    } else if (normalizedMaterialType !== 'ore') {
      throw new Error('Only ore can be registered without a parentBatchID');
    }

    const normalizedComplianceFlag = String(complianceFlag).toLowerCase();
    if (!['true', 'false'].includes(normalizedComplianceFlag)) {
      throw new Error('complianceFlag must be true or false');
    }

    const txTimestamp = ctx.stub.getTxTimestamp();
    const timestamp = this.toISOStringFromFabricTimestamp(txTimestamp);
    const creatorMSP = ctx.clientIdentity.getMSPID();
    const creatorID = ctx.clientIdentity.getID();

    const batch = {
      batchID,
      parentBatchID: parentBatchID || '',
      owner,
      materialType: normalizedMaterialType,
      country: normalizedCountry,
      propertiesHash,
      complianceFlag: normalizedComplianceFlag === 'true',
      timestamp,
      creatorMSP,
      creatorID,
      custodianMSP: creatorMSP,
      custodianID: creatorID,
      previousOwner: '',
      transferTimestamp: ''
    };

    await ctx.stub.putState(batchID, Buffer.from(JSON.stringify(batch)));
    await ctx.stub.putState(
      ctx.stub.createCompositeKey('owner~batch', [owner, batchID]),
      Buffer.from('\u0000')
    );
    await ctx.stub.putState(
      ctx.stub.createCompositeKey('materialType~batch', [normalizedMaterialType, batchID]),
      Buffer.from('\u0000')
    );

    return JSON.stringify(batch);
  }

  async queryBatch(ctx, batchID) {
    if (!batchID || batchID.trim() === '') {
      throw new Error('batchID is required');
    }

    const batchBytes = await ctx.stub.getState(batchID);
    if (!batchBytes || batchBytes.length === 0) {
      throw new Error(`Batch ${batchID} does not exist`);
    }

    return batchBytes.toString();
  }

  async getBatchHistory(ctx, batchID) {
    if (!batchID || batchID.trim() === '') {
      throw new Error('batchID is required');
    }

    const exists = await this.batchExists(ctx, batchID);
    if (!exists) {
      throw new Error(`Batch ${batchID} does not exist`);
    }

    const iterator = await ctx.stub.getHistoryForKey(batchID);
    const history = [];

    try {
      let result = await iterator.next();
      while (!result.done) {
        const historyRecord = {
          txId: result.value.txId,
          timestamp: this.toISOStringFromFabricTimestamp(result.value.timestamp),
          isDelete: result.value.isDelete
        };

        if (result.value.value && result.value.value.length > 0) {
          historyRecord.value = JSON.parse(result.value.value.toString('utf8'));
        } else {
          historyRecord.value = null;
        }

        history.push(historyRecord);
        result = await iterator.next();
      }
    } finally {
      await iterator.close();
    }

    return JSON.stringify(history);
  }

  async verifyCompliance(ctx, batchID) {
    if (!batchID || batchID.trim() === '') {
      throw new Error('batchID is required');
    }

    const batchJSON = await this.queryBatch(ctx, batchID);
    const batch = JSON.parse(batchJSON);

    const restrictedCountries = await this.getRestrictedCountries(ctx);
    const countryRestricted = restrictedCountries.includes(this.normalizeCountry(batch.country));

    const compliant = Boolean(batch.complianceFlag) && !countryRestricted;

    return JSON.stringify({
      batchID: batch.batchID,
      complianceFlag: batch.complianceFlag,
      country: batch.country,
      restrictedCountries,
      isCompliant: compliant,
      reason: compliant
        ? 'Batch is compliant'
        : 'Batch failed compliance flag or country restriction checks'
    });
  }

  async traceToOrigin(ctx, batchID) {
    if (!batchID || batchID.trim() === '') {
      throw new Error('batchID is required');
    }

    const lineage = [];
    const visited = new Set();
    let currentBatchID = batchID;
    let depth = 0;

    while (currentBatchID) {
      if (visited.has(currentBatchID)) {
        throw new Error(`Cycle detected in lineage at batch ${currentBatchID}`);
      }
      visited.add(currentBatchID);

      if (depth > REMTraceContract.MAX_LINEAGE_DEPTH) {
        throw new Error('Lineage depth exceeded maximum allowed limit');
      }

      const batchJSON = await this.queryBatch(ctx, currentBatchID);
      const batch = JSON.parse(batchJSON);
      lineage.push(batch);

      currentBatchID = batch.parentBatchID;
      depth += 1;
    }

    return JSON.stringify(lineage);
  }

  async verifyFullLineageCompliance(ctx, batchID) {
    const lineageJSON = await this.traceToOrigin(ctx, batchID);
    const lineage = JSON.parse(lineageJSON);
    const restrictedCountries = await this.getRestrictedCountries(ctx);

    const issues = [];

    for (let i = 0; i < lineage.length; i += 1) {
      const batch = lineage[i];
      const normalizedCountry = this.normalizeCountry(batch.country);

      if (!batch.complianceFlag) {
        issues.push(`Batch ${batch.batchID} has complianceFlag=false`);
      }

      if (restrictedCountries.includes(normalizedCountry)) {
        issues.push(`Batch ${batch.batchID} is from restricted country ${normalizedCountry}`);
      }

      // Validate continuity and transitions along lineage.
      const parent = i < lineage.length - 1 ? lineage[i + 1] : null;
      if (parent) {
        if (batch.parentBatchID !== parent.batchID) {
          issues.push(`Batch ${batch.batchID} parent link mismatch`);
        } else {
          try {
            this.validateStageTransition(
              this.normalizeMaterialType(parent.materialType),
              this.normalizeMaterialType(batch.materialType)
            );
          } catch (error) {
            issues.push(String(error.message));
          }
        }
      } else if (this.normalizeMaterialType(batch.materialType) !== 'ore') {
        issues.push(`Origin batch ${batch.batchID} is not ore`);
      }
    }

    return JSON.stringify({
      batchID,
      isCompliant: issues.length === 0,
      issues,
      lineageDepth: lineage.length
    });
  }

  _certificateKey(stub, batchID, certificateID) {
    return stub.createCompositeKey('certificate', [batchID, certificateID]);
  }

  parseISODate(label, value) {
    const s = String(value || '').trim();
    if (!s) {
      throw new Error(`${label} is required`);
    }
    const t = Date.parse(s);
    if (!Number.isFinite(t)) {
      throw new Error(`${label} must be a valid ISO-8601 date string`);
    }
    return t;
  }

  async registerCertificate(
    ctx,
    batchID,
    certificateID,
    certificateType,
    issuer,
    issueDate,
    expiryDate,
    certificateHash,
    status
  ) {
    await this.requireRegulator(ctx, 'register certificates');

    if (!batchID || !batchID.trim()) {
      throw new Error('batchID is required');
    }
    if (!certificateID || !certificateID.trim()) {
      throw new Error('certificateID is required');
    }
    if (!(await this.batchExists(ctx, batchID))) {
      throw new Error(`Batch ${batchID} does not exist`);
    }

    const key = this._certificateKey(ctx.stub, batchID, certificateID.trim());
    const existing = await ctx.stub.getState(key);
    if (existing && existing.length > 0) {
      throw new Error(`Certificate ${certificateID} already exists for batch ${batchID}`);
    }

    if (!certificateType || !certificateType.trim()) {
      throw new Error('certificateType is required');
    }
    if (!issuer || !issuer.trim()) {
      throw new Error('issuer is required');
    }

    const issueMs = this.parseISODate('issueDate', issueDate);
    const expiryMs = this.parseISODate('expiryDate', expiryDate);
    if (issueMs > expiryMs) {
      throw new Error('issueDate must be on or before expiryDate');
    }

    if (!certificateHash || !certificateHash.trim()) {
      throw new Error('certificateHash is required');
    }
    this.validatePropertiesHash(certificateHash);

    const normalizedStatus = String(status || '').trim().toUpperCase();
    if (!['VALID', 'REVOKED', 'SUSPENDED', 'EXPIRED'].includes(normalizedStatus)) {
      throw new Error('status must be one of: VALID, REVOKED, SUSPENDED, EXPIRED');
    }

    const txTimestamp = ctx.stub.getTxTimestamp();
    const registeredAt = this.toISOStringFromFabricTimestamp(txTimestamp);

    const record = {
      batchID: batchID.trim(),
      certificateID: certificateID.trim(),
      certificateType: certificateType.trim(),
      issuer: issuer.trim(),
      issueDate: String(issueDate).trim(),
      expiryDate: String(expiryDate).trim(),
      certificateHash: String(certificateHash).trim(),
      status: normalizedStatus,
      registeredAt
    };

    await ctx.stub.putState(key, Buffer.from(JSON.stringify(record)));
    return JSON.stringify(record);
  }

  async verifyCertificate(ctx, batchID, certificateID) {
    if (!batchID || !batchID.trim()) {
      throw new Error('batchID is required');
    }
    if (!certificateID || !certificateID.trim()) {
      throw new Error('certificateID is required');
    }

    const key = this._certificateKey(ctx.stub, batchID, certificateID.trim());
    const bytes = await ctx.stub.getState(key);
    if (!bytes || bytes.length === 0) {
      return JSON.stringify({
        batchID: batchID.trim(),
        certificateID: certificateID.trim(),
        isValid: false,
        checks: { exists: false, statusValid: false, notExpired: false },
        message: 'Certificate record not found on ledger (metadata only; document authenticity is off-chain)'
      });
    }

    const cert = JSON.parse(bytes.toString());
    const txTimestamp = ctx.stub.getTxTimestamp();
    const nowMs = this.parseISODate('transaction time', this.toISOStringFromFabricTimestamp(txTimestamp));
    const expiryMs = Date.parse(cert.expiryDate);
    const notExpired =
      Number.isFinite(expiryMs) && Number.isFinite(nowMs) && expiryMs >= nowMs;
    const statusValid = cert.status === 'VALID';

    const isValid = statusValid && notExpired;
    const reasons = [];
    if (!statusValid) {
      reasons.push(`Certificate status is ${cert.status}, expected VALID for positive verification`);
    }
    if (!notExpired) {
      reasons.push('Certificate is expired relative to transaction time');
    }

    return JSON.stringify({
      batchID: cert.batchID,
      certificateID: cert.certificateID,
      isValid,
      checks: { exists: true, statusValid, notExpired },
      certificateType: cert.certificateType,
      issuer: cert.issuer,
      issueDate: cert.issueDate,
      expiryDate: cert.expiryDate,
      certificateHash: cert.certificateHash,
      message: isValid
        ? 'On-chain metadata and anchor hash are consistent; off-chain document must still be checked by auditors'
        : reasons.join('; ')
    });
  }

  // ---------------------------------------------------------------------
  // Custody transfer is a two-step handover bound to individual identities:
  //   1. transferBatch  - only the identity that currently holds custody may
  //                       offer the batch to another organisation.
  //   2. acceptTransfer - an identity of the receiving organisation accepts,
  //                       and becomes the new custodian.
  // ---------------------------------------------------------------------
  async transferBatch(ctx, batchID, newOwner, newOwnerMSP) {
    if (!batchID || !batchID.trim()) {
      throw new Error('batchID is required');
    }
    if (!newOwner || !newOwner.trim()) {
      throw new Error('newOwner is required');
    }
    if (!newOwnerMSP || !newOwnerMSP.trim()) {
      throw new Error('newOwnerMSP is required');
    }

    const batch = JSON.parse(await this.queryBatch(ctx, batchID));
    const oldOwner = String(batch.owner || '').trim();
    const trimmedNew = newOwner.trim();

    const custodianMSP = String(batch.custodianMSP || batch.creatorMSP || '').trim();
    const custodianID = String(batch.custodianID || batch.creatorID || '').trim();
    const clientMSP = ctx.clientIdentity.getMSPID();
    const clientID = ctx.clientIdentity.getID();

    if (!custodianMSP || clientMSP !== custodianMSP) {
      throw new Error(
        `Unauthorized transfer of ${batchID}. Current custodian MSP: ${custodianMSP}, got: ${clientMSP}`
      );
    }
    if (!custodianID || clientID !== custodianID) {
      throw new Error(
        `Unauthorized transfer of ${batchID}. Caller is not the identity that holds custody of this batch`
      );
    }
    if (oldOwner === trimmedNew) {
      throw new Error('newOwner must differ from current owner');
    }
    if (batch.pendingTransfer) {
      throw new Error(`Batch ${batchID} already has a pending transfer`);
    }

    batch.pendingTransfer = {
      newOwner: trimmedNew,
      newOwnerMSP: newOwnerMSP.trim(),
      offeredByMSP: clientMSP,
      offeredByID: clientID,
      offeredAt: this.toISOStringFromFabricTimestamp(ctx.stub.getTxTimestamp())
    };

    await ctx.stub.putState(batchID, Buffer.from(JSON.stringify(batch)));
    return JSON.stringify({ batchID, status: 'PENDING_ACCEPTANCE', pendingTransfer: batch.pendingTransfer });
  }

  async acceptTransfer(ctx, batchID) {
    if (!batchID || !batchID.trim()) {
      throw new Error('batchID is required');
    }

    const batch = JSON.parse(await this.queryBatch(ctx, batchID));
    const pending = batch.pendingTransfer;
    if (!pending) {
      throw new Error(`Batch ${batchID} has no pending transfer`);
    }

    const clientMSP = ctx.clientIdentity.getMSPID();
    if (clientMSP !== pending.newOwnerMSP) {
      throw new Error(
        `Unauthorized acceptance of ${batchID}. Receiving MSP: ${pending.newOwnerMSP}, got: ${clientMSP}`
      );
    }

    const oldOwner = String(batch.owner || '').trim();
    const transferTimestamp = this.toISOStringFromFabricTimestamp(ctx.stub.getTxTimestamp());

    const ownerIndexKey = ctx.stub.createCompositeKey('owner~batch', [oldOwner, batchID]);
    const ownerIdx = await ctx.stub.getState(ownerIndexKey);
    if (ownerIdx && ownerIdx.length > 0) {
      await ctx.stub.deleteState(ownerIndexKey);
    }
    await ctx.stub.putState(
      ctx.stub.createCompositeKey('owner~batch', [pending.newOwner, batchID]),
      Buffer.from('\u0000')
    );

    const previousCustodianMSP = batch.custodianMSP;
    batch.previousOwner = oldOwner;
    batch.owner = pending.newOwner;
    batch.custodianMSP = clientMSP;
    batch.custodianID = ctx.clientIdentity.getID();
    batch.transferredByMSP = pending.offeredByMSP;
    batch.transferredByID = pending.offeredByID;
    batch.transferTimestamp = transferTimestamp;
    delete batch.pendingTransfer;

    await ctx.stub.putState(batchID, Buffer.from(JSON.stringify(batch)));

    return JSON.stringify({
      batchID,
      status: 'TRANSFERRED',
      previousOwner: oldOwner,
      newOwner: batch.owner,
      previousCustodianMSP,
      newCustodianMSP: batch.custodianMSP,
      newCustodianID: batch.custodianID,
      transferTimestamp
    });
  }
}

module.exports = REMTraceContract;
