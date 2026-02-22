'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class QueryAllCertificatesWorkload extends WorkloadModuleBase {
    async submitTransaction() {
        const request = {
            contractId: 'basic',
            contractFunction: 'QueryAllCertificates', 
            contractArguments: [],
            readOnly: true
        };

        // استخدام return لضمان قياس زمن الاستجابة (Latency) بدقة
        return this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new QueryAllCertificatesWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
