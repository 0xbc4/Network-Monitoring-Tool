param(
    [string]$UsernameVariable = "NETWORK_MONITOR_SMTP_USERNAME",
    [string]$PasswordVariable = "NETWORK_MONITOR_SMTP_PASSWORD"
)

# The monitor reads SMTP credentials from environment variables. This avoids
# Windows DPAPI/CLIXML files, which cannot be shared with Linux hosts.
$credential = Get-Credential -Message "Enter the SMTP account credentials"

if ($IsWindows -or $env:OS -eq "Windows_NT") {
    [Environment]::SetEnvironmentVariable($UsernameVariable, $credential.UserName, "User")
    [Environment]::SetEnvironmentVariable($PasswordVariable, $credential.GetNetworkCredential().Password, "User")
    Write-Host "SMTP variables were saved for the current Windows user. Open a new PowerShell session before starting the monitor." -ForegroundColor Green
}
else {
    Write-Host "Credentials were not written to disk on Linux." -ForegroundColor Yellow
    Write-Host "For an interactive session, set the variables before starting the monitor:" -ForegroundColor Yellow
    Write-Host "`$env:$UsernameVariable = '$($credential.UserName)'"
    Write-Host "`$env:$PasswordVariable = '<password>'"
    Write-Host "For systemd, place them in /etc/network-monitor/smtp.env with permissions 600." -ForegroundColor Yellow
}
