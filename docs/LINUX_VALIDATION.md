# Linux Validation Record

## Scope

The cross-platform monitoring path was validated on a Linux x86_64 virtual
machine with PowerShell 7.6.2.

## Test Performed

The project was copied to a temporary directory and run with:

```bash
pwsh -NoProfile -File ./NetworkMonitor.ps1 -Once -NoDashboard
```

The test used the repository's `test-safe` notification mode. No SMTP
credentials, SMTP delivery, production device details, or host access details
were used or recorded.

## Result

- The monitor completed successfully with exit code `0`.
- ICMP checks ran through the platform-neutral .NET implementation.
- Relative `Logs` and `Reports` directories were created successfully.
- Test-safe notifications were logged without attempting email delivery.

## Not Covered

- Production SMTP delivery with environment-provided credentials.
- Installation and lifecycle verification of the systemd service unit.

Those checks remain deployment-specific and should be performed using a
dedicated non-production SMTP account and an approved Linux service account.
