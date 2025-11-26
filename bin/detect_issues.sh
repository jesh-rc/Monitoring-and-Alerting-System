#!/usr/bin/env bash

set -euo pipefail

# -------------------------

# Paths / constants

# -------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$BASE_DIR/var/log/monitor.log"
THRESHOLDS_FILE="$BASE_DIR/etc/thresholds.conf"
SERVICES_FILE="$BASE_DIR/etc/services.conf"
STATE_DIR="$BASE_DIR/var/state"
ISSUE_FILE="$STATE_DIR/last_issues.txt"

# Helper: append timestamped message to both main log and issue file (if provided)
log() {
  echo "$(date -Iseconds) [DETECT] $*" | tee -a "$LOG_FILE"
}

# Helper: write a single issue line to the ISSUE_FILE and main log
record_issue() {
  echo "$(date -Iseconds) $*" | tee -a "$LOG_FILE" >> "$ISSUE_FILE"
}

# -------------------------
# Validate required files
# -------------------------
if [ ! -f "$THRESHOLDS_FILE" ]; then
  log "ERROR: thresholds file not found at $THRESHOLDS_FILE"
  exit 2
fi


source "$THRESHOLDS_FILE"

# clear (truncate) issue file at start of run to avoid stale entries
: > "$ISSUE_FILE"

# -------------------------
# Fetch the most recent METRICS line
# -------------------------
last_metrics_line=$(grep " METRICS " "$LOG_FILE" 2>/dev/null | tail -n 1 || true)

if [ -z "$last_metrics_line" ]; then
  log "No METRICS line found in $LOG_FILE; nothing to analyze."
  # Nothing wrong, just no data yet
  exit 0
fi

# Extract fields; default to 0 if not found
cpu_val=$(echo "$last_metrics_line" | sed -n 's/.*cpu=\([0-9]\+\).*/\1/p' || echo "0")
mem_val=$(echo "$last_metrics_line" | sed -n 's/.*mem=\([0-9]\+\).*/\1/p' || echo "0")
disk_root_val=$(echo "$last_metrics_line" | sed -n 's/.*disk_root=\([0-9]\+\).*/\1/p' || echo "0")
net_rx_val=$(echo "$last_metrics_line" | sed -n 's/.*net_rx=\([0-9]\+\).*/\1/p' || echo "0")
net_tx_val=$(echo "$last_metrics_line" | sed -n 's/.*net_tx=\([0-9]\+\).*/\1/p' || echo "0")

# Convert to integers (in case of empty)
cpu_val=${cpu_val:-0}
mem_val=${mem_val:-0}
disk_root_val=${disk_root_val:-0}
net_rx_val=${net_rx_val:-0}
net_tx_val=${net_tx_val:-0}

# Flag indicates if we found any issue
issues_found=0

# -------------------------

# Threshold checks

# -------------------------
# For each metric, we check configured threshold variables (if set).
# If a threshold variable is not set, we skip that check.

# CPU checks (warn / crit)
if [ -n "${CPU_PCT_CRIT:-}" ]; then
  if [ "$cpu_val" -gt "$CPU_PCT_CRIT" ]; then
    record_issue "CRITICAL: CPU=${cpu_val}% > CPU_PCT_CRIT=${CPU_PCT_CRIT}"
    issues_found=1
  fi
fi

if [ -n "${CPU_PCT_WARN:-}" ]; then
  if [ "$cpu_val" -gt "$CPU_PCT_WARN" ]; then
    record_issue "WARNING: CPU=${cpu_val}% > CPU_PCT_WARN=${CPU_PCT_WARN}"
    issues_found=1
  fi
fi

# Memory check
if [ -n "${MEM_PCT_CRIT:-}" ]; then
  if [ "$mem_val" -gt "$MEM_PCT_CRIT" ]; then
    record_issue "CRITICAL: MEM=${mem_val}% > MEM_PCT_CRIT=${MEM_PCT_CRIT}"
    issues_found=1
  fi
fi

