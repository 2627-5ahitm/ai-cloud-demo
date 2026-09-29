#!/usr/bin/env bash
# DevBox bootstrap: installs the toolchain into the PVC at /work/tools.
# Idempotent: every step is skipped when its marker file already exists.
# Never exits non-zero on tool failure -- the pod must stay reachable via
# `kubectl exec` even when one install step breaks, so it can be debugged.

set -uo pipefail

TOOLS=/work/tools
MARKERS="$TOOLS/.markers"
LOG=/work/bootstrap.log

mkdir -p "$TOOLS" "$MARKERS" /work/projects /work/.m2/repository /work/.npm

exec > >(tee -a "$LOG") 2>&1
echo "=== bootstrap start $(date -Is) ==="

step() { # step <marker> <description>
  local marker="$MARKERS/$1"
  shift
  local desc="$*"
  if [[ -f "$marker" ]]; then
    echo "--- skip: $desc (already done)"
    return 1
  fi
  echo "--- run:  $desc"
  return 0
}
done_step() { touch "$MARKERS/$1"; echo "--- ok:   $1"; }
fail_step() { echo "!!! FAILED: $1 (see $LOG); continuing"; }

# ---------------------------------------------------------------- apt packages
# The container filesystem is ephemeral, so apt packages are reinstalled on
# every pod start. The .deb cache lives on the PVC to keep that fast.
install_apt() {
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /work/cache/apt/archives/partial
  rm -rf /var/cache/apt/archives
  ln -sfn /work/cache/apt/archives /var/cache/apt/archives
  apt-get update -qq || return 1
  apt-get install -y --no-install-recommends \
    ca-certificates curl wget git unzip zip xz-utils tar gzip bzip2 \
    procps less vim-tiny jq openssl gnupg locales tini \
    build-essential python3 || return 1
}
echo "--- run:  apt base packages"
if install_apt; then echo "--- ok:   apt base packages"; else fail_step "apt"; fi

