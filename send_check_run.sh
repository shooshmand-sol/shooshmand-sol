#!/usr/bin/env bash
set -euo pipefail

# Usage:
# ./create_check_run.sh <app_id> <owner> <repo> <private_key_path> <commit_sha> <conclusion> [<title>] [<summary>]
#
# Example:
# ./create_check_run.sh \
#   123456 my-org my-repo ./private-key.pem \
#   1a2b3c4d5e6f7 success "Tests Passed" "All automated tests have passed ✅"

APP_ID="$1"
OWNER="$2"
REPO="$3"
PRIVATE_KEY_PATH="$4"
COMMIT_SHA="$5"
CHECK_NAME="$6"
CONCLUSION="$7"
TITLE="${8:-Merge Queue Validation}"
SUMMARY="${9:-Merge queue validation completed.}"

# === 1️⃣ Create JWT for GitHub App authentication ===
ISSUED_AT=$(date +%s)
EXPIRATION=$((ISSUED_AT + 600))

HEADER=$(jq -nc --arg alg "RS256" --arg typ "JWT" '{alg: $alg, typ: $typ}')
PAYLOAD=$(jq -nc --arg iat "$ISSUED_AT" --arg exp "$EXPIRATION" --arg iss "$APP_ID" '{iat: ($iat | tonumber), exp: ($exp | tonumber), iss: ($iss | tonumber)}')

b64_encode() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

HEADER_B64=$(echo -n "$HEADER" | b64_encode)
PAYLOAD_B64=$(echo -n "$PAYLOAD" | b64_encode)
SIGNATURE=$(printf '%s.%s' "$HEADER_B64" "$PAYLOAD_B64" \
  | openssl dgst -binary -sha256 -sign "$PRIVATE_KEY_PATH" \
  | b64_encode)
JWT="${HEADER_B64}.${PAYLOAD_B64}.${SIGNATURE}"

echo "✅ Generated JWT."

# === 2️⃣ Get installation ID for this repository ===
INSTALLATION_ID=$(curl -s -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$OWNER/$REPO/installation" \
  | jq -r .id)

if [[ "$INSTALLATION_ID" == "null" || -z "$INSTALLATION_ID" ]]; then
  echo "❌ Failed to get installation ID. Is the app installed on $OWNER/$REPO?"
  exit 1
fi

echo "✅ Installation ID: $INSTALLATION_ID"

# === 3️⃣ Exchange JWT for an installation access token ===
ACCESS_TOKEN=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  | jq -r .token)

if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
  echo "❌ Failed to get installation access token."
  exit 1
fi

echo "✅ Got installation token."

# === 4️⃣ Create a check run ===
CREATE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $ACCESS_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$OWNER/$REPO/check-runs" \
  -d @- <<EOF
{
  "name": "$CHECK_NAME",
  "head_sha": "$COMMIT_SHA",
  "status": "completed",
  "conclusion": "$CONCLUSION",
  "output": {
    "title": "$TITLE",
    "summary": "$SUMMARY"
  }
}
EOF
)

CHECK_RUN_URL=$(echo "$CREATE_RESPONSE" | jq -r .html_url)
if [[ "$CHECK_RUN_URL" == "null" ]]; then
  echo "❌ Failed to create check run:"
  echo "$CREATE_RESPONSE"
  exit 1
fi

echo "✅ Check run created successfully!"
echo "🔗 $CHECK_RUN_URL"
