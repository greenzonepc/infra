#!/bin/sh
set -e

DOMAIN="${DOMAIN:?DOMAIN is required}"
EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL is required}"
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"

# Cloudflare DNS-01 credentials. The operator-supplied secret is mounted
# read-only at /cloudflare.ini; copy it into the persistent letsencrypt volume
# with strict permissions so renewals find it and certbot doesn't warn.
CF_CREDS_SRC="/cloudflare.ini"
CF_CREDS="/etc/letsencrypt/cloudflare.ini"

if [ ! -f "${CF_CREDS_SRC}" ]; then
    echo "[certbot] ERROR: ${CF_CREDS_SRC} not found. Create certbot/cloudflare.ini with your Cloudflare API token." >&2
    exit 1
fi
install -m 600 "${CF_CREDS_SRC}" "${CF_CREDS}"

make_placeholder() {
    # Self-signed cert so nginx's HTTPS server block can load before the real
    # certificate exists. Short lived on purpose.
    mkdir -p "${LIVE_DIR}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 7 \
        -keyout "${LIVE_DIR}/privkey.pem" \
        -out "${LIVE_DIR}/fullchain.pem" \
        -subj "/CN=${DOMAIN}" >/dev/null 2>&1
}

obtain_cert() {
    certbot certonly --dns-cloudflare \
        --dns-cloudflare-credentials "${CF_CREDS}" \
        --dns-cloudflare-propagation-seconds 30 \
        -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --email "${EMAIL}" --agree-tos --no-eff-email \
        --non-interactive --keep-until-expiring
}

if [ -f "${RENEWAL_CONF}" ]; then
    echo "[certbot] Existing Let's Encrypt certificate found for ${DOMAIN}"
else
    echo "[certbot] Requesting Let's Encrypt certificate for ${DOMAIN} via Cloudflare DNS-01"
    if obtain_cert; then
        echo "[certbot] Certificate obtained; nginx will start with the real certificate"
    else
        echo "[certbot] Request failed; creating self-signed placeholder so nginx can still start"
        make_placeholder
    fi
fi

trap exit TERM INT
echo "[certbot] Entering renewal loop (checking every 12h)"
while :; do
    sleep 12h
    echo "[certbot] Running certbot renew"
    certbot renew --quiet || true
done
