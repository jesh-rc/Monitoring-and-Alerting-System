#!/usr/bin/env bash
set -euo pipefail

# Determine project base directory
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Directory to store state files (network counters, CPU window, etc.)
STATE_DIR="$BASE_DIR/var/state"
mkdir -p "$STATE_DIR"

# Path to log file
LOG_FILE="$BASE_DIR/var/log/monitor.log"

# Timestamp
timestamp="$(date -Iseconds)"

# --------------------------------------------------------------------
# CPU usage (%)
# --------------------------------------------------------------------
# We use `top` in batch mode (-b) with one iteration (-n1).
# It prints a line like:
#   Cpu(s):  3.2 us,  1.0 sy,  0.0 ni, 95.2 id, ...
# We grab the "id" (idle) value and do: 100 - idle = usage.
cpu_pct=$(
  top -bn1 | awk '
    /Cpu\(s\)/ {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /id,/) {
          idle = $(i-1)
          gsub(",", "", idle)
          usage = 100 - idle
          printf("%d\n", usage)
          exit
        }
      }
    }
  '
)

# --------------------------------------------------------------------
# Memory usage (%)
# --------------------------------------------------------------------
# `free -m` prints a line like:
#   Mem:   total   used   free  ...
# We compute: (used / total) * 100
mem_pct=$(
  free -m | awk '/Mem:/ { printf("%d\n", ($3 / $2) * 100) }'
)

# --------------------------------------------------------------------
# Disk usage for the root filesystem (/)
# --------------------------------------------------------------------
# `df -P /` prints:
#   Filesystem  1K-blocks  Used  Available Use% Mounted on
# We take the 5th column (Use%), remove the '%' and use that number.
disk_root_pct=$(
  df -P / | awk 'NR==2 { gsub("%","",$5); print $5 }'
)

# --------------------------------------------------------------------
# Network usage (approximate KB/s) using /proc/net/dev
# --------------------------------------------------------------------
# Idea:
#   - Read RX/TX byte counters for the main (non-lo) interface from /proc/net/dev.
#   - Compare with the previous counters stored in var/state/net_prev.
#   - Compute (delta_bytes / delta_time) -> bytes/sec, then convert to KB/s.
#
# This gives a rough "throughput since last run" for one interface.

NET_STATE_FILE="$STATE_DIR/net_prev"

# Get current interface + byte counters
read net_iface cur_rx_bytes cur_tx_bytes < <(
  awk '
    NR>2 {
      gsub(":", "", $1);      # remove trailing colon from iface
      iface = $1;
      rx = $2;                # receive bytes
      tx = $10;               # transmit bytes
      if (iface != "lo") {
        print iface, rx, tx;
        exit;                 # take the first non-lo interface
      }
    }
  ' /proc/net/dev
)

# If we didn't get anything, fall back to zeros
if [ -z "${net_iface:-}" ]; then
  net_iface="none"
  cur_rx_bytes=0
  cur_tx_bytes=0
fi

now_ts=$(date +%s)

net_rx_kbps=0
net_tx_kbps=0

# If we have previous values, compute deltas
if [ -f "$NET_STATE_FILE" ]; then
  # File format: <timestamp> <rx_bytes> <tx_bytes> <iface>
  read prev_ts prev_rx prev_tx prev_iface < "$NET_STATE_FILE" || {
    prev_ts=0
    prev_rx=0
    prev_tx=0
    prev_iface="$net_iface"
  }

  dt=$(( now_ts - prev_ts ))
  if [ "$dt" -gt 0 ]; then
    # Handle counter resets or changes
    if [ "$cur_rx_bytes" -ge "$prev_rx" ] && [ "$cur_tx_bytes" -ge "$prev_tx" ]; then
      delta_rx=$(( cur_rx_bytes - prev_rx ))
      delta_tx=$(( cur_tx_bytes - prev_tx ))

      # bytes/sec = delta_bytes / dt
      # KB/sec (approx) = bytes/sec / 1024
      net_rx_kbps=$(( (delta_rx / dt) / 1024 ))
      net_tx_kbps=$(( (delta_tx / dt) / 1024 ))
    else
      # Counters reset; keep usage at 0 for this interval
      net_rx_kbps=0
      net_tx_kbps=0
    fi
  fi
fi

# Save current counters for next run
echo "$now_ts $cur_rx_bytes $cur_tx_bytes $net_iface" > "$NET_STATE_FILE"

# --------------------------------------------------------------------
# Save CPU values to a small rolling window for anomaly detection later
# --------------------------------------------------------------------
cpu_window="$STATE_DIR/cpu.window"
echo "$cpu_pct" >> "$cpu_window"
tail -n 10 "$cpu_window" > "${cpu_window}.tmp" && mv "${cpu_window}.tmp" "$cpu_window"

# --------------------------------------------------------------------
# Write a single metrics line to the log
# --------------------------------------------------------------------
echo "$timestamp METRICS cpu=$cpu_pct mem=$mem_pct disk_root=$disk_root_pct net_rx=$net_rx_kbps net_tx=$net_tx_kbps" >> "$LOG_FILE"

exit 0
