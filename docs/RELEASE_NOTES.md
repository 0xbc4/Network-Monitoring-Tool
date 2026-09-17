# Release Notes

## v0.1.1-alpha

### Highlights
- Added validation for configuration files, notification modes, device entries, and polling values.
- Made log, report, and credential paths portable by resolving relative paths from the project folder.
- Allowed `test-safe`, `stdout`, and `disabled` notification modes to run without SMTP credentials.
- Added `-Once` and `-NoDashboard` options for scheduled and non-interactive checks.
- Prevented the device-management Back action from blocking while it rechecks every enabled device.
- Added a configurable ICMP timeout through `PingTimeoutMilliseconds`.

### Upgrade Notes
- Add `"PingTimeoutMilliseconds": 1000` to existing configuration files.
- The default configuration now uses project-relative `Logs`, `Reports`, and `smtp_cred.xml` paths.

## v0.1.0-alpha

### Overview
This is the first alpha release of the Network Monitoring Tool. The goal of this version is to provide a working network monitoring foundation for validation, testing, and safe operational review.

### Included Features
- ICMP-based reachability checks
- Device availability tracking
- Critical and warning classification
- Recovery detection logic
- SMTP notification flow abstraction
- Safe notification mode for validation
- Daily logging and reporting support
- Runtime config reload support
- Live dashboard status output

### Security and Operational Notes
- SMTP credentials are stored in encrypted local XML form
- Real email sending is intentionally suppressed in the safe test mode
- Production environments should validate SMTP configuration before enabling real alerting

### Known Limitations
- Windows-first PowerShell implementation
- SMTP transport is still directly coupled to a local credential workflow
- Linux/systemd packaging and secure production notification transport are planned for the next release stage
- Some operational hardening is still pending for large-scale production deployment

### Upgrade Guidance
Use this version for:
- internal validation
- environment testing
- alert logic verification
- previewing monitoring behavior before production rollout

Do not enable full production alerting until SMTP configuration, recipient validation, and delivery paths have been verified in a controlled environment.
