#!/bin/sh
# Headwind MDM Docker entrypoint
# Configures the application from environment variables and starts Tomcat
# Designed for Render (SSL terminated at Render's edge)

set -e

TEMPLATE_DIR=/opt/hmdm/templates
TOMCAT_DIR=/usr/local/tomcat
BASE_DIR=$TOMCAT_DIR/work

# Ensure base directories exist
for DIR in cache files plugins logs; do
   [ -d "$BASE_DIR/$DIR" ] || mkdir -p "$BASE_DIR/$DIR"
done

# Create Tomcat config directory
mkdir -p "$TOMCAT_DIR/conf/Catalina/localhost"

# Set defaults for optional variables
: "${SQL_HOST:=localhost}"
: "${SQL_PORT:=5432}"
: "${SQL_BASE:=hmdm}"
: "${SQL_USER:=hmdm}"
: "${SQL_PASS:=hmdm}"
: "${PROTOCOL:=http}"
: "${BASE_DOMAIN:=localhost}"
: "${SHARED_SECRET:=changeme-C3z9vi54}"
: "${JDBC_SSLMODE:=require}"
: "${CATALINA_OPTS:=-Xmx192m -Xms96m -XX:MaxMetaspaceSize=48m -Xss256k -XX:+UseSerialGC}"

# Import Aiven CA certificate into Java truststore (if mounted)
CA_CERT_PATH="/opt/aiven/ca-certificate.pem"
JAVA_HOME="${JAVA_HOME:-/opt/java/openjdk}"
TRUSTSTORE="$JAVA_HOME/lib/security/cacerts"
TRUSTSTORE_PASS="${TRUSTSTORE_PASS:-changeit}"

if [ -f "$CA_CERT_PATH" ]; then
    keytool -list -keystore "$TRUSTSTORE" -storepass "$TRUSTSTORE_PASS" -alias aiven-ca > /dev/null 2>&1 || {
        echo "Importing Aiven CA certificate into Java truststore..."
        keytool -importcert -noprompt \
            -keystore "$TRUSTSTORE" \
            -storepass "$TRUSTSTORE_PASS" \
            -alias aiven-ca \
            -file "$CA_CERT_PATH"
        echo "Aiven CA certificate imported successfully."
    }
fi

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL at $SQL_HOST:$SQL_PORT..."
until PGPASSWORD=$SQL_PASS psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -c '\q' 2>/dev/null; do
  echo "PostgreSQL not ready yet, retrying in 5 seconds..."
  sleep 5
done
echo "PostgreSQL is ready!"

# Configure Tomcat context from environment variables using template
# Escape special characters in variables for safe sed use
SQL_PASS_ESC=$(echo "$SQL_PASS" | sed 's|[|&\\/]|\\&|g')
SQL_USER_ESC=$(echo "$SQL_USER" | sed 's|[|&\\/]|\\&|g')
SHARED_SECRET_ESC=$(echo "$SHARED_SECRET" | sed 's|[|&\\/]|\\&|g')
BASE_DOMAIN_ESC=$(echo "$BASE_DOMAIN" | sed 's|[|&\\/]|\\&|g')
SQL_HOST_ESC=$(echo "$SQL_HOST" | sed 's|[|&\\/]|\\&|g')
SQL_BASE_ESC=$(echo "$SQL_BASE" | sed 's|[|&\\/]|\\&|g')

sed \
    -e "s|_SQL_HOST_|$SQL_HOST_ESC|g" \
    -e "s|_SQL_PORT_|$SQL_PORT|g" \
    -e "s|_SQL_BASE_|$SQL_BASE_ESC|g" \
    -e "s|_SQL_USER_|$SQL_USER_ESC|g" \
    -e "s|_SQL_PASS_|$SQL_PASS_ESC|g" \
    -e "s|_PROTOCOL_|$PROTOCOL|g" \
    -e "s|_BASE_DOMAIN_|$BASE_DOMAIN_ESC|g" \
    -e "s|_SHARED_SECRET_|$SHARED_SECRET_ESC|g" \
    -e "s|_JDBC_SSLMODE_|$JDBC_SSLMODE|g" \
    $TEMPLATE_DIR/conf/context_template.xml \
    > $TOMCAT_DIR/conf/Catalina/localhost/ROOT.xml

# Copy log4j config
if [ ! -f "$BASE_DIR/log4j-hmdm.xml" ]; then
    cp $TEMPLATE_DIR/conf/log4j_template.xml $BASE_DIR/log4j-hmdm.xml
fi

# Copy email templates
if [ -d "$TEMPLATE_DIR/emails" ] && [ ! -d "$BASE_DIR/emails" ]; then
    cp -r $TEMPLATE_DIR/emails $BASE_DIR/emails
fi

# Fix random number generation delay (speeds up Tomcat startup)
if [ -f /opt/java/openjdk/conf/security/java.security ]; then
    sed -i 's|securerandom.source=file:/dev/random|securerandom.source=file:/dev/urandom|g' \
        /opt/java/openjdk/conf/security/java.security 2>/dev/null || true
fi

# CATALINA_OPTS: already set above with default; export it for Tomcat
export CATALINA_OPTS

echo "========================================"
echo "Headwind MDM starting..."
echo "Database: $SQL_HOST:$SQL_PORT/$SQL_BASE"
echo "Protocol: $PROTOCOL"
echo "Domain:   $BASE_DOMAIN"
echo "JVM:      $CATALINA_OPTS"
echo "========================================"

# Start Tomcat in foreground
catalina.sh run
