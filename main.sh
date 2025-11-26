#!/usr/bin/env bash

set -euo pipefail
SCRIPT_PATH="${BASH_SOURCE[0]}"

# Determine the project base directory
BASE_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

# --------------------------------------------------------------------

# Path to the log file we will use for high level logs
LOG_FILE="$BASE_DIR/var/log/monitor.log"

# --------------------------------------------------------------------

# Helper function for logging
# log message will prepend timestamp and MAIN tag, and append to the main log file
log() {
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [MAIN] $*" | tee -a "$LOG_FILE"
}

# --------------------------------------------------------------------

# Start of the monitoring cycle
log "===== Monitoring cycle start ====="

# --------------------------------------------------------------------

# Collect and log system metrics using collect_data.sh
if ! "$BASE_DIR/bin/collect_data.sh"; then
    log "ERROR: collect_data.sh failed."
    exit 2
fi

# --------------------------------------------------------------------

# Detect issues using detect_issues.sh
if "$BASE_DIR/bin/detect_issues.sh"; then
  # Exit code 0 -> everything is fine
  log "No issues detected."
  log "===== Monitoring cycle end (OK) ====="
  exit 0
else
  # Non-zero exit code. Capture it to decide what to do.
  rc=$?

  if [ "$rc" -eq 1 ]; then
    # rc == 1 means issues were detected and we should alert.
    log "Issues detected – triggering alert."

# --------------------------------------------------------------------

# Send alert usinmg alert.sh
"$BASE_DIR/bin/alert.sh" "$BASE_DIR/var/state/last_issues.txt" || \
    log "ERROR: alert.sh failed."

log "===== Monitoring cycle end (ALERT) ====="
  else
    # Any other non-zero code (2, 3, ...) is treated as an internal error.
    log "ERROR: detect_issues.sh failed with code $rc."
    log "===== Monitoring cycle end (ERROR) ====="
    exit 2
  fi
fi
