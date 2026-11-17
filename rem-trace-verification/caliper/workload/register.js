'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
class W extends WorkloadModuleBase {
  async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
    await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    this.n = 0; this.prefix = `BENCH_ORE_R${roundIndex}_W${workerIndex}_${Date.now()}`;
  }
  async submitTransaction() {
    this.n += 1;
    return this.sutAdapter.sendRequests({ contractId: 'remtrace', contractFunction: 'registerBatch', invokerIdentity: 'Admin',
      contractArguments: [`${this.prefix}_${this.n}`, '', 'MineOrg', 'ore', 'Australia',
        '33023d3111a7b4237d1fab6edee0c559aec1d7fabcdf2a76c458301d472a935f', 'true'], readOnly: false });
  }
}
module.exports.createWorkloadModule = () => new W();
