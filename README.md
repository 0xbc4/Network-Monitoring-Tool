# Network Monitoring Tool

A PowerShell-based infrastructure monitoring solution for tracking IP reachability, device availability, and alert conditions across networked systems.

## Overview

This project continuously checks whether configured devices are reachable over the network and raises alerts when failures or recoveries are detected. It is designed for environments that need basic but reliable uptime monitoring without requiring a heavy third-party platform.

The tool currently supports:

- ICMP-based health checks
- Device status tracking
- Alert and recovery logic
- Email notification support through SMTP
- Safe test mode to prevent noisy alerts during validation
- Daily logging and reporting
- Runtime configuration reload without restarting the script

## Current Status

This repository is currently in alpha stage and is tagged as:

- v0.1.0-alpha

The project is intentionally positioned as a practical test and validation release before the beta iteration, where the monitoring logic, alert pipeline, and Linux deployment model will be hardened further.

## Features

### Network Monitoring

- Continuous device availability checks
- Configurable polling interval
- Retries and delay handling
- Device enable/disable control
- Critical versus warning device classification
- Live dashboard for active monitoring status

### Alerting and Recovery

- Alert notifications for unreachable devices
- Recovery notifications when a device becomes reachable again
- Multiple recipient support
- Flexible notification modes:
  - disabled
  - stdout
  - test-safe
  - smtp

### Logging and Reporting

- Daily log files
- Alert and recovery event history
- CSV-compatible reporting structure
- Support for reporting and auditing in operational scenarios

### Security and Configuration

- SMTP credentials stored using encrypted local XML files
- Config values separated from script logic
- Runtime reload support for recipients and devices
- Safe testing mode to prevent accidental production alerts during validation

## Repository Structure

```text
Network Monitoring Tool/
├── NetworkMonitor.ps1
├── Setup-SMTP Credentials.ps1
├── config.json
├── servers.json
├── README.md
├── LICENSE
├── docs/
│   ├── RELEASE_NOTES.md
│   └── BETA_ROADMAP.md
├── Logs/
├── Reports/
└── test-env/
```

## Quick Start

### 1. Configure the environment

Update the values in [config.json](config.json) and [servers.json](servers.json) for your deployment.

### 2. Create the encrypted SMTP credential file

```powershell
.\Setup-SMTP Credentials.ps1
```

This creates a local encrypted XML credential file used by the monitoring script.

### 3. Start the monitoring tool

```powershell
.\NetworkMonitor.ps1
```

For a single non-interactive check (useful for Task Scheduler and validation), run:

```powershell
.\NetworkMonitor.ps1 -Once -NoDashboard
```

### 4. Validate in safe mode

The project is currently configured to use a safe no-noise validation mode by default, which suppresses real alert delivery while allowing monitoring behavior to be tested safely.

## Configuration

The project reads its runtime configuration from JSON files so key settings remain external to the script logic.

### Example config

```json
{
  "NotificationMode": "test-safe",
  "AlertTransport": "smtp",
  "SecureEmailMode": "disabled",
  "SmtpServer": "smtp.example.com",
  "SmtpPort": 587,
  "LogFolder": "Logs",
  "ReportFolder": "Reports",
  "CredentialFile": "smtp_cred.xml",
  "CheckIntervalSeconds": 60,
  "RetryCount": 3,
  "RetryDelaySeconds": 1,
  "Recipients": [
    { "Email": "admin@example.com", "Enabled": true },
    { "Email": "ops@example.com", "Enabled": true }
  ]
}
```

### Example device list

```json
{
  "Devices": [
    {
      "Name": "Example-Server-01",
      "IP": "192.168.1.10",
      "Enabled": true,
      "Critical": true
    }
  ]
}
```

## Alert Modes

The notification layer supports several modes depending on deployment stage:

- disabled: notifications are turned off
- stdout: notifications are printed to console output
- test-safe: validation mode that suppresses actual alerts while preserving visibility in logs
- smtp: production alert delivery through SMTP credentials

## Security Notes

- SMTP credentials are saved locally as encrypted XML files
- No plaintext credentials should be committed to the repository
- Production IP ranges and internal hostnames should remain outside public source control
- The safe test mode is recommended before enabling real delivery in production
- Relative log, report, and credential paths are resolved from the project folder; absolute paths remain supported.

## Operational Notes

- The monitoring script is built for Windows-first PowerShell environments
- The project is being prepared for a future Linux and systemd-oriented deployment model
- The current alpha release focuses on stability and safe validation flows rather than full production alert transport

## Documentation

- [Release Notes](docs/RELEASE_NOTES.md)
- [Beta Roadmap](docs/BETA_ROADMAP.md)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact and Notes

This project is intended to evolve from a testable alpha prototype into a more hardened beta version with stronger security, reporting, automation, and Linux compatibility.
