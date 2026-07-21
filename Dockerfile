# ============================================================
# Dockerfile for Headwind MDM (hmdm-server)
# Multi-stage build: Maven build + Tomcat runtime
# Designed for Render (SSL terminated at Render's edge)
# ============================================================

# ---- Stage 1: Build the WAR with Maven ----
FROM maven:3.8-openjdk-11-slim AS builder

WORKDIR /build

# Install aapt (Android Asset Packaging Tool)
RUN apt-get update && apt-get install -y \
    aapt \
    && rm -rf /var/lib/apt/lists/*

# Copy pom.xml files first for dependency caching
COPY pom.xml .
COPY common/pom.xml common/
COPY jwt/pom.xml jwt/
COPY notification/pom.xml notification/
COPY swagger/ui/pom.xml swagger/ui/
COPY plugins/pom.xml plugins/
COPY server/pom.xml server/

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B || true

# Copy source code
COPY common common/
COPY jwt jwt/
COPY notification notification/
COPY swagger swagger/
COPY plugins plugins/
COPY server server/
COPY install install/

# Copy build.properties from example (file is gitignored but needed for Maven)
RUN cp server/build.properties.example server/build.properties

# Skip frontend grunt build (frontend resources already in repo under src/main/webapp/)
# The grunt 'resolve' task fails in Docker due to missing dependencies
RUN sed -i 's|<phase>generate-resources</phase>|<phase>none</phase>|' server/pom.xml

# Build the WAR (skip tests for faster builds)
RUN mvn install -DskipTests -B

# ---- Stage 2: Run with Tomcat (minimal runtime) ----
FROM tomcat:9-jdk11-temurin-jammy

# Install runtime dependencies
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
        aapt \
        wget \
        curl \
        postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Create required directories
RUN mkdir -p /usr/local/tomcat/conf/Catalina/localhost \
    /usr/local/tomcat/work/cache \
    /usr/local/tomcat/work/files \
    /usr/local/tomcat/work/plugins \
    /usr/local/tomcat/work/logs

# Copy the WAR from the builder stage
COPY --from=builder /build/server/target/launcher.war /usr/local/tomcat/webapps/ROOT.war

# Copy entrypoint and configuration templates
COPY docker-entrypoint.sh /
COPY templates /opt/hmdm/templates/

# Expose port (Render handles SSL termination at the edge)
EXPOSE 8080

# Health check for Render
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD curl --fail http://localhost:8080/ || exit 1

ENTRYPOINT ["/docker-entrypoint.sh"]
