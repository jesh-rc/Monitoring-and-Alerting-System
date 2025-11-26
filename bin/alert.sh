#!/usr/bin/env bash


# --------------------------------------------------------------------
# Make the script stricter/safer
# --------------------------------------------------------------------
set -euo pipefail

# --------------------------------------------------------------------
# Figure out important paths
# --------------------------------------------------------------------
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LOG_FILE="$BASE_DIR/var/log/monitor.log"

ISSUE_FILE="${1:-$BASE_DIR/var/state/last_issues.txt}"

# --------------------------------------------------------------------
# Configure email address
# --------------------------------------------------------------------
#MAIL_TO="YOUR_EMAIL@gmail.com"
SUBJECT="Monitoring Alert from $(hostname)"

# --------------------------------------------------------------------
# Helper logging function for alert-related messages
# --------------------------------------------------------------------
log_alert() {
  echo "$(date -Iseconds) [ALERT] $*" | tee -a "$LOG_FILE"
}

# --------------------------------------------------------------------
# Check for issues to send alert about
# --------------------------------------------------------------------
if [ ! -s "$ISSUE_FILE" ]; then
  # -s checks that file exists and is not empty
  log_alert "No issue details found in $ISSUE_FILE; nothing to alert."
  exit 0
fi

log_alert "Issues detected. Preparing to send alert."
log_alert "Alert details (from $ISSUE_FILE):"

# Log each issue line so it also appears in monitor.log
while IFS= read -r line; do
  log_alert "  $line"
done < "$ISSUE_FILE"

# --------------------------------------------------------------------
# Try to send email using the 'mail' command
# --------------------------------------------------------------------
if command -v mail >/dev/null 2>&1; then
  # Send the contents of ISSUE_FILE as the email body.
  if mail -s "$SUBJECT" "$MAIL_TO" < "$ISSUE_FILE"; then
    log_alert "Alert email sent to $MAIL_TO."
  else
    log_alert "WARNING: Failed to send alert email using 'mail'."
  fi
else
  log_alert "WARNING: 'mail' command not found; alert logged only (no email sent)."
fi

exit 0
