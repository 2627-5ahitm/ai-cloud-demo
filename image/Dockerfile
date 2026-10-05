# DevBox image: Debian + the whole toolchain baked in.
# Workloads on LeoCloud run from an image built here and pushed to ghcr.io;
# the PVC (max 2Gi) only holds projects and caches under /work.
#
#   docker buildx build --platform linux/amd64 \
#     -t ghcr.io/htl-leonding/devbox:<tag> --push image/

FROM debian:trixie-slim

ARG NODE_MAJOR=24
ARG JDK_MAJOR=21
ARG MAVEN_VERSION=3.9.16
ARG QUARKUS_VERSION=3.39.5
ARG HTTPYAC_VERSION=6.16.7
ARG PLAYWRIGHT_VERSION=1.63.0

ENV TOOLS=/opt/tools \
    JAVA_HOME=/opt/tools/jdk \
    M2_HOME=/opt/tools/maven \
    NPM_CONFIG_PREFIX=/opt/tools/npm-global \
    NPM_CONFIG_CACHE=/work/.npm \
    PLAYWRIGHT_BROWSERS_PATH=/opt/tools/ms-playwright \
    PATH=/opt/tools/node/bin:/opt/tools/npm-global/bin:/opt/tools/jdk/bin:/opt/tools/maven/bin:/opt/tools/quarkus/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    HOME=/root \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git unzip zip xz-utils tar gzip bzip2 \
      procps less vim-tiny jq openssl gnupg locales tini \
      build-essential python3 \
 && rm -rf /var/lib/apt/lists/*

# Node.js: newest release of the LTS major
RUN set -eux; \
    file=$(curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt" \
      | grep -o 'node-v[0-9.]*-linux-x64.tar.xz' | head -1); \
    mkdir -p "$TOOLS/node"; \
    curl -fsSL "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/$file" \
      | tar -xJ -C "$TOOLS/node" --strip-components=1; \
    node --version

# Eclipse Temurin JDK (LTS)
RUN set -eux; \
    mkdir -p "$JAVA_HOME"; \
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/${JDK_MAJOR}/ga/linux/x64/jdk/hotspot/normal/eclipse" \
      | tar -xz -C "$JAVA_HOME" --strip-components=1; \
    java -version

# Maven; local repository on the PVC so dependencies survive pod restarts
RUN set -eux; \
    mkdir -p "$M2_HOME"; \
    curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      | tar -xz -C "$M2_HOME" --strip-components=1; \
    sed -i 's#<!-- localRepository#<localRepository>/work/.m2/repository</localRepository>\n  <!-- localRepository#' \
      "$M2_HOME/conf/settings.xml"; \
    mvn -v

# Quarkus CLI
RUN set -eux; \
    mkdir -p "$TOOLS/quarkus"; \
    curl -fsSL "https://github.com/quarkusio/quarkus/releases/download/${QUARKUS_VERSION}/quarkus-cli-${QUARKUS_VERSION}.tar.gz" \
      | tar -xz -C "$TOOLS/quarkus" --strip-components=1; \
    quarkus --version

# httpyac, Playwright + Chromium (with its system libraries)
RUN set -eux; \
    NPM_CONFIG_CACHE=/tmp/npm-cache npm install -g --no-fund --no-audit \
      "httpyac@${HTTPYAC_VERSION}" "playwright@${PLAYWRIGHT_VERSION}" "@playwright/test@${PLAYWRIGHT_VERSION}"; \
    playwright install --with-deps chromium; \
    rm -rf /tmp/npm-cache /var/lib/apt/lists/*; \
    httpyac --version; playwright --version

RUN mkdir -p /work/projects
WORKDIR /work/projects

ENTRYPOINT ["/usr/bin/tini", "--"]
# No foreground workload: all work arrives through `kubectl exec`.
CMD ["sleep", "infinity"]
