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

# True only when a real (CA-issued, not self-signed) certificate is present.
# The placeholder is self-signed, so its issuer equals its subject.
cert_is_real() {
    [ -f "${LIVE_DIR}/fullchain.pem" ] || return 1
    _issuer=$(openssl x509 -in "${LIVE_DIR}/fullchain.pem" -noout -issuer 2>/dev/null) || return 1
    _subject=$(openssl x509 -in "${LIVE_DIR}/fullchain.pem" -noout -subject 2>/dev/null) || return 1
    [ -n "${_issuer}" ] && [ "${_issuer}" != "${_subject}" ]
}

obtain_cert() {
    certbot certonly --dns-cloudflare \
        --dns-cloudflare-credentials "${CF_CREDS}" \
        --dns-cloudflare-propagation-seconds 30 \
        --cert-name "${DOMAIN}" \
        -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --email "${EMAIL}" --agree-tos --no-eff-email \
        --non-interactive --keep-until-expiring
}

if cert_is_real; then
    echo "[certbot] Existing Let's Encrypt certificate found for ${DOMAIN}"
else
    # Only a placeholder, a broken lineage, or nothing exists. Wipe any partial
    # state for this domain so certbot can write a clean lineage.
    rm -rf "${LIVE_DIR}" "/etc/letsencrypt/archive/${DOMAIN}" "${RENEWAL_CONF}"
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
