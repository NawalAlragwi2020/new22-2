'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class VerifyCertificateWorkload extends WorkloadModuleBase {
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
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;

        // Regenerate the same hash used during IssueCertificate so the verification matches
        const certHash = crypto.createHash('sha256').update(certID + studentName).digest('hex');

        const request = {
            contractId: 'basic',
            // FIX #5: call VerifyCertificate to match the deployed chaincode function name
            contractFunction: 'VerifyCertificate',
            contractArguments: [certID, certHash],
            readOnly: true
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports.createWorkloadModule = () => new VerifyCertificateWorkload();
