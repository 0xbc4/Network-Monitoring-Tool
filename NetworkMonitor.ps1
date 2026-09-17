# ==========================================
# Configuration Loading
# ==========================================
# IMPORTANT:
# - The script reads its runtime settings from JSON files in the same folder.
# - Keep config.json and servers.json outside the repo if they contain production data.
# - Do not commit real SMTP credentials, internal hostnames, or production IP ranges.
$configFile = Join-Path $PSScriptRoot "config.json"  # Path to the configuration file
$serverFile = Join-Path $PSScriptRoot "servers.json" # Path to the server list file


if (-not (Test-Path $configFile)) {
    Write-Host "Configuration file not found: $configFile" -ForegroundColor Red
    exit
}


if (-not (Test-Path $serverFile)) {
    Write-Host "Server file not found: $serverFile" -ForegroundColor Red
    exit
}






$config = Get-Content $configFile -Raw | ConvertFrom-Json
$servers = Get-Content $serverFile -Raw | ConvertFrom-Json




# ==========================================
# Global Variables
# ==========================================
# These values are loaded once and reused by all monitoring functions.
# The script keeps the last known state for each device so it can detect transitions
# from UP -> DOWN and DOWN -> UP without sending duplicate alerts.
$global:serverStatus = @{}
$global:dashboardStatus = @{}
$script:notificationMode = if ($config.NotificationMode) { $config.NotificationMode } else { "smtp" }


$script:recipients = @(
    $config.Recipients |
    Where-Object { $_.Enabled -eq $true } |
    ForEach-Object { $_.Email }
)
$script:smtpServer = $config.SmtpServer
$script:smtpPort = $config.SmtpPort


# SMTP credentials are loaded from an encrypted XML file created locally.
# This keeps passwords out of the source code and prevents accidental commits.
$credential = Import-Clixml $config.CredentialFile
$username = $credential.UserName


$global:ipAddresses = @(
    $servers.Devices |
    Where-Object { $_.Enabled -eq $true }
)


$lastAlert = "None"




# ==========================================
# Folder Initialization
# ==========================================


$reportFolder = $config.ReportFolder




if (-not (Test-Path $reportFolder)) {
    New-Item -Path $reportFolder -ItemType Directory -Force | Out-Null
}


$csvFile = Join-Path $reportFolder "AlarmHistory.csv"


$logFolder = $config.LogFolder


