# Monitoring & Alerting System  
SOFE 3200 – System Programming  

---

# 1. Project Overview

This project implements a modular **system monitoring and alerting tool** in Bash.  
It collects system metrics, evaluates them against configurable thresholds, checks services, logs results, and sends alerts when issues are detected.  
The system can run manually or automatically through cron.

---

# 2. Features

## Resource Monitoring
- CPU usage
- Memory usage
- Disk usage
- Network throughput (RX/TX)
- Rolling window CPU history for anomaly detection

## Service Monitoring
Checks services listed in `etc/services.conf` using `systemctl`.

## Alerting
- Writes issue reports to `var/state/last_issues.txt`
- Logs all events to `var/log/monitor.log`
- Sends alert emails through Gmail SMTP

## Configurable Thresholds
Defined in `etc/thresholds.conf`.

## Scheduling
Can run continuously via cron.

---

# 3. Project Structure

```
.
├── README.md
├── main.sh
├── bin/
│   ├── collect_data.sh
│   ├── detect_issues.sh
│   └── alert.sh
├── etc/
│   ├── thresholds.conf
│   └── services.conf
├── cron/
│   └── monitoring.cron
├── scripts/
│   └── install_requirements.sh
└── var/
    ├── log/
    └── state/
```

---

# 4. Requirements

This system requires:

- Bash
- Postfix + mailutils (for email alerts)
- Standard Linux tools (top, free, df, awk, sed, etc.)
- cron (optional for scheduling)

The included installer handles everything.

---

# 5. Installation

Run the included installer:

```bash
cd scripts
sudo ./install_requirements.sh
```

This installs:

- mailutils  
- postfix  
- cron  
- sysstat  
- net-tools  
- jq, bc, lsof, curl, etc.

# 6. Gmail SMTP Configuration (Required for Email Alerts)

To enable email alerts:

1. Enable 2-Factor Authentication in Gmail  
2. Generate an App Password  
3. Edit `sudo nano /etc/postfix/sasl_passwd`:

```
[smtp.gmail.com]:587 your_email@gmail.com:YOUR_APP_PASSWORD
```

4. Secure and activate:

```bash
sudo chmod 600 /etc/postfix/sasl_passwd
sudo postmap /etc/postfix/sasl_passwd
sudo systemctl restart postfix
```

Test email:

```bash
echo "test" | mail -s "test" your_email@gmail.com
```

---

# 7. Configuration

## Thresholds
Edit:

```
etc/thresholds.conf
```

Example:

```
CPU_PCT_WARN=85
CPU_PCT_CRIT=90
MEM_PCT_WARN=80
MEM_PCT_CRIT=95
```

## Services
Edit:

```
etc/services.conf
```

Example:

```
apache2
mysql
nginx
ssh
```

---

# 8. Running the System Manually

```bash
./main.sh
```

Outputs include:

- Start of cycle  
- Metrics  
- Detected issues  
- Alerts sent  
- End of cycle  

Logs:
```
var/log/monitor.log
```

State:
```
var/state/last_issues.txt
```

---

# 9. Running Automatically with Cron

Edit the crontab:

```bash
crontab -e
```

Add:

```
* * * * * /path/to/main.sh >> /path/to/var/log/cron.log 2>&1
```

Verify:

```bash
systemctl status cron
```

View cron output:

```bash
tail -n 20 var/log/cron.log
```

---

# 10. Script Responsibilities

## main.sh
Controls the full monitoring pipeline.

## collect_data.sh
Gathers system metrics and writes log entries.

## detect_issues.sh
Compares metrics and service states against thresholds.  
Outputs issues and sets exit codes appropriately.

## alert.sh
Logs alert messages and sends email using postfix.

---

# 11. Logs and State

### Logs
```
var/log/monitor.log
var/log/cron.log
```

### State Files
```
var/state/cpu.window
var/state/net_prev
var/state/last_issues.txt
```

These persist data between monitoring cycles.

---

# 12. Troubleshooting

## No Email Received
- Check `/var/log/mail.log`
- Confirm postfix is using Gmail relay
- Confirm App Password is correct
- Ensure `relayhost = [smtp.gmail.com]:587` is set
- Ensure `default_transport` and `relay_transport` are NOT set to “error”

## Cron Not Running
- Ensure cron is installed and enabled

## Permission Errors
Make scripts executable:

```bash
chmod -R +x .
```

---

# 13. Notes

- The project is fully modular and can be extended with SMS or webhook-based alerts.
- No further file changes are required to run the system.


