'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    // FIX #6: override initializeWorkloadModule so that this.workerIndex is set
    // (WorkloadModuleBase sets it here – without calling super it stays undefined)
    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
    }

    async submitTransaction() {
        this.txIndex++;

        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        const degree = 'Bachelor of Computer Science';
        const issuer = 'Digital University';
        const certHash = crypto.createHash('sha256').update(certID + studentName).digest('hex');
        const issueDate = new Date().toISOString().split('T')[0];

        const request = {
            contractId: 'basic',
            // FIX #5: call IssueCertificate – this must match the deployed chaincode function name
            contractFunction: 'IssueCertificate',
            contractArguments: [certID, studentName, degree, issuer, certHash, issueDate],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request);
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
