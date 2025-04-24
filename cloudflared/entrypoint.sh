#!/bin/sh
set -e

# Get Zone ID
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" | jq -r '.result[0].id')

# DEBUG
#echo -e "\n  [+] ZONE_ID=${ZONE_ID}"

# Get Account ID
CF_ACCOUNT_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${CF_ZONE}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].account.id')\

# Check if tunnel exists, based on name
CF_TUNNEL_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | \
  jq -r --arg NAME "$CF_TUNNEL_NAME" '.result[] | select(.name == $NAME) | .id' | head -n 1)

echo -e "\n  [!] CF_TUNNEL_ID=${CF_TUNNEL_ID}"

# If tunnels with your desired name exist, delete them
if [ ! -z "$CF_TUNNEL_ID" ] && [ "$CF_TUNNEL_ID" != "null" ]; then
  echo "Deleting existing tunnels with name: $CF_TUNNEL_NAME"
  for CF_TUNNEL_ID in $(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r --arg NAME "$CF_TUNNEL_NAME" '.result[] | select(.name == $NAME) | .id'); do
    curl -s -X DELETE "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/$CF_TUNNEL_ID" \
    -H "Authorization: Bearer ${CF_API_TOKEN}"
  done
fi

# Create a new tunnel and generate credentials file
response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{"name":"'"${CF_TUNNEL_NAME}"'", "config_src": "cloudflare"}')

if echo "$response" | grep -q '"success":true'; then
  CF_TUNNEL_ID=$(echo "$response" | jq -r '.result.id')
  echo -e "\n  [+] Created tunnel with ID: $CF_TUNNEL_ID"
  echo "${response}" | jq -r '.result.credentials_file' > "${CF_FILES_PATH}/${CF_TUNNEL_CREDENTIAL_FILE}"
  echo -e "\n  [+] Credentials file saved to ${CF_FILES_PATH}/${CF_TUNNEL_CREDENTIAL_FILE}"
else
  echo -e "\n  [-] Failed to create tunnel:"
  echo "$response"
  exit 1
fi

# Check for existing DNS record
existing_record_id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=CNAME&name=${CF_HOSTNAME}.${CF_ZONE}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" | jq -r '.result[0].id')

echo -e "\n  DEBUG: existing_record_id=${existing_record_id}"

# Create the DNS record if it doesn't exist
if [ -z "$existing_record_id" ] || [ "$existing_record_id" = "null" ]; then
  response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    --data '{"type":"CNAME","name":"'"${CF_HOSTNAME}.${CF_ZONE}"'","content":"'"${CF_TUNNEL_ID}.cfargotunnel.com"'","proxied":true}')
  echo -e "\n  DEBUG: DNS Record Create Response: ${response}"
  if ! echo "$response" | grep -q '"success":true'; then
    echo -e "\n  [-] Cloudflare DNS API error:"
    echo "$response"
  else
    echo -e "\n  [+] DNS record ${CF_HOSTNAME}.${CF_ZONE} created."
  fi
else
  echo -e "\n  [!] DNS record for ${CF_HOSTNAME}.${CF_ZONE} already exists with ID: ${existing_record_id}"
fi

# Create config
cat > ${CF_FILES_PATH}/${CF_CONFIG_FILE} <<EOF
tunnel: ${CF_TUNNEL_ID}
credentials-file: ${CF_FILES_PATH}/${CF_TUNNEL_CREDENTIAL_FILE}
ingress:
  - hostname: ${CF_HOSTNAME}.${CF_ZONE}
    service: http://signal-kasm:3000
  - service: http_status:404
EOF

# Create policy to allow your email
POLICY_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/access/policies" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{
    "name": "'"${ACCESS_POLICY_NAME}"'",
    "decision": "allow",
    "include": [
      {
        "email": {
          "email": "'"${CF_EMAIL}"'"
        }
      }
    ]
  }')

REUSABLE_POLICY_ID=$(echo "$POLICY_RESPONSE" | jq -r '.result.id')

# DEBUG
#echo -e "\n  [+] REUSABLE_POLICY_ID=${REUSABLE_POLICY_ID}"

# Create application and apply your email policy
APP_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/access/apps" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data '{
    "name": "'"${APP_NAME}"'",
    "domain": "'"${CF_HOSTNAME}.${CF_ZONE}"'",
    "type": "self_hosted",
    "session_duration": "24h",
    "allowed_idps": [],
    "app_launcher_visible": true,
    "policies": ["'"${REUSABLE_POLICY_ID}"'"]
  }')

APP_ID=$(echo "$APP_RESPONSE" | jq -r '.result.id')

# DEBUG
#echo -e "\n  [+] APP_ID=${APP_ID}"