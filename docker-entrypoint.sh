#!/bin/sh
# Headwind MDM Docker entrypoint
# Configures the application from environment variables and starts Tomcat

set -e

HMDM_DIR=/opt/hmdm
TEMPLATE_DIR=$HMDM_DIR/templates
TOMCAT_DIR=/usr/local/tomcat
BASE_DIR=$TOMCAT_DIR/work
PASSWORD=123456

# Ensure base directories exist
for DIR in cache files plugins logs; do
   [ -d "$BASE_DIR/$DIR" ] || mkdir -p "$BASE_DIR/$DIR"
done

# Create Tomcat config directory
if [ ! -d "$TOMCAT_DIR/conf/Catalina/localhost" ]; then
    mkdir -p "$TOMCAT_DIR/conf/Catalina/localhost"
fi

# Configure from environment variables using template
cat $TEMPLATE_DIR/conf/context_template.xml | \
    sed "s|_SQL_HOST_|${SQL_HOST:-localhost}|g; \
         s|_SQL_PORT_|${SQL_PORT:-5432}|g; \
         s|_SQL_BASE_|${SQL_BASE:-hmdm}|g; \
         s|_SQL_USER_|${SQL_USER:-hmdm}|g; \
         s|_SQL_PASS_|${SQL_PASS:-hmdm}|g; \
         s|_PROTOCOL_|${PROTOCOL:-http}|g; \
         s|_BASE_DOMAIN_|${BASE_DOMAIN:-localhost}|g; \
         s|_SHARED_SECRET_|${SHARED_SECRET:-changeme-C3z9vi54}|g" \
    > $TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml

# Copy log4j config
if [ ! -f "$BASE_DIR/log4j-hmdm.xml" ]; then
    cp $TEMPLATE_DIR/conf/log4j_template.xml $BASE_DIR/log4j-hmdm.xml
fi

# Copy email templates if they exist
if [ -d "$TEMPLATE_DIR/emails" ] && [ ! -d "$BASE_DIR/emails" ]; then
    cp -r $TEMPLATE_DIR/emails $BASE_DIR/emails
fi

# Handle SSL if HTTPS is enabled
if [ "$PROTOCOL" = "https" ] && [ -n "$BASE_DOMAIN" ]; then
    if [ "$HTTPS_LETSENCRYPT" = "true" ] && [ -d "/etc/letsencrypt/live/$BASE_DOMAIN" ]; then
        HTTPS_CERT_PATH="/etc/letsencrypt/live/$BASE_DOMAIN"
        echo "Using Let's Encrypt certificates from $HTTPS_CERT_PATH..."
    elif [ -n "$HTTPS_CERT_PATH" ]; then
        echo "Using custom certificates from $HTTPS_CERT_PATH..."
    fi

    if [ -n "$HTTPS_CERT_PATH" ] && [ -f "$HTTPS_CERT_PATH/$HTTPS_PRIVKEY" ]; then
        echo "Generating JKS keystore from certificates..."
        openssl pkcs12 -export \
            -out $TOMCAT_DIR/ssl/hmdm.p12 \
            -inkey $HTTPS_CERT_PATH/${HTTPS_PRIVKEY:-privkey.pem} \
            -in $HTTPS_CERT_PATH/${HTTPS_CERT:-cert.pem} \
            -certfile $HTTPS_CERT_PATH/${HTTPS_FULLCHAIN:-fullchain.pem} \
            -password pass:$PASSWORD 2>/dev/null
        keytool -importkeystore \
            -destkeystore $TOMCAT_DIR/ssl/hmdm.jks \
            -srckeystore $TOMCAT_DIR/ssl/hmdm.p12 \
            -srcstoretype PKCS12 \
            -srcstorepass $PASSWORD \
            -deststorepass $PASSWORD \
            -noprompt 2>/dev/null
    fi
fi

# Fix random number generation delay
if [ -f /opt/java/openjdk/conf/security/java.security ]; then
    sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/urandom|g' \
        /opt/java/openjdk/conf/security/java.security 2>/dev/null || true
fi

echo "========================================"
echo "Headwind MDM starting..."
echo "Database: $SQL_HOST:$SQL_PORT/$SQL_BASE"
echo "Protocol: $PROTOCOL"
echo "Domain:   ${BASE_DOMAIN:-not set}"
echo "========================================"

# Start Tomcat
catalina.sh run
