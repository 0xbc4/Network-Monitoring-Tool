# Camera Server Monitoring

PowerShell-based monitoring and alerting solution for network devices and servers.

## Overview

This project monitors infrastructure devices using ICMP ping checks and sends notifications when devices become unreachable.

The solution provides:

- Availability monitoring
- Email alerting
- Recovery notifications
- Daily logging
- Alarm history reporting
- Secure SMTP credential storage
- Centralized configuration management

## Features

### Monitoring

- Continuous device health monitoring
- Configurable monitoring interval
- Configurable retry attempts
- Multiple device support
- Device enable/disable capability

### Alerting

- Critical outage notifications
- Warning notifications
- Recovery notifications
- Multiple recipients support

### Security

- SMTP credentials stored using Windows DPAPI encryption
- No plain-text passwords in source code

### Logging

- Daily log files
- Connection failure logging
- Recovery logging
- SMTP error logging

### Reporting

- CSV-based alarm history
- UP/DOWN event tracking
- Excel-compatible reporting structure

## Folder Structure

```text
Camera Server Monitoring
├── CameraServers-Check.ps1
├── Setup-SMTP Credentials.ps1
├── config.json
├── servers.json
├── README.md
├── Logs/
└── Reports/
```

## Installation and Setup

Follow these steps in order before running the monitoring service.

1. Edit the values in `config.json` and `servers.json` for your environment.
2. Run `Setup-SMTP Credentials.ps1` once to create the encrypted SMTP credential file.
3. Confirm that `smtp_cred.xml` was generated successfully.
4. Run `CameraServers-Check.ps1` to start monitoring.

```powershell
# 1) Create the encrypted SMTP credential file
.\Setup-SMTP Credentials.ps1

# 2) Start the monitoring loop
.\CameraServers-Check.ps1
```

> Important: Run the SMTP setup script before the main monitor. The monitor loads the encrypted credential file from `config.json` to send email alerts.

## Configuration

The project reads settings from JSON files so deployment details stay outside the script source.

Example `config.json`:

```json
{
  "SmtpServer": "smtp.example.com",
  "SmtpPort": 587,
  "LogFolder": "C:\\Monitoring\\Logs",
  "ReportFolder": "C:\\Monitoring\\Reports",
  "CredentialFile": "C:\\Monitoring\\smtp_cred.xml",
  "CheckIntervalSeconds": 60,
  "RetryCount": 3,
  "RetryDelaySeconds": 1,
  "Recipients": [
    { "Email": "admin@example.com", "Enabled": true },
    { "Email": "ops@example.com", "Enabled": true }
  ]
}
```

Example `servers.json`:

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

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Notes

- Replace the sample values and paths before running in a real environment.
- The encrypted credential file is created locally with the setup script.
- Do not commit real SMTP credentials, production IPs, or internal hostnames.
