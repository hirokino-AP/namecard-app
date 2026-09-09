#!/bin/bash
set -e

echo "=== Codemagic Deploy Start ==="

if [ -f .env ]; then
  source .env
  echo "OK: .env loaded"
else
  echo "ERROR: .env not found"
  exit 1
fi

if [ -z "$CM_API_TOKEN" ]; then
  echo "ERROR: CM_API_TOKEN not set"
  exit 1
fi

if [ -z "$APP_ID" ]; then
  echo "ERROR: APP_ID not set"
  exit 1
fi

echo "OK: APP_ID = $APP_ID"
echo "Triggering build..."

RESPONSE=$(curl -s -X POST \
  "https://api.codemagic.io/builds" \
  -H "x-auth-token: $CM_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"appId\": \"$APP_ID\", \"workflowId\": \"ios-workflow\", \"branch\": \"main\"}")

echo "Response: $RESPONSE"

BUILD_ID=$(echo $RESPONSE | grep -o '"buildId":"[^"]*"' | cut -d'"' -f4)

if [ -n "$BUILD_ID" ]; then
  echo "Build started! URL: https://codemagic.io/build/$BUILD_ID"
else
  echo "Check response above"
fi

echo "=== Done ==="
