'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    // FIX #6: override initializeWorkloadModule so that this.workerIndex is set correctly
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        this.txIndex++;
        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;

        const request = {
            contractId: 'basic',
            // FIX #5: call RevokeCertificate to match the deployed chaincode function name
            contractFunction: 'RevokeCertificate',
            contractArguments: [certID],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports.createWorkloadModule = () => new RevokeCertificateWorkload();
