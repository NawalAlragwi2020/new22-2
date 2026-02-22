#!/bin/bash
set -e

echo "🔧 Starting Automated Caliper Fix and Run Script..."

# ============================================================
# 1. SETUP: Define ROOT_DIR and verify location
# ============================================================
ROOT_DIR="/workspaces/fabric_certificate_MT"

if [ ! -d "$ROOT_DIR/test-network" ]; then
    echo "❌ ERROR: ROOT_DIR not found. Adjust ROOT_DIR variable."
    exit 1
fi

echo "✅ ROOT_DIR: $ROOT_DIR"

# Create necessary directories
mkdir -p workload benchmarks networks

# ============================================================
# 2. DYNAMIC KEY FINDING: Locate private key
# ============================================================
echo "🔍 Searching for private key..."

KEY_FILE=$(find "$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore" -name "*_sk" -type f | head -n 1)

if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "❌ ERROR: Private key not found. Ensure network is running."
    exit 1
fi

echo "✅ Private Key Found: $KEY_FILE"

CERT_FILE="$ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/User1@org1.example.com-cert.pem"

if [ ! -f "$CERT_FILE" ]; then
    echo "❌ ERROR: Certificate not found at $CERT_FILE"
    exit 1
fi

echo "✅ Certificate Found: $CERT_FILE"

# ============================================================
# 3. OVERWRITE WORKLOAD: Create issueCertificate.js
# ============================================================
echo "📝 Creating workload/issueCertificate.js..."

cat > workload/issueCertificate.js << 'WORKLOAD_EOF'
'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');

class CreateAssetWorkload extends WorkloadModuleBase {
    constructor() {
        super();
    }

    async initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext) {
        await super.initializeWorkloadModule(workerIndex, totalWorkers, roundIndex, roundArguments, sutAdapter, sutContext);
        this.workerIndex = workerIndex;
    }

    async submitTransaction() {
        const assetID = `asset${this.workerIndex}_${Date.now()}_${Math.floor(Math.random() * 10000)}`;
        
        const args = {
            contractId: 'basic',
            contractFunction: 'CreateAsset',
            contractArguments: [
                assetID,
                'blue',
                '5',
                'Alice',
                '300'
            ],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(args);
    }
}

function createWorkloadModule() {
    return new CreateAssetWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
WORKLOAD_EOF

echo "✅ Workload created."

# ============================================================
# 4. OVERWRITE BENCH CONFIG: Create benchConfig.yaml
# ============================================================
echo "📝 Creating benchmarks/benchConfig.yaml..."

cat > benchmarks/benchConfig.yaml << 'BENCH_EOF'
test:
  name: fabric-basic-asset-benchmark
  description: Simple benchmark for CreateAsset operation
  workers:
    type: local
    number: 1
  rounds:
    - label: Create Asset
      description: Create new assets on the ledger
      txDuration: 30
      rateControl:
        type: fixed-rate
        opts:
          tps: 10
      workload:
        module: workload/issueCertificate.js
BENCH_EOF

echo "✅ Benchmark config created."

# ============================================================
# 5. OVERWRITE NETWORK CONFIG: Create networkConfig.yaml
# ============================================================
echo "📝 Creating networks/networkConfig.yaml..."

cat > networks/networkConfig.yaml << NETWORK_EOF
name: Fabric Test Network
version: "2.0.0"

caliper:
  blockchain: fabric

channels:
  - channelName: mychannel
    contracts:
      - id: basic

organizations:
  - mspid: Org1MSP
    identities:
      certificates:
        - name: 'User1'
          clientPrivateKey:
            path: '$KEY_FILE'
          clientSignedCert:
            path: '$CERT_FILE'
    connectionProfile:
      path: 'networks/connection-org1.yaml'
      discover: false
NETWORK_EOF

echo "✅ Network config created with discover: false"

# ============================================================
# 6. OVERWRITE CONNECTION PROFILE: Create connection-org1.yaml
# ============================================================
echo "📝 Creating networks/connection-org1.yaml..."

cat > networks/connection-org1.yaml << CONNECTION_EOF
name: test-network-org1
version: 1.0.0
client:
  organization: Org1
  connection:
    timeout:
      peer:
        endorser: '300'
      orderer: '300'

channels:
  mychannel:
    orderers:
      - orderer.example.com
    peers:
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true

organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
    certificateAuthorities:
      - ca.org1.example.com

  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com

orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
    tlsCACerts:
      path: $ROOT_DIR/test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
    tlsCACerts:
      path: $ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: $ROOT_DIR/test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

certificateAuthorities:
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: $ROOT_DIR/test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem
    httpOptions:
      verify: false
CONNECTION_EOF

echo "✅ Connection profile created with manual peer mapping."

# ============================================================
# 7. EXECUTION: Install dependencies and run Caliper
# ============================================================
echo "📦 Installing Caliper dependencies..."

npm install --silent 2>/dev/null || npm install

echo "🔗 Binding Caliper to Fabric 2.5..."

npx caliper bind --caliper-bind-sut fabric:2.5 --caliper-bind-args=-g

echo "🚀 Launching Caliper Benchmark..."

npx caliper launch manager \
  --caliper-workspace ./ \
  --caliper-networkconfig networks/networkConfig.yaml \
  --caliper-benchconfig benchmarks/benchConfig.yaml \
  --caliper-flow-only-test \
  --caliper-fabric-gateway-enabled

echo ""
echo "✅ Caliper benchmark completed!"
echo "📊 Check report.html for results."
