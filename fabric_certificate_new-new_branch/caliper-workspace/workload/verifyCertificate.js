'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto'); // استخدام مكتبة التشفير لمحاكاة الواقع

class VerifyCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        
        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        
        // توليد الهاش باستخدام SHA-256 ليطابق عملية الإصدار
        const certHash = crypto.createHash('sha256').update(certID + studentName).digest('hex');

        const request = {
            contractId: 'basic',
            contractFunction: 'VerifyCertificate', 
            contractArguments: [certID, certHash],
            readOnly: true 
        };

        // إرجاع النتيجة لمحرك Caliper لتسجيلها في التقرير النهائي
        return this.sutAdapter.sendRequests(request);
    }
}

module.exports.createWorkloadModule = () => new VerifyCertificateWorkload();
