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
docker volume prune -f

# Deep Clean: Remove dev-* Docker images for fresh chaincode builds
echo "Performing deep-clean for Docker images starting with dev-*..."
DEV_IMAGE_IDS=$(docker images --format '{{.Repository}} {{.ID}}' | awk '$1 ~ /^(dev-|dev-peer)/ {print $2}' || true)
if [ -n "$DEV_IMAGE_IDS" ]; then
  echo "Found dev images: $DEV_IMAGE_IDS"
  docker rmi -f $DEV_IMAGE_IDS || true
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
    curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.5.9 1.5.7
else
    echo "Fabric tools found."
fi

export PATH=${PWD}/bin:$PATH
export FABRIC_CFG_PATH=${PWD}/config/

# Step 2: Start the test network
echo "Starting test network..."
cd test-network
./network.sh down
docker volume prune -f
docker system prune -f
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
    npx caliper bind --caliper-bind-sut fabric:2.2
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
      path: '../test-network/organizations/peerOrganizations/org1.example.com/connection-org1.yaml'
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
      path: '../test-network/organizations/peerOrganizations/org2.example.com/connection-org2.yaml'
      discover: false
EOFYAML

# Update the private key paths with actual values
if [ -n "$PVT_KEY1" ]; then
  sed -i "s|ORG1_KEY_PLACEHOLDER|$PVT_KEY1|g" networks/networkConfig.yaml
fi

if [ -n "$PVT_KEY2" ]; then
  sed -i "s|ORG2_KEY_PLACEHOLDER|$PVT_KEY2|g" networks/networkConfig.yaml
fi

echo "Network config generated successfully"

# Step 6: Run Caliper benchmark
echo "Running Caliper Benchmark..."

npx caliper launch manager \
    --caliper-workspace . \
    --caliper-networkconfig networks/networkConfig.yaml \
    --caliper-benchconfig benchmarks/benchConfig.yaml \
    --caliper-flow-only-test

echo "Finished. Report at: caliper-workspace/report.html"

cd ..
