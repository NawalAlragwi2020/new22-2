'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class RevokeCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        const workerId = this.workerIndex || 0;
        const certID = `CERT_${workerId}_${this.txIndex}`;

        const request = {
            contractId: 'basic',
            contractFunction: 'RevokeCertificate',
            contractArguments: [certID],
            readOnly: false
        };

        // تحسين: استخدام return لضمان قياس زمن الكمون (Latency) الفعلي للمعاملة
        return this.sutAdapter.sendRequests(request);
    }
}

module.exports.createWorkloadModule = () => new RevokeCertificateWorkload();
