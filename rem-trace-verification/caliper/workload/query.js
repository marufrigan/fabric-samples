'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
class W extends WorkloadModuleBase {
  async submitTransaction() {
    return this.sutAdapter.sendRequests({ contractId: 'remtrace', contractFunction: this.roundArguments.fn, invokerIdentity: 'Admin',
      contractArguments: ['BATCH_DRONE_001'], readOnly: true });
  }
}
module.exports.createWorkloadModule = () => new W();
