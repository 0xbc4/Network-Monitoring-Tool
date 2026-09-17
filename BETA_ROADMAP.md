# Beta Roadmap

## Goal
Transform the current alpha monitoring prototype into a more resilient beta-grade product with better operational safety, cleaner alert transport, and broader deployment readiness.

## Planned Beta Scope

### 1. Production-safe notification flow
- Replace direct SMTP dependency assumptions with a cleaner abstraction layer
- Add explicit modes for:
  - disabled
  - stdout
  - test-safe
  - smtp
- Validate SMTP delivery only after credential and recipient checks

### 2. Linux and service readiness
- Prepare the project for Linux-compatible execution using PowerShell Core
- Define runtime directories and writable paths for logs and reports
- Design a systemd service unit for daemon-style monitoring
- Validate permission and file ownership requirements

### 3. Configuration hardening
- Improve config validation before runtime execution
- Add schema checks for missing fields and invalid values
- Standardize log and report paths across environments
- Separate production and test configuration profiles more clearly

### 4. Alert quality and operational controls
- Add rate limiting and suppression windows for repeated alerts
- Improve recovery logic and status transition tracking
- Reduce duplicate alert noise in unstable conditions
- Add clearer audit trails for device events

### 5. Reporting improvements
- Add structured export formats for historical incidents
- Improve CSV and log readability for operator review
- Introduce time-based summaries and outage windows

## Beta Milestones

### Milestone 1: Safe validation
- Stable alert logic in test-safe mode
- Correct runtime reload behavior
- Reliable dashboard and device tracking output

### Milestone 2: Hardened transport
- Verified SMTP delivery path
- Controlled notification mode switching
- Full validation of recipient and credential flow

### Milestone 3: Linux deployment readiness
- PowerShell Core compatibility checks
- systemd startup and service packaging
- Secure configuration injection path

### Milestone 4: Beta release candidate
- Stable production behavior under test conditions
- Documentation and operational runbook complete
- Release notes and upgrade guidance finalized

## Proposed Beta Version
- v0.5.0-beta

## Recommended Release Gate
The project should move to beta only after the following conditions are met:
- alert suppression and SMTP delivery are both tested intentionally
- configuration reload is validated in live sessions
- log/report paths work in both Windows and Linux-style layouts
- service lifecycle and restart behavior are verified

## Recommendation
The current alpha stage is useful for proving the concept and validating core monitoring behavior. The beta stage should focus on security, automation, and operational clarity before broader production adoption.
