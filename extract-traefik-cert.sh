#!/bin/bash

# Configurable variables
ACME_JSON="/opt/docker-composes/traefik/letsencrypt/acme.json"
CERT_DIR="./certs"
DOMAIN="mail.roudin.de"

CERT_PATH="$CERT_DIR/cert.pem"
KEY_PATH="$CERT_DIR/key.pem"
CHAIN_PATH="$CERT_DIR/fullchain.pem"

mkdir -p "$CERT_DIR"

# Check if ACME JSON exists and is non-empty
if [ ! -s "$ACME_JSON" ]; then
  echo "❌ Error: ACME file '$ACME_JSON' not found or is empty."
  exit 1
fi

# Extract and decode cert, key, chain
NEW_CERT=$(jq -r '
  . | to_entries[]
  | select(.value | has("Certificates"))
  | .value.Certificates[]
  | select(.domain.main == "'"$DOMAIN"'")
  | .certificate' "$ACME_JSON" | base64 -d)

NEW_KEY=$(jq -r '
  . | to_entries[]
  | select(.value | has("Certificates"))
  | .value.Certificates[]
  | select(.domain.main == "'"$DOMAIN"'")
  | .key' "$ACME_JSON" | base64 -d)

# Optional: fullchain same as cert (Traefik's cert already includes full chain)
NEW_CHAIN="$NEW_CERT"

# Safety check
if [[ -z "$NEW_CERT" || -z "$NEW_KEY" ]]; then
  echo "❌ Error: Could not extract certificate or key for domain '$DOMAIN'."
  exit 1
fi

# Temporary files for comparison
TMP_CERT="$CERT_DIR/tmp_cert.pem"
TMP_KEY="$CERT_DIR/tmp_key.pem"
TMP_CHAIN="$CERT_DIR/tmp_chain.pem"

echo "$NEW_CERT" > "$TMP_CERT"
echo "$NEW_KEY" > "$TMP_KEY"
echo "$NEW_CHAIN" > "$TMP_CHAIN"

RESTART_NEEDED=0

# Compare and update cert
if ! cmp -s "$TMP_CERT" "$CERT_PATH"; then
  mv "$TMP_CERT" "$CERT_PATH"
  RESTART_NEEDED=1
else
  rm -f "$TMP_CERT"
fi

# Compare and update key
if ! cmp -s "$TMP_KEY" "$KEY_PATH"; then
  mv "$TMP_KEY" "$KEY_PATH"
  RESTART_NEEDED=1
else
  rm -f "$TMP_KEY"
fi

# Compare and update chain
if ! cmp -s "$TMP_CHAIN" "$CHAIN_PATH"; then
  mv "$TMP_CHAIN" "$CHAIN_PATH"
  RESTART_NEEDED=1
else
  rm -f "$TMP_CHAIN"
fi

# Set secure permissions
chmod 600 "$CERT_DIR"/*.pem

# Print cert metadata
echo "🔎 Certificate details:"
openssl x509 -in "$CERT_PATH" -noout -subject -issuer -dates

# Optional restart hook (uncomment if needed)
#if [[ $RESTART_NEEDED -eq 1 ]]; then
#  echo "🔁 TLS certs updated. Restarting mail containers..."
#  docker compose restart front
#fi

# Result
if [[ $RESTART_NEEDED -eq 1 ]]; then
  echo "✅ TLS certs updated for '$DOMAIN'."
else
  echo "✅ Certs unchanged. No update needed."
fi

exit 0
