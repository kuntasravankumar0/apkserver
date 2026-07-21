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

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL at $SQL_HOST:$SQL_PORT..."
until PGPASSWORD=$SQL_PASS psql -h "$SQL_HOST" -p "$SQL_PORT" -U "$SQL_USER" -d "$SQL_BASE" -c '\q' 2>/dev/null; do
  echo "PostgreSQL not ready yet, retrying in 5 seconds..."
  sleep 5
done
echo "PostgreSQL is ready!"

# Configure Tomcat context from environment variables using template
sed \
    -e "s|_SQL_HOST_|$SQL_HOST|g" \
    -e "s|_SQL_PORT_|$SQL_PORT|g" \
    -e "s|_SQL_BASE_|$SQL_BASE|g" \
    -e "s|_SQL_USER_|$SQL_USER|g" \
    -e "s|_SQL_PASS_|$SQL_PASS|g" \
    -e "s|_PROTOCOL_|$PROTOCOL|g" \
    -e "s|_BASE_DOMAIN_|$BASE_DOMAIN|g" \
    -e "s|_SHARED_SECRET_|$SHARED_SECRET|g" \
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

# Limit JVM memory for Render's 512MB free tier
# Without these limits, Java+Tomcat exceeds 512MB and gets OOM-killed
# Aggressive memory limits for Render's 512MB free tier
# Total estimated usage: 192MB heap + 48MB metaspace + ~40MB JVM + ~50MB native + ~100MB OS = ~430MB
# This leaves ~80MB headroom within the 512MB limit
export CATALINA_OPTS="-Xmx192m -Xms96m -XX:MaxMetaspaceSize=48m -Xss256k -XX:+UseSerialGC"

echo "========================================"
echo "Headwind MDM starting..."
echo "Database: $SQL_HOST:$SQL_PORT/$SQL_BASE"
echo "Protocol: $PROTOCOL"
echo "Domain:   $BASE_DOMAIN"
echo "JVM:      $CATALINA_OPTS"
echo "========================================"

# Start Tomcat in foreground
catalina.sh run
