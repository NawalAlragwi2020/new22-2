'use strict';
const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto'); // أضفنا مكتبة التشفير

class IssueCertificateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
    }

    async submitTransaction() {
        this.txIndex++;
        
        const certID = `CERT_${this.workerIndex}_${this.txIndex}`;
        const studentName = `Student_${this.workerIndex}_${this.txIndex}`;
        const degree = 'Bachelor of Computer Science';
        const issuer = 'Digital University';
        // محاكاة بصمة رقمية حقيقية لزيادة مصداقية الاختبار
        const certHash = crypto.createHash('sha256').update(certID + studentName).digest('hex'); 
        const issueDate = new Date().toISOString().split('T')[0]; // تاريخ اليوم آلياً

        const request = {
            contractId: 'basic', 
            contractFunction: 'IssueCertificate', 
            contractArguments: [certID, studentName, degree, issuer, certHash, issueDate],
            readOnly: false
        };

        return this.sutAdapter.sendRequests(request); // تأكد من إرجاع الطلب للمحول
    }
}

module.exports = { createWorkloadModule: () => new IssueCertificateWorkload() };
