FROM certbot/dns-cloudflare

# openssl is needed to generate the temporary self-signed placeholder certificate
# that lets nginx start before the real Let's Encrypt certificate is issued.
RUN apk add --no-cache openssl