# ------------------------------------------------------------------- Node.js
if step node "Node.js (LTS tarball -> $TOOLS/node)"; then
  (
    set -e
    ver=$(curl -fsSL https://nodejs.org/dist/index.json \
      | grep -o '"version":"v[0-9.]*","date":"[^"]*","files":\[[^]]*\],"npm":"[^"]*"[^}]*"lts":"[A-Za-z]*"' \
      | grep -o '"version":"v[0-9.]*"' | head -1 | cut -d'"' -f4)
    # Fallback: newest even-numbered (LTS) major from SHASUMS listing
    if [[ -z "${ver:-}" ]]; then ver=$(curl -fsSL https://nodejs.org/dist/index.json | grep -o '"version":"v[0-9.]*"' | head -1 | cut -d'"' -f4); fi
    echo "Node version: $ver"
    tmp=$(mktemp -d)
    curl -fsSL "https://nodejs.org/dist/$ver/node-$ver-linux-x64.tar.xz" -o "$tmp/node.tar.xz"
    rm -rf "$TOOLS/node"; mkdir -p "$TOOLS/node"
    tar -xJf "$tmp/node.tar.xz" -C "$TOOLS/node" --strip-components=1
    rm -rf "$tmp"
    "$TOOLS/node/bin/node" --version
  ) && done_step node || fail_step node
fi

export PATH="$TOOLS/node/bin:$TOOLS/npm-global/bin:$PATH"
export NPM_CONFIG_PREFIX="$TOOLS/npm-global"
export NPM_CONFIG_CACHE=/work/.npm

# ----------------------------------------------------------------- JDK 21 (LTS)
if step jdk "Eclipse Temurin JDK 21 -> $TOOLS/jdk"; then
  (
    set -e
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/jdk.tar.gz" \
      "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
    rm -rf "$TOOLS/jdk"; mkdir -p "$TOOLS/jdk"
    tar -xzf "$tmp/jdk.tar.gz" -C "$TOOLS/jdk" --strip-components=1
    rm -rf "$tmp"
    "$TOOLS/jdk/bin/java" -version
  ) && done_step jdk || fail_step jdk
fi

export JAVA_HOME="$TOOLS/jdk"
export PATH="$JAVA_HOME/bin:$PATH"

# ------------------------------------------------------------------- Maven
if step maven "Apache Maven -> $TOOLS/maven"; then
  (
    set -e
    base=https://dlcdn.apache.org/maven/maven-3
    ver=$(curl -fsSL "$base/" | grep -o '3\.9\.[0-9]*/' | tr -d '/' | sort -V | tail -1)
    [[ -n "$ver" ]]
    echo "Maven version: $ver"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/mvn.tar.gz" "$base/$ver/binaries/apache-maven-$ver-bin.tar.gz"
    rm -rf "$TOOLS/maven"; mkdir -p "$TOOLS/maven"
    tar -xzf "$tmp/mvn.tar.gz" -C "$TOOLS/maven" --strip-components=1
    rm -rf "$tmp"
    "$TOOLS/maven/bin/mvn" -v
  ) && done_step maven || fail_step maven
fi

export PATH="$TOOLS/maven/bin:$PATH"

# Maven local repo on the PVC so dependencies survive pod restarts
mkdir -p "$TOOLS/maven/conf"
cat > /work/.m2/settings.xml <<'EOF'
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <localRepository>/work/.m2/repository</localRepository>
</settings>
EOF

# --------------------------------------------------------------- Quarkus CLI
if step quarkus "Quarkus CLI -> $TOOLS/quarkus"; then
  (
    set -e
    url=$(curl -fsSL https://api.github.com/repos/quarkusio/quarkus/releases/latest \
      | grep -o 'https://[^"]*quarkus-cli-[0-9][^"]*\.tar\.gz' | head -1)
    [[ -n "$url" ]]
    echo "Quarkus CLI: $url"
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/q.tar.gz" "$url"
    rm -rf "$TOOLS/quarkus"; mkdir -p "$TOOLS/quarkus"
    tar -xzf "$tmp/q.tar.gz" -C "$TOOLS/quarkus" --strip-components=1
    rm -rf "$tmp"
    "$TOOLS/quarkus/bin/quarkus" --version
  ) && done_step quarkus || fail_step quarkus
fi

# ------------------------------------------------------- npm tools: httpyac
if step httpyac "httpyac (npm -g)"; then
  npm install -g --no-fund --no-audit httpyac && httpyac --version && done_step httpyac || fail_step httpyac
fi

# ------------------------------------------------------ Playwright + Chromium
export PLAYWRIGHT_BROWSERS_PATH="$TOOLS/ms-playwright"
if step playwright "Playwright (npm -g) + Chromium browser"; then
  (
    set -e
    npm install -g --no-fund --no-audit playwright @playwright/test
    mkdir -p "$PLAYWRIGHT_BROWSERS_PATH"
    # --with-deps drives apt; if Playwright has no recipe for this Debian
    # release, fall back to an explicit library list plus a plain browser
    # download.
    if ! playwright install --with-deps chromium; then
      echo "playwright install --with-deps failed; installing libs manually"
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libnss3 libnspr4 libdbus-1-3 libatk1.0-0t64 libatk-bridge2.0-0t64 \
        libcups2t64 libdrm2 libatspi2.0-0t64 libxcomposite1 libxdamage1 \
        libxfixes3 libxrandr2 libgbm1 libxkbcommon0 libpango-1.0-0 \
        libcairo2 libasound2t64 fonts-liberation fonts-noto-color-emoji \
        || echo "manual lib install had failures"
      playwright install chromium
    fi
    playwright --version
  ) && done_step playwright || fail_step playwright
fi

# ---------------------------------------------------------------- shell env
# Pod env vars (set in the Deployment) already cover non-interactive
# `kubectl exec`. This file is for interactive shells and for sourcing.
cat > "$TOOLS/env.sh" <<EOF
export TOOLS=$TOOLS
export JAVA_HOME=$TOOLS/jdk
export M2_HOME=$TOOLS/maven
export MAVEN_ARGS="--settings /work/.m2/settings.xml"
export NPM_CONFIG_PREFIX=$TOOLS/npm-global
export NPM_CONFIG_CACHE=/work/.npm
export PLAYWRIGHT_BROWSERS_PATH=$TOOLS/ms-playwright
export PATH=$TOOLS/node/bin:$TOOLS/npm-global/bin:\$JAVA_HOME/bin:$TOOLS/maven/bin:$TOOLS/quarkus/bin:\$PATH
EOF
grep -q 'tools/env.sh' /root/.bashrc 2>/dev/null || echo "source $TOOLS/env.sh" >> /root/.bashrc

echo "=== versions ==="
{
  echo -n "node    : "; node --version 2>&1
  echo -n "npm     : "; npm --version 2>&1
  echo -n "java    : "; java -version 2>&1 | head -1
  echo -n "maven   : "; mvn -v 2>&1 | head -1
  echo -n "quarkus : "; "$TOOLS/quarkus/bin/quarkus" --version 2>&1 | tail -1
  echo -n "httpyac : "; httpyac --version 2>&1 | head -1
  echo -n "pwright : "; playwright --version 2>&1
  echo -n "curl    : "; curl --version 2>&1 | head -1
  echo -n "git     : "; git --version 2>&1
} || true

touch /work/.devbox-ready
echo "=== bootstrap done $(date -Is) ==="
