# IMPORTANT:
# This script creates the encrypted SMTP credential file locally.
# The XML file contains your email username/password in an encrypted Windows format,
# so it should never be committed to GitHub or shared with others.
$credFile = Join-Path $PSScriptRoot "smtp_cred.xml" # Path to the credential file

if (-not (Test-Path $credFile)) {

    Write-Host "SMTP credential file not found." -ForegroundColor Yellow

    $cred = Get-Credential

    $cred | Export-Clixml $credFile

    Write-Host "Credential file created." -ForegroundColor Green
}

$credential = Import-Clixml $credFile 
