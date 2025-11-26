#!/usr/bin/env bash
# install_requirements.sh
# Install ALL required packages for the Monitoring & Alerting System project.

set -euo pipefail

echo "=== Monitoring Project: Installing FULL system requirements ==="

# Require root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo, e.g.:"
  echo "  sudo ./scripts/install_requirements.sh"
  exit 1
fi

echo "[1/5] Updating package lists..."
apt update -y

echo "[2/5] Installing core monitoring tools..."
apt install -y \
    htop \
    sysstat \
    net-tools \
    lsof \
    curl \
    bc \
    jq

echo "[3/5] Installing mail support (mailutils + postfix)..."

# mailutils → provides `mail` command  
# postfix   → actually sends mail (needed for Gmail relaying tests)
# Choose "Local Only" when prompted or press ENTER for defaults
DEBIAN_FRONTEND=noninteractive apt install -y mailutils postfix

echo "[4/5] Installing cron (scheduler)..."
apt install -y cron
systemctl enable cron || true
systemctl start cron || true

echo "[5/5] Installing service-checking tools..."
apt install -y \
    systemd \
    procps \
    psmisc

echo "=== All requirements installed successfully! ==="
echo "System is ready for the Monitoring & Alerting System project."
