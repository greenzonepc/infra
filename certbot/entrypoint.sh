#!/bin/sh
set -e

DOMAIN="${DOMAIN:?DOMAIN is required}"
EMAIL="${CERTBOT_EMAIL:?CERTBOT_EMAIL is required}"
LIVE_DIR="/etc/letsencrypt/live/${DOMAIN}"
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
WEBROOT="/var/www/certbot"

mkdir -p "${WEBROOT}"

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
    certbot certonly --webroot -w "${WEBROOT}" \
        -d "${DOMAIN}" -d "www.${DOMAIN}" \
        --email "${EMAIL}" --agree-tos --no-eff-email \
        --non-interactive --keep-until-expiring
}

if [ -f "${RENEWAL_CONF}" ]; then
    echo "[certbot] Existing Let's Encrypt certificate found for ${DOMAIN}"
else
    echo "[certbot] No managed certificate; creating self-signed placeholder so nginx can start"
    make_placeholder

    # Once nginx is up and serving the ACME challenge, swap in a real certificate.
    (
        sleep 15
        echo "[certbot] Requesting Let's Encrypt certificate for ${DOMAIN}"
        # The placeholder occupies the lineage path; remove it so certbot writes
        # a clean ${DOMAIN} lineage instead of ${DOMAIN}-0001.
        rm -rf "${LIVE_DIR}" "/etc/letsencrypt/archive/${DOMAIN}" "${RENEWAL_CONF}"
        if obtain_cert; then
            echo "[certbot] Certificate obtained; nginx will pick it up on its next reload"
        else
            echo "[certbot] Certificate request failed; restoring self-signed placeholder"
            make_placeholder
        fi
    ) &
fi

trap exit TERM INT
echo "[certbot] Entering renewal loop (checking every 12h)"
while :; do
    sleep 12h
    echo "[certbot] Running certbot renew"
    certbot renew --quiet || true
done
