# ============================================================
# Dockerfile for Headwind MDM (hmdm-server)
# Multi-stage build: Maven + Tomcat
# Deploy on Render using "Docker" runtime
# ============================================================

# ---- Stage 1: Build the WAR with Maven ----
FROM maven:3.8-openjdk-11-slim AS builder

WORKDIR /build

# Install required tools
RUN apt-get update && apt-get install -y \
    aapt \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy source
COPY . .

# Build the WAR (skip tests for faster build)
RUN mvn install -DskipTests

# ---- Stage 2: Run with Tomcat ----
FROM tomcat:9-jdk11-temurin-jammy

# Install required tools
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y \
        aapt \
        wget \
        sed \
        postgresql-client \
        openssl \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /usr/local/tomcat/conf/Catalina/localhost
RUN mkdir -p /usr/local/tomcat/ssl
RUN mkdir -p /usr/local/tomcat/work/cache
RUN mkdir -p /usr/local/tomcat/work/files
RUN mkdir -p /usr/local/tomcat/work/plugins
RUN mkdir -p /usr/local/tomcat/work/logs

# Copy the WAR from builder stage
COPY --from=builder /build/server/target/launcher.war /usr/local/tomcat/webapps/ROOT.war

# Copy entrypoint and templates
COPY docker-entrypoint.sh /
COPY templates /opt/hmdm/templates/
COPY tomcat_conf/server.xml /usr/local/tomcat/conf/server.xml

# Expose ports
EXPOSE 8080
EXPOSE 8443
EXPOSE 31000

ENTRYPOINT ["/docker-entrypoint.sh"]
