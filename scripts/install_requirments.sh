#!/usr/bin/env bash
# install_requirements.sh
# Run this script (with sudo) on a fresh Ubuntu system
# to install the packages needed for the monitoring project.

set -euo pipefail

echo "=== Monitoring Project: Installing system requirements ==="

# Check for root (we need sudo / root to install packages)
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script with sudo, e.g.:"
  echo "  sudo ./scripts/install_requirements.sh"
  exit 1
fi

echo "[1/3] Updating package lists..."
apt update -y

echo "[2/3] Installing required packages..."
# mailutils : provides the 'mail' command used in alert.sh
# net-tools : provides ifconfig/netstat (mentioned in the project outline)
# cron      : ensures cron is available for scheduling
apt install -y mailutils net-tools cron

echo "[3/3] Enabling and starting cron service (if not already running)..."
systemctl enable cron || true
systemctl start cron || true

echo "=== Done. Requirements installed successfully. ==="
echo "You can now run the monitoring scripts."