if (-not (Test-Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
}


$logFile = Join-Path $logFolder "IPMonitor_$(Get-Date -Format 'yyyyMMdd').txt"






# ==========================================
# Functions
# ==========================================


function Write-LogEntry {
    param(
        [string]$Message
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp - $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line -ForegroundColor DarkGray
}

function Send-NotificationMessage {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$DeviceName,
        [string]$DeviceIP
    )

    $mode = if ($script:config -and $script:config.NotificationMode) { $script:config.NotificationMode } else { "smtp" }

    switch ($mode) {
        "disabled" {
            Write-Host "[NOTIFY] Disabled for $DeviceName ($DeviceIP)" -ForegroundColor Yellow
            return
        }
        "stdout" {
            Write-Host "[NOTIFY] $Subject" -ForegroundColor Cyan
            Write-Host $Body -ForegroundColor DarkCyan
            return
        }
        "test-safe" {
            Write-Host "[TEST SAFE MODE] Notification suppressed for $DeviceName ($DeviceIP)" -ForegroundColor Yellow
            Write-LogEntry "NOTIFICATION SUPPRESSED - $DeviceName ($DeviceIP) - $Subject"
            return
        }
        default {
            try {
                Send-MailMessage `
                    -From $script:username `
                    -To $script:recipients `
                    -Subject $Subject `
                    -Body $Body `
                    -SmtpServer $script:smtpServer `
                    -Port $script:smtpPort `
                    -UseSsl `
                    -Credential $script:credential `
                    -ErrorAction Stop
            }
            catch {
                $errorMessage = "MAIL ERROR - $DeviceName ($DeviceIP) - $($_.Exception.Message)"
                Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $errorMessage" -ForegroundColor Red
                Write-LogEntry $errorMessage
            }
        }
    }
}

function Send-AlertMail {
    param (
        [string]$Name,
        [string]$IP,
        [bool]$Critical
    )

    if ($script:notificationMode -eq "test-safe") {
        Write-Host "[TEST SAFE MODE] Alert suppressed for $Name ($IP)" -ForegroundColor Yellow
        Write-LogEntry "ALERT SUPPRESSED - $Name ($IP) - $(if ($Critical) { '[CRITICAL]' } else { '[WARNING]' })"
        return
    }

    if ($Critical) {
        $subject = "[CRITICAL] $Name Unreachable"
    }
    else {
        $subject = "[WARNING] $Name Unreachable"
    }


    $body = @"
Alert generated by IP Monitor


Server Name : $Name
IP Address  : $IP
Status      : Unreachable
Date        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')


Please check the device.
"@

    Send-NotificationMessage -Subject $subject -Body $body -DeviceName $Name -DeviceIP $IP
}








function Send-RecoveryMail {
    param (
        [string]$Name,
        [string]$IP
    )

    if ($script:notificationMode -eq "test-safe") {
        Write-Host "[TEST SAFE MODE] Recovery suppressed for $Name ($IP)" -ForegroundColor Yellow
        Write-LogEntry "RECOVERY SUPPRESSED - $Name ($IP)"
        return
    }

    $body = @"
Recovery generated by IP Monitor


Server Name : $Name
IP Address  : $IP
Status      : Reachable Again
Date        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@

    Send-NotificationMessage -Subject "[RECOVERY] $Name Reachable Again" -Body $body -DeviceName $Name -DeviceIP $IP
}








function Write-AlarmHistory {
    param(
        [string]$Name,
        [string]$IP,
        [string]$Status
    )


    $record = [PSCustomObject]@{
        DateTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Device   = $Name
        IP       = $IP
        Status   = $Status
    }


    if (Test-Path $csvFile) {
        $record | Export-Csv -Path $csvFile -NoTypeInformation -Append
    }
    else {
        $record | Export-Csv -Path $csvFile -NoTypeInformation
    }
}








function Test-IPAvailability {
    param(
        [string]$IP
    )


    for ($i = 1; $i -le $config.RetryCount; $i++) {


        try {


            $reply = Test-Connection `
                -ComputerName $IP `
                -Count 1 `
                -ErrorAction Stop


            return @{
                Success = $true
                Latency = $reply.ResponseTime
            }
        }
        catch {


            Start-Sleep -Seconds $config.RetryDelaySeconds
        }
    }


    return @{
        Success = $false
        Latency = $null
    }
}




function Test-IPConnection {
    param (
        [string]$ip,
        [string]$name,
        [bool]$critical
    )

    # Device health check logic:
    # - If a device is reachable, update status to UP
    # - If it was previously DOWN, send a recovery email and log the event
    # - If a device is unreachable, record the DOWN state and send alert only once
    #   until the next recovery occurs.
    $result = Test-IPAvailability -IP $ip

    $ping = $result.Success
    $latency = $result.Latency


    if ($ping) {

        $global:dashboardStatus[$ip] = @{
            Name      = $name
            IP        = $ip
            Status    = "UP"
            Latency   = if ($null -ne $latency) {
                "$latency ms"
            }
            else {
                "N/A"
            }
            Critical  = $critical
            LastCheck = Get-Date
            DownSince = $null
        }

        if ($global:serverStatus[$ip] -eq $false) {
            Send-RecoveryMail -Name $name -IP $ip

            $global:lastAlert = "$name recovered"

            $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DEVICE RECOVERED - $name ($ip) is reachable again."
            Add-Content -Path $logFile -Value $logMessage

            Write-AlarmHistory `
                -Name $name `
                -IP $ip `
                -Status "UP"

            $global:serverStatus[$ip] = $true
        }

        $global:serverStatus[$ip] = $true
    }
    else {

        # Preserve the initial DOWN timestamp so the outage duration remains accurate.
        if (
            $global:dashboardStatus.ContainsKey($ip) -and
            $global:dashboardStatus[$ip].Status -eq "DOWN" -and
            $null -ne $global:dashboardStatus[$ip].DownSince
        ) {
            $downSince = $global:dashboardStatus[$ip].DownSince
        }
        else {
            $downSince = Get-Date
        }

        $global:dashboardStatus[$ip] = @{
            Name      = $name
            IP        = $ip
            Status    = "DOWN"
            Latency   = "N/A"
            Critical  = $critical
            LastCheck = Get-Date
            DownSince = $downSince
        }

        if (-not $global:serverStatus.ContainsKey($ip) -or $global:serverStatus[$ip] -eq $true) {
            $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - DEVICE DOWN - $name ($ip) is not accessible."
            Add-Content -Path $logFile -Value $logMessage

            Send-AlertMail `
                -Name $name `
                -IP $ip `
                -Critical $critical

            $global:lastAlert = "$name unreachable"

            Write-AlarmHistory `
                -Name $name `
                -IP $ip `
                -Status "DOWN"

            $global:serverStatus[$ip] = $false
        }
    }
}




function Update-Dashboard {

    Clear-Host

    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host "           Network Monitoring Tool" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan

    $totalDevices = @($global:ipAddresses).Count

    $upCount = @(
        $global:dashboardStatus.Values |
        Where-Object { $_.Status -eq "UP" }
    ).Count

    $downDevices = @(
        $global:dashboardStatus.Values |
        Where-Object { $_.Status -eq "DOWN" }
    )

    $downCount = $downDevices.Count

    Write-Host ""
    Write-Host "Device Count : $totalDevices"
    Write-Host "UP           : " -NoNewline
    Write-Host "$upCount" -ForegroundColor Green

    Write-Host "DOWN         : " -NoNewline

    if ($downCount -gt 0) {
        Write-Host "$downCount" -ForegroundColor Red
    }
    else {
        Write-Host "$downCount" -ForegroundColor Green
    }

    Write-Host ""

    if ($downCount -gt 0) {

        Write-Host "--------------------------------------------------------"
        Write-Host "DOWN DEVICES" -ForegroundColor Red
        Write-Host "--------------------------------------------------------"

        Write-Host ("-" * 75)

        foreach ($device in ($downDevices | Sort-Object Name)) {

            Write-Host (
                "{0,-25} {1,-18} {2,-10} {3,-20}" -f `
                $device.Name,
                $device.IP,
                $device.Critical,
                $device.LastCheck.ToString("HH:mm:ss")
            ) -ForegroundColor Red
        }
    }
    else {

        Write-Host "--------------------------------------------------------"
        Write-Host "ALL DEVICES ARE UP" -ForegroundColor Green
        Write-Host "--------------------------------------------------------"
    }

    Write-Host ""
    Write-Host "Last Alert : $lastAlert" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "[1] Live Dashboard" -ForegroundColor Cyan
}

function Show-DeviceManagement {

    while ($true) {

        Clear-Host

        Write-Host "=== Device Management ===" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "[1] Add Device" -ForegroundColor Green
        Write-Host "[2] Edit Device" -ForegroundColor Yellow
        Write-Host "[3] Enable / Disable Device" -ForegroundColor Magenta
        Write-Host "[4] Delete Device" -ForegroundColor Red
        Write-Host "[0] Back" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {

            # ==========================================
            # ADD DEVICE
            # ==========================================

            '1' {

                Clear-Host

                Write-Host "=== Add New Device ===" -ForegroundColor Cyan
                Write-Host ""

                $name = Read-Host "Device Name"
                $ip = Read-Host "IP Address"

                try {
                    [System.Net.IPAddress]::Parse($ip) | Out-Null
                }
                catch {
                    Write-Host ""
                    Write-Host "Invalid IP address." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                if (@($servers.Devices | Where-Object {
                    $_.IP -eq $ip
                }).Count -gt 0) {

                    Write-Host ""
                    Write-Host "A device with this IP already exists." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                if (@($servers.Devices | Where-Object {
                    $_.Name -eq $name
                }).Count -gt 0) {

                    Write-Host ""
                    Write-Host "A device with this name already exists." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $criticalInput = Read-Host "Critical Device? (Y/N)"

                $critical = $criticalInput.ToUpper() -eq "Y"

                $newDevice = [PSCustomObject]@{
                    Name     = $name
                    IP       = $ip
                    Enabled  = $true
                    Critical = $critical
                }

                $servers.Devices += $newDevice

                $servers |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $serverFile -Encoding UTF8

                Write-Host ""
                Write-Host "Device added successfully." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # ==========================================
            # EDIT DEVICE
            # ==========================================

            '2' {

                Clear-Host

                Write-Host "=== Edit Device ===" -ForegroundColor Cyan
                Write-Host ""

                $devices = @($servers.Devices)

                if ($devices.Count -eq 0) {

                    Write-Host "No devices found." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    continue
                }

                for ($i = 0; $i -lt $devices.Count; $i++) {

                    $status = if ($devices[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($devices[$i].Name) - $($devices[$i].IP) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back" -ForegroundColor Cyan
                Write-Host ""

                $selection = Read-Host "Select device"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $devices.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $device = $devices[$index]

                Clear-Host

                Write-Host "=== Edit Device ===" -ForegroundColor Cyan
                Write-Host ""

                Write-Host "Current Name     : $($device.Name)"
                Write-Host "Current IP       : $($device.IP)"
                Write-Host "Current Critical : $($device.Critical)"
                Write-Host "Current Enabled  : $($device.Enabled)"
                Write-Host ""

                $newName = Read-Host "New Device Name [Enter = Keep]"
                $newIP = Read-Host "New IP Address [Enter = Keep]"
                $newCritical = Read-Host "Critical? (Y/N) [Enter = Keep]"

                # ==========================================
		# VALIDATE NEW NAME
		# ==========================================

		if (-not [string]::IsNullOrWhiteSpace($newName)) {

    		$duplicateName = @(
        		$servers.Devices |
        		Where-Object {
            		$_ -ne $device -and
            		$_.Name -eq $newName
        		}
    		)

    		if ($duplicateName.Count -gt 0) {
        		Write-Host ""
        		Write-Host "A device with this name already exists." -ForegroundColor Red
        		Start-Sleep -Seconds 2
        		continue
    		}

    		$device.Name = $newName
		}


		# ==========================================
		# VALIDATE NEW IP
		# ==========================================

		if (-not [string]::IsNullOrWhiteSpace($newIP)) {

    		try {
        		[System.Net.IPAddress]::Parse($newIP) | Out-Null
    		}
    		catch {
        		Write-Host ""
        		Write-Host "Invalid IP address." -ForegroundColor Red
        		Start-Sleep -Seconds 2
        		continue
    		}

    		$duplicateIP = @(
        		$servers.Devices |
        		Where-Object {
            		$_ -ne $device -and
            		$_.IP -eq $newIP
        		}
    		)

    		if ($duplicateIP.Count -gt 0) {
        		Write-Host ""
        		Write-Host "A device with this IP already exists." -ForegroundColor Red
        		Start-Sleep -Seconds 2
        		continue
    		}

    		$device.IP = $newIP
	}

                if ($newCritical.ToUpper() -eq "Y") {
                    $device.Critical = $true
                }
                elseif ($newCritical.ToUpper() -eq "N") {
                    $device.Critical = $false
                }

                $servers |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $serverFile -Encoding UTF8

                Write-Host ""
                Write-Host "Device updated successfully." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # ==========================================
            # ENABLE / DISABLE
            # ==========================================

            '3' {

                Clear-Host

                Write-Host "=== Enable / Disable Device ===" -ForegroundColor Cyan
                Write-Host ""

                $devices = @($servers.Devices)

                for ($i = 0; $i -lt $devices.Count; $i++) {

                    $status = if ($devices[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($devices[$i].Name) - $($devices[$i].IP) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back" -ForegroundColor Cyan
                Write-Host ""

                $selection = Read-Host "Select device"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $devices.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $device = $devices[$index]

                $device.Enabled = -not $device.Enabled

                $newStatus = if ($device.Enabled) {
                    "ENABLED"
                }
                else {
                    "DISABLED"
                }

                $servers |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $serverFile -Encoding UTF8

                Write-Host ""
                Write-Host "$($device.Name) is now $newStatus." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # ==========================================
            # DELETE
            # ==========================================

            '4' {

                Clear-Host

                Write-Host "=== Delete Device ===" -ForegroundColor Red
                Write-Host ""

                $devices = @($servers.Devices)

                for ($i = 0; $i -lt $devices.Count; $i++) {

                    $status = if ($devices[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($devices[$i].Name) - $($devices[$i].IP) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back" -ForegroundColor Cyan
                Write-Host ""

                $selection = Read-Host "Select device to delete"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $devices.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $device = $devices[$index]

                Write-Host ""
                Write-Host "Selected: $($device.Name) - $($device.IP)" -ForegroundColor Yellow

                $confirmation = Read-Host "Are you sure? (Y/N)"

                if ($confirmation.ToUpper() -eq "Y") {

                    $servers.Devices = @(
                        $servers.Devices |
                        Where-Object {
                            $_.IP -ne $device.IP
                        }
                    )

                    $servers |
                        ConvertTo-Json -Depth 10 |
                        Set-Content $serverFile -Encoding UTF8

                    Write-Host ""
                    Write-Host "Device deleted successfully." -ForegroundColor Green

                    Start-Sleep -Seconds 2

                    Import-Config
                }
            }


            '0' {
                return
            }


            default {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}



function Show-RecipientManagement {

    while ($true) {

        Clear-Host

        Write-Host "=== Recipient Management ===" -ForegroundColor Cyan
        Write-Host ""

        Write-Host "[1] Add Recipient" -ForegroundColor Green
        Write-Host "[2] Edit Recipient" -ForegroundColor Yellow
        Write-Host "[3] Enable / Disable Recipient" -ForegroundColor Magenta
        Write-Host "[4] Delete Recipient" -ForegroundColor Red
        Write-Host "[0] Back" -ForegroundColor Cyan
        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice) {

            # ADD
            '1' {

                Clear-Host

                Write-Host "=== Add Recipient ===" -ForegroundColor Cyan
                Write-Host ""

                $email = Read-Host "Email Address"

                if ($email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
                    Write-Host "Invalid email address." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                if (@($config.Recipients | Where-Object {
                    $_.Email -eq $email
                }).Count -gt 0) {

                    Write-Host "Recipient already exists." -ForegroundColor Yellow
                    Start-Sleep -Seconds 2
                    continue
                }

                $newRecipient = [PSCustomObject]@{
                    Email   = $email
                    Enabled = $true
                }

                $config.Recipients += $newRecipient

                $config |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $configFile -Encoding UTF8

                Write-Host ""
                Write-Host "Recipient added successfully." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # EDIT
            '2' {

                Clear-Host

                Write-Host "=== Edit Recipient ===" -ForegroundColor Cyan
                Write-Host ""

                $recipientList = @($config.Recipients)

                for ($i = 0; $i -lt $recipientList.Count; $i++) {

                    $status = if ($recipientList[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($recipientList[$i].Email) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back"
                Write-Host ""

                $selection = Read-Host "Select recipient"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $recipientList.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $recipient = $recipientList[$index]

                Write-Host ""
                Write-Host "Current Email: $($recipient.Email)"
                Write-Host ""

                $newEmail = Read-Host "New Email Address [Enter = Keep]"

                if (-not [string]::IsNullOrWhiteSpace($newEmail)) {

    		# ==========================================
    		# EMAIL FORMAT VALIDATION
    		# ==========================================

    		if ($newEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {

        		Write-Host ""
        		Write-Host "Invalid email address." -ForegroundColor Red
        		Start-Sleep -Seconds 2
        		continue
    		}


    		# ==========================================
    		# DUPLICATE EMAIL CHECK
    		# ==========================================

    		$duplicateEmail = @(
        		$config.Recipients |
        		Where-Object {
            		$_ -ne $recipient -and
            		$_.Email -eq $newEmail
        		}
    		)

    		if ($duplicateEmail.Count -gt 0) {

        		Write-Host ""
        		Write-Host "A recipient with this email already exists." -ForegroundColor Red
        		Start-Sleep -Seconds 2
        		continue
    		}


    		# ==========================================
    		# UPDATE EMAIL
    		# ==========================================

    		$recipient.Email = $newEmail
	}

                $config |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $configFile -Encoding UTF8

                Write-Host ""
                Write-Host "Recipient updated successfully." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # ENABLE / DISABLE
            '3' {

                Clear-Host

                Write-Host "=== Enable / Disable Recipient ===" -ForegroundColor Cyan
                Write-Host ""

                $recipientList = @($config.Recipients)

                for ($i = 0; $i -lt $recipientList.Count; $i++) {

                    $status = if ($recipientList[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($recipientList[$i].Email) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back"
                Write-Host ""

                $selection = Read-Host "Select recipient"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $recipientList.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $recipient = $recipientList[$index]

                $recipient.Enabled = -not $recipient.Enabled

                $newStatus = if ($recipient.Enabled) {
                    "ENABLED"
                }
                else {
                    "DISABLED"
                }

                $config |
                    ConvertTo-Json -Depth 10 |
                    Set-Content $configFile -Encoding UTF8

                Write-Host ""
                Write-Host "$($recipient.Email) is now $newStatus." -ForegroundColor Green

                Start-Sleep -Seconds 2

                Import-Config
            }


            # DELETE
            '4' {

                Clear-Host

                Write-Host "=== Delete Recipient ===" -ForegroundColor Red
                Write-Host ""

                $recipientList = @($config.Recipients)

                for ($i = 0; $i -lt $recipientList.Count; $i++) {

                    $status = if ($recipientList[$i].Enabled) {
                        "ENABLED"
                    }
                    else {
                        "DISABLED"
                    }

                    Write-Host "[$($i + 1)] $($recipientList[$i].Email) - $status"
                }

                Write-Host ""
                Write-Host "[0] Back"
                Write-Host ""

                $selection = Read-Host "Select recipient to delete"

                if ($selection -eq "0") {
                    continue
                }

                if ($selection -notmatch '^\d+$') {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $index = [int]$selection - 1

                if ($index -lt 0 -or $index -ge $recipientList.Count) {
                    Write-Host "Invalid selection." -ForegroundColor Red
                    Start-Sleep -Seconds 2
                    continue
                }

                $recipient = $recipientList[$index]

                Write-Host ""
                Write-Host "Selected: $($recipient.Email)" -ForegroundColor Yellow

                $confirmation = Read-Host "Are you sure? (Y/N)"

                if ($confirmation.ToUpper() -eq "Y") {

                    $config.Recipients = @(
                        $recipientList |
                        Where-Object {
                            $_.Email -ne $recipient.Email
                        }
                    )

                    $config |
                        ConvertTo-Json -Depth 10 |
                        Set-Content $configFile -Encoding UTF8

                    Write-Host ""
                    Write-Host "Recipient deleted successfully." -ForegroundColor Green

                    Start-Sleep -Seconds 2

                    Import-Config
                }
            }


            '0' {
                return
            }


            default {
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }
}

function Show-LiveDashboard {

    $pageSize = 15
    $currentPage = 0

    while ($true) {

        Clear-Host

        Write-Host "========================================================" -ForegroundColor Cyan
        Write-Host "              NETWORK MONITORING TOOL" -ForegroundColor Cyan
        Write-Host "                  LIVE DASHBOARD" -ForegroundColor Cyan
        Write-Host "========================================================" -ForegroundColor Cyan

        Write-Host ""
        Write-Host "Last Refresh  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Host "Check Interval: $($config.CheckIntervalSeconds) sec"
        Write-Host "Retry Count   : $($config.RetryCount)"
        Write-Host ""

        # ==========================================
        # DEVICE COUNTS
        # ==========================================

        $totalDevices = @($global:ipAddresses).Count

        $upCount = @(
            $global:dashboardStatus.Values |
            Where-Object { $_.Status -eq "UP" }
        ).Count

        $downCount = @(
            $global:dashboardStatus.Values |
            Where-Object { $_.Status -eq "DOWN" }
        ).Count

        Write-Host "Device Count : $totalDevices"

        Write-Host "UP           : " -NoNewline
        Write-Host "$upCount" -ForegroundColor Green

        Write-Host "DOWN         : " -NoNewline

        if ($downCount -gt 0) {
            Write-Host "$downCount" -ForegroundColor Red
        }
        else {
            Write-Host "$downCount" -ForegroundColor Green
        }

        Write-Host ""

        # ==========================================
        # DEVICE LIST
        # ==========================================

        $allDevices = @(
            $global:dashboardStatus.Values |
            Sort-Object Name
        )

        $totalPages = [Math]::Ceiling($allDevices.Count / $pageSize)

        if ($totalPages -eq 0) {
            $totalPages = 1
        }

        # Validate page boundaries before rendering the list.
        if ($currentPage -ge $totalPages) {
            $currentPage = $totalPages - 1
        }

        if ($currentPage -lt 0) {
            $currentPage = 0
        }

        $startIndex = $currentPage * $pageSize

        $pageDevices = @(
            $allDevices |
            Select-Object -Skip $startIndex -First $pageSize
        )

        Write-Host "--------------------------------------------------------"
        Write-Host "DEVICES - Page $($currentPage + 1) / $totalPages" -ForegroundColor Cyan
        Write-Host "--------------------------------------------------------"

        # ==========================================
        # TABLE HEADER
        # ==========================================

        Write-Host (
    		"{0,-35} {1,-10} {2,-10} {3,-10} {4,-10} {5,-10} {6,-12}" -f `
    		"Device",
    		"Status",
    		"Latency",
    		"Critical",
    		"Last Check",
    		"Down Since",
    		"Duration"
		)

        Write-Host ("-" * 107)

        # ==========================================
        # DEVICES
        # ==========================================

	foreach ($device in $pageDevices) {

    		$color = if ($device.Status -eq "UP") {
        		"Green"
    		}
    		else {
        		"Red"
    		}

# Truncate long device names for display consistency.
            $displayName = $device.Name

            if ($displayName.Length -gt 35) {
                $displayName = $displayName.Substring(0, 32) + "..."
            }

            # Calculate the total duration for devices currently marked as DOWN.
            if ($device.Status -eq "DOWN" -and $null -ne $device.DownSince) {

        		$downSinceDisplay = $device.DownSince.ToString("HH:mm:ss")

        		$duration = (Get-Date) - $device.DownSince

        		$durationDisplay = "{0:00}:{1:00}:{2:00}" -f `
            		[int]$duration.TotalHours,
            		$duration.Minutes,
            		$duration.Seconds
    		}
    		else {

        		$downSinceDisplay = "-"
        		$durationDisplay = "-"
    		}

    		Write-Host (
        		"{0,-35} {1,-10} {2,-10} {3,-10} {4,-10} {5,-10} {6,-12}" -f `
        		$displayName,
        		$device.Status,
        		$device.Latency,
        		$device.Critical,
        		$device.LastCheck.ToString("HH:mm:ss"),
        		$downSinceDisplay,
        		$durationDisplay
    		) -ForegroundColor $color
	}

        Write-Host ("-" * 107)

        Write-Host ""
        Write-Host "Last Alert : $global:lastAlert" -ForegroundColor Yellow
        Write-Host ""

        # ==========================================
        # PAGE NAVIGATION
        # ==========================================

        Write-Host "[N] Next Page" -ForegroundColor Cyan
        Write-Host "[P] Previous Page" -ForegroundColor Cyan
        Write-Host ""

        # ==========================================
        # MANAGEMENT MENU
        # ==========================================

        Write-Host "[1] Manage Devices" -ForegroundColor Cyan
        Write-Host "[2] Manage Recipients" -ForegroundColor Cyan
        Write-Host "[3] Reload Config" -ForegroundColor Cyan
        Write-Host "[0] Back" -ForegroundColor Cyan

        Write-Host ""

        $choice = Read-Host "Select an option"

        switch ($choice.ToUpper()) {

            # ==========================================
            # NEXT PAGE
            # ==========================================

            'N' {
                if ($currentPage -lt ($totalPages - 1)) {
                    $currentPage++
                }
                else {
                    Write-Host ""
                    Write-Host "Already on the last page." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }

            # ==========================================
            # PREVIOUS PAGE
            # ==========================================

            'P' {
                if ($currentPage -gt 0) {
                    $currentPage--
                }
                else {
                    Write-Host ""
                    Write-Host "Already on the first page." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }

            # ==========================================
            # MANAGE DEVICES
            # ==========================================

            '1' {
                Show-DeviceManagement

                # The device list may have changed and needs to be reloaded.
                Import-Config

                if ($global:ipAddresses.Count -gt 0) {
                    Test-AllDevices
                }

                $currentPage = 0
            }

            # ==========================================
            # MANAGE RECIPIENTS
            # ==========================================

            '2' {
                Show-RecipientManagement
            }

            # ==========================================
            # RELOAD CONFIG
            # ==========================================

            '3' {
                Import-Config

                if ($global:ipAddresses.Count -gt 0) {
                    Test-AllDevices
                }

                $currentPage = 0
            }

            # ==========================================
            # BACK
            # ==========================================

            '0' {
                return
            }

            # ==========================================
            # INVALID
            # ==========================================

            default {
                Write-Host ""
                Write-Host "Invalid selection." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}
function Test-AllDevices {

    foreach ($device in @($global:ipAddresses)) {

        Test-IPConnection `
            -ip $device.IP `
            -name $device.Name `
            -critical ([bool]$device.Critical)
    }
}


function Import-Config {

    try {

        # Reload configuration without restarting the service.
        # This is important when recipients or monitored devices are changed at runtime.
        # It also prevents stale data from the previous config from being kept in memory.
	$script:config = Get-Content $configFile -Raw | ConvertFrom-Json
	$global:config = $script:config
	$config = $script:config
	
	$script:recipients = @(
    		$script:config.Recipients |
    		Where-Object { $_.Enabled -eq $true } |
    		ForEach-Object { $_.Email }
		)
	$global:recipients = $script:recipients
	$recipients = $script:recipients

        $script:servers = Get-Content $serverFile -Raw | ConvertFrom-Json
	$global:servers = $script:servers
	$servers = $script:servers

	$script:smtpServer = $script:config.SmtpServer
	$script:smtpPort = $script:config.SmtpPort
	$global:smtpServer = $script:smtpServer
	$global:smtpPort = $script:smtpPort
	$smtpServer = $script:smtpServer
	$smtpPort = $script:smtpPort
	
	$script:credential = Import-Clixml $script:config.CredentialFile
	$script:username = $script:credential.UserName
	$global:credential = $script:credential
	$global:username = $script:username
	$credential = $script:credential
	$username = $script:username

        $script:notificationMode = if ($script:config.NotificationMode) { $script:config.NotificationMode } else { "smtp" }
	$global:notificationMode = $script:notificationMode
	$notificationMode = $script:notificationMode

        $script:ipAddresses = @(
            $script:servers.Devices |
            Where-Object { $_.Enabled -eq $true }
        )
	$global:ipAddresses = $script:ipAddresses
	$ipAddresses = $script:ipAddresses

	$logFolder = $script:config.LogFolder
	$reportFolder = $script:config.ReportFolder

        $activeIPs = @(
            $global:ipAddresses | ForEach-Object {
                $_.IP
            }
        )

        foreach ($ip in @($global:dashboardStatus.Keys)) {

            if ($ip -notin $activeIPs) {
                $global:dashboardStatus.Remove($ip)
            }
        }

        foreach ($ip in @($global:serverStatus.Keys)) {

            if ($ip -notin $activeIPs) {
                $global:serverStatus.Remove($ip)
            }
        }

    }
    catch {

        Write-Host "Configuration reload failed!" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        Add-Content $logFile `
            "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - CONFIG RELOAD FAILED - $($_.Exception.Message)"
    }
}


# ==========================================
# Main Loop
# ==========================================


while ($true) {

	$global:logFile = Join-Path `
    	$logFolder "IPMonitor_$(Get-Date -Format 'yyyyMMdd').txt"

	Test-AllDevices
    	Update-Dashboard

	$reloadDashboard = $false

for ($i = 0; $i -lt $config.CheckIntervalSeconds; $i++) {

    if ([Console]::KeyAvailable) {

        $key = [Console]::ReadKey($true)

        switch ($key.KeyChar) {

            '1' {
                Show-LiveDashboard
                $reloadDashboard = $true
            }
        }

        if ($reloadDashboard) {
            break
        }
    }

    Start-Sleep -Seconds 1
}
}

