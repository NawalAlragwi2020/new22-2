#!/bin/bash
set -e

# Run permission fix script only in CI or when explicitly requested
if [ "${CI:-}" = "true" ] || [ "${CI:-}" = "1" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ "${FIX_PERMISSIONS:-}" = "true" ]; then
  if [ -x "./scripts/fix-permissions.sh" ]; then
    echo "Running scripts/fix-permissions.sh to fix permissions..."
    ./scripts/fix-permissions.sh || true
  else
    echo "Warning: scripts/fix-permissions.sh not found or not executable."
  fi
else
  echo "Skipping permission fix."
fi

# Clean up any old containers or networks
docker ps -aq | xargs -r docker rm -f || true
docker volume prune -f || true

# Deep Clean: Remove dev-* Docker images for fresh chaincode builds
echo "Performing deep-clean for Docker images starting with dev-*..."
DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
if [ -n "$DEV_IMAGE_IDS" ]; then
  echo "Found dev images: $DEV_IMAGE_IDS"
  # FIX #10: quote the variable to prevent word-splitting / globbing issues
  docker rmi -f "$DEV_IMAGE_IDS" || true
else
  echo "No dev-* images found."
fi

# Clean up old reports
rm -f caliper-workspace/report.html

# Clean up workspace
cd caliper-workspace && rm -rf networks/networkConfig.yaml && cd ..

echo "Starting Full Project Setup (Fabric + Caliper)..."
echo "=================================================="

# Step 1: Check and download Fabric tools
echo "Checking Fabric Binaries..."
if [ ! -d "bin" ]; then
    echo "Downloading Fabric tools..."
    # FIX #8: use the current official install URL (the bit.ly shortlink was deprecated)
    curl -sSL https://raw.githubusercontent.com/hyperledger/fabric/main/scripts/install-fabric.sh \
      | bash -s -- --fabric-version 2.5.9 --ca-version 1.5.7 binary
else
    echo "Fabric tools found."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# Step 2: Start the test network
echo "Starting test network..."
cd test-network
./network.sh down || true
docker volume prune -f || true
docker system prune -f || true
./network.sh up createChannel -c mychannel -ca -s couchdb
cd ..

# Step 3: Deploy smart contract
echo "Deploying Smart Contract..."
cd test-network
./network.sh deployCC -ccn basic -ccp ../asset-transfer-basic/chaincode-go -ccl go -ccep "OR('Org1MSP.peer','Org2MSP.peer')"
cd ..

# Step 4: Setup Caliper
echo "Setting up Caliper..."
cd caliper-workspace

if [ ! -d "node_modules" ]; then
    npm install
    # FIX #1 + #3: use fabric:2.5 to match the deployed Fabric 2.5.9 network
    # (caliper-cli 0.5.0 does NOT support the old fabric:2.2 binding)
    npx caliper bind --caliper-bind-sut fabric:2.5
fi

echo "Detecting Private Keys..."

# Find Org1 Key
KEY_DIR1="../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore"
PVT_KEY1=$(find "$KEY_DIR1" -name "*_sk" | head -n 1)

# Find Org2 Key
KEY_DIR2="../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/keystore"
PVT_KEY2=$(find "$KEY_DIR2" -name "*_sk" | head -n 1)

echo "Org1 Key: $PVT_KEY1"
echo "Org2 Key: $PVT_KEY2"

# Validate that both keys were actually found before continuing
if [ -z "$PVT_KEY1" ]; then
  echo "ERROR: Org1 private key not found in $KEY_DIR1 – is the network running?"
  exit 1
fi
if [ -z "$PVT_KEY2" ]; then
  echo "ERROR: Org2 private key not found in $KEY_DIR2 – is the network running?"
  exit 1
fi

# Step 5: Generate network config
echo "Generating network config..."
mkdir -p networks

cat > networks/networkConfig.yaml << 'EOFYAML'
name: Caliper-Fabric
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
        - name: 'User1@org1.example.com'
          clientPrivateKey:
            path: 'ORG1_KEY_PLACEHOLDER'
          clientSignedCert:
            path: '../test-network/organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/cert.pem'
    connectionProfile:
      path: 'networks/connection-org1.yaml'
      discover: false

  - mspid: Org2MSP
    identities:
      certificates:
        - name: 'User1@org2.example.com'
          clientPrivateKey:
            path: 'ORG2_KEY_PLACEHOLDER'
          clientSignedCert:
            path: '../test-network/organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp/signcerts/cert.pem'
    connectionProfile:
      path: 'networks/connection-org2.yaml'
      discover: false
EOFYAML

# Update the private key paths with actual values
sed -i "s|ORG1_KEY_PLACEHOLDER|$PVT_KEY1|g" networks/networkConfig.yaml
sed -i "s|ORG2_KEY_PLACEHOLDER|$PVT_KEY2|g" networks/networkConfig.yaml

echo "Network config generated successfully"

# -----------------------------------------------------------------------
# FIX #4: Generate connection-org1.yaml (was missing from original script)
# -----------------------------------------------------------------------
echo "Generating connection-org1.yaml..."
cat > networks/connection-org1.yaml << EOFCONN1
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
        chaincodeQuery: false
        ledgerQuery: false
        eventSource: false

organizations:
  Org1:
    mspid: Org1MSP
    peers:
      - peer0.org1.example.com
    certificateAuthorities:
      - ca.org1.example.com

orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
    tlsCACerts:
      path: ../test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

peers:
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt

certificateAuthorities:
  ca.org1.example.com:
    url: https://localhost:7054
    caName: ca-org1
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org1.example.com/ca/ca.org1.example.com-cert.pem
    httpOptions:
      verify: false
EOFCONN1

# -----------------------------------------------------------------------
# FIX #4 (cont.): Generate connection-org2.yaml (was COMPLETELY missing)
# -----------------------------------------------------------------------
echo "Generating connection-org2.yaml..."
cat > networks/connection-org2.yaml << EOFCONN2
name: test-network-org2
version: 1.0.0
client:
  organization: Org2
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
      peer0.org2.example.com:
        endorsingPeer: true
        chaincodeQuery: true
        ledgerQuery: true
        eventSource: true
      peer0.org1.example.com:
        endorsingPeer: true
        chaincodeQuery: false
        ledgerQuery: false
        eventSource: false

organizations:
  Org2:
    mspid: Org2MSP
    peers:
      - peer0.org2.example.com
    certificateAuthorities:
      - ca.org2.example.com

orderers:
  orderer.example.com:
    url: grpcs://localhost:7050
    grpcOptions:
      ssl-target-name-override: orderer.example.com
      hostnameOverride: orderer.example.com
    tlsCACerts:
      path: ../test-network/organizations/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

peers:
  peer0.org2.example.com:
    url: grpcs://localhost:9051
    grpcOptions:
      ssl-target-name-override: peer0.org2.example.com
      hostnameOverride: peer0.org2.example.com
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
  peer0.org1.example.com:
    url: grpcs://localhost:7051
    grpcOptions:
      ssl-target-name-override: peer0.org1.example.com
      hostnameOverride: peer0.org1.example.com
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt

certificateAuthorities:
  ca.org2.example.com:
    url: https://localhost:8054
    caName: ca-org2
    tlsCACerts:
      path: ../test-network/organizations/peerOrganizations/org2.example.com/ca/ca.org2.example.com-cert.pem
    httpOptions:
      verify: false
EOFCONN2

echo "Connection profiles generated successfully"

# Step 6: Run Caliper benchmark
echo "Running Caliper Benchmark..."

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo "Finished. Report at: caliper-workspace/report.html"

cd ..