# Disk root (/) check
if [ -n "${DISK_ROOT_PCT_CRIT:-}" ]; then
  if [ "$disk_root_val" -gt "$DISK_ROOT_PCT_CRIT" ]; then
    record_issue "CRITICAL: DISK_ROOT=${disk_root_val}% > DISK_ROOT_PCT_CRIT=${DISK_ROOT_PCT_CRIT}"
    issues_found=1
  fi
fi

# Network checks (if configured)
if [ -n "${NET_RX_KBPS_CRIT:-}" ] && [ "$net_rx_val" -gt "$NET_RX_KBPS_CRIT" ]; then
  record_issue "CRITICAL: NET_RX=${net_rx_val} kbps > NET_RX_KBPS_CRIT=${NET_RX_KBPS_CRIT}"
  issues_found=1
fi
if [ -n "${NET_TX_KBPS_CRIT:-}" ] && [ "$net_tx_val" -gt "$NET_TX_KBPS_CRIT" ]; then
  record_issue "CRITICAL: NET_TX=${net_tx_val} kbps > NET_TX_KBPS_CRIT=${NET_TX_KBPS_CRIT}"
  issues_found=1
fi


# -------------------------

# Simple anomaly detection (lightweight)

# -------------------------
# We keep a small rolling window (populated by collect_data.sh into var/state/cpu.window)
# If there are at least ANOMALY_WINDOW entries, compute a simple average of previous values
# (excluding current). If current > avg * ANOMALY_MULTIPLIER, flag an anomaly.
cpu_window_file="$STATE_DIR/cpu.window"
if [ -f "$cpu_window_file" ]; then
  # default window size and multiplier if not set in thresholds.conf
  ANOMALY_WINDOW="${ANOMALY_WINDOW:-8}"
  ANOMALY_MULTIPLIER="${ANOMALY_MULTIPLIER:-1.5}"

  count=$(wc -l < "$cpu_window_file" || echo 0)
  if [ "$count" -ge 5 ]; then
    # compute average of previous values (exclude the last line — assume last is current)
    # if the file includes the current value already, exclude it by taking head -n (count-1)
    prev_count=$((count - 1))
    if [ "$prev_count" -gt 0 ]; then
      prev_avg=$(head -n "$prev_count" "$cpu_window_file" | awk '{sum+=$1} END { if (NR>0) print int(sum/NR); else print 0 }')
      # calculate threshold = prev_avg * ANOMALY_MULTIPLIER (rounded down)
      # To avoid floating math, use awk
      threshold=$(awk -v avg="$prev_avg" -v m="$ANOMALY_MULTIPLIER" 'BEGIN{printf("%d", avg * m)}')
      if [ "$prev_avg" -gt 0 ] && [ "$cpu_val" -gt "$threshold" ]; then
        record_issue "ANOMALY: CPU=${cpu_val}% >> prev_avg=${prev_avg}%, threshold=${threshold}% (mult=${ANOMALY_MULTIPLIER})"
        issues_found=1
      fi
    fi
  fi
fi

# -------------------------

# Service health checks

# -------------------------
# Read each service name from etc/services.conf and test with systemctl.
# If systemctl says not active, record a CRITICAL issue.
if [ -f "$SERVICES_FILE" ]; then
  while IFS= read -r svc_line || [ -n "$svc_line" ]; do
    svc=$(echo "$svc_line" | sed 's/#.*//' | xargs)  # remove comments & trim
    [ -z "$svc" ] && continue

    if systemctl is-active --quiet "$svc"; then
      # service OK; optionally log at DEBUG level (comment/uncomment if needed)
      echo "$(date -Iseconds) [DETECT] Service '$svc' is active." >> "$LOG_FILE"
    else
      record_issue "CRITICAL: Service '$svc' is NOT active"
      issues_found=1
    fi
  done < "$SERVICES_FILE"
else
  # services file missing is not fatal; we just skip service checks, but log it
  log "Note: services config file not found at $SERVICES_FILE — skipping service checks."
fi

# -------------------------

# Finalize and exit

# -------------------------
if [ "$issues_found" -eq 1 ]; then
  log "Issues detected; details written to $ISSUE_FILE"
  exit 1
else
  # ensure issue file is empty (no stale data) and exit OK
  : > "$ISSUE_FILE"
  log "No issues detected."
  exit 0
fi
