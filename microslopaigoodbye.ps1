#Requires -RunAsAdministrator
# Windows 11 Optimization Script v1.1 - Interactive Menu
# Creates a restore point before changes. Logs to %TEMP%.
# Preserves: Print Spooler, Windows Search, Windows Scan, WIA (scanner drivers)

$ErrorActionPreference = 'SilentlyContinue'
$LogFile = (Join-Path $env:TEMP ('Win11Optimize_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log'))

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' [' + $Level + '] ' + $Message
    Add-Content -Path $LogFile -Value $entry
    switch ($Level) {
        'SUCCESS' { Write-Host ('  [OK] ' + $Message) -ForegroundColor Green }
        'WARN'    { Write-Host ('  [!!] ' + $Message) -ForegroundColor Yellow }
        'ERROR'   { Write-Host ('  [XX] ' + $Message) -ForegroundColor Red }
        default   { Write-Host ('  [--] ' + $Message) -ForegroundColor Cyan }
    }
}

function Set-RegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Log ('Registry set: ' + $Path + '\' + $Name + ' = ' + $Value) 'SUCCESS'
    }
    catch {
        Write-Log ('Failed to set: ' + $Path + '\' + $Name + ' - ' + $_) 'ERROR'
    }
}

function Disable-ServiceSafe {
    param([string]$ServiceName, [string]$DisplayName)
    # Protected services - never disable these
    $protected = @('Spooler', 'WSearch', 'WiaRpc', 'StiSvc', 'PrintWorkflowUserSvc')
    if ($protected -contains $ServiceName) {
        Write-Log ('PROTECTED - skipped: ' + $DisplayName + ' - ' + $ServiceName) 'WARN'
        return
    }
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
        Set-Service -Name $ServiceName -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log ('Disabled service: ' + $DisplayName + ' - ' + $ServiceName) 'SUCCESS'
    }
    else {
        Write-Log ('Service not found: ' + $ServiceName) 'WARN'
    }
}

function Remove-AppxSafe {
    param([string]$Pattern)
    # Protected apps - never remove print/scan related packages
    $protectedPatterns = @('*Print3D*', '*Print*Scan*', '*WindowsScan*')
    foreach ($pp in $protectedPatterns) {
        if ($Pattern -like $pp) {
            Write-Log ('PROTECTED - skipped removal: ' + $Pattern) 'WARN'
            return
        }
    }
    $pkgs = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $Pattern }
    foreach ($pkg in $pkgs) {
        try {
            $pkg | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Get-AppxProvisionedPackage -Online |
                Where-Object { $_.DisplayName -like $Pattern } |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
            Write-Log ('Removed: ' + $pkg.Name) 'SUCCESS'
        }
        catch {
            Write-Log ('Could not remove: ' + $pkg.Name + ' - ' + $_) 'WARN'
        }
    }
    if (-not $pkgs) { Write-Log ('Package not found: ' + $Pattern) 'WARN' }
}

function Show-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor DarkCyan
    Write-Host '         Windows 11 Optimization Script v1.1            ' -ForegroundColor DarkCyan
    Write-Host '            Run as Administrator required                ' -ForegroundColor DarkCyan
    Write-Host '  ======================================================' -ForegroundColor DarkCyan
    Write-Host ''
}

# ---- Category 1: AI / Copilot Removal ----
function Invoke-RemoveAICopilot {
    Write-Host ''
    Write-Host '  -- Removing AI / Copilot Features --' -ForegroundColor Magenta

    Remove-AppxSafe '*Microsoft.Copilot*'
    Remove-AppxSafe '*Microsoft.Windows.Ai*'
    Remove-AppxSafe '*MicrosoftWindows.Client.AIX*'

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'TurnOffSavingSnapshots' 1

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0

    Write-Log 'AI/Copilot removal complete' 'SUCCESS'
}

# ---- Category 2: Disable Unnecessary Services ----
function Invoke-DisableServices {
    Write-Host ''
    Write-Host '  -- Disabling Unnecessary Services --' -ForegroundColor Magenta

    Disable-ServiceSafe 'DiagTrack'            'Connected User Experiences and Telemetry'
    Disable-ServiceSafe 'dmwappushservice'      'WAP Push Message Routing'
    Disable-ServiceSafe 'diagnosticshub.standardcollector.service' 'Diagnostics Hub'

    Disable-ServiceSafe 'XblAuthManager'        'Xbox Live Auth Manager'
    Disable-ServiceSafe 'XblGameSave'           'Xbox Live Game Save'
    Disable-ServiceSafe 'XboxNetApiSvc'         'Xbox Live Networking'
    Disable-ServiceSafe 'XboxGipSvc'            'Xbox Accessory Management'

    Disable-ServiceSafe 'Fax'                   'Fax'
    Disable-ServiceSafe 'RemoteRegistry'        'Remote Registry'
    Disable-ServiceSafe 'lfsvc'                 'Geolocation Service'
    Disable-ServiceSafe 'MapsBroker'            'Downloaded Maps Manager'
    Disable-ServiceSafe 'RetailDemo'            'Retail Demo Service'
    Disable-ServiceSafe 'wisvc'                 'Windows Insider Service'
    Disable-ServiceSafe 'WMPNetworkSvc'         'Windows Media Player Sharing'
    Disable-ServiceSafe 'icssvc'                'Mobile Hotspot Service'
    Disable-ServiceSafe 'PhoneSvc'              'Phone Service'
    Disable-ServiceSafe 'WpcMonSvc'             'Parental Controls'

    # Print Spooler and WSearch preserved per user preference

    Write-Log 'Service optimization complete' 'SUCCESS'
}

# ---- Category 3: Telemetry and Privacy ----
function Invoke-TelemetryPrivacy {
    Write-Host ''
    Write-Host '  -- Reducing Telemetry and Improving Privacy --' -ForegroundColor Magenta

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0

    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0

    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0

    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 0

    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0

    $telemetryTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser'
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater'
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator'
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip'
        '\Microsoft\Windows\Autochk\Proxy'
    )
    foreach ($task in $telemetryTasks) {
        schtasks /Change /TN $task /Disable 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log ('Disabled task: ' + $task) 'SUCCESS'
        }
        else {
            Write-Log ('Task not found or already disabled: ' + $task) 'WARN'
        }
    }

    Write-Log 'Telemetry/privacy optimization complete' 'SUCCESS'
}

# ---- Category 5: Bloatware Removal ----
function Invoke-RemoveBloatware {
    Write-Host ''
    Write-Host '  -- Removing Bloatware --' -ForegroundColor Magenta

    $bloatApps = @(
        '*Microsoft.BingNews*'
        '*Microsoft.BingWeather*'
        '*Microsoft.BingFinance*'
        '*Microsoft.BingSports*'
        '*Microsoft.GetHelp*'
        '*Microsoft.Getstarted*'
        '*Microsoft.MicrosoftOfficeHub*'
        '*Microsoft.MicrosoftSolitaireCollection*'
        '*Microsoft.People*'
        '*Microsoft.PowerAutomateDesktop*'
        '*Microsoft.Todos*'
        '*Microsoft.WindowsFeedbackHub*'
        '*Microsoft.WindowsMaps*'
        '*Microsoft.ZuneMusic*'
        '*Microsoft.ZuneVideo*'
        '*Microsoft.YourPhone*'
        '*Microsoft.WindowsCommunicationsApps*'
        '*Microsoft.MixedReality.Portal*'
        '*Microsoft.549981C3F5F10*'
        '*Clipchamp.Clipchamp*'
        '*Microsoft.GamingApp*'
        '*MicrosoftTeams*'
        '*Microsoft.OutlookForWindows*'
        '*Microsoft.ScreenSketch*'
        '*Microsoft.Windows.DevHome*'
    )

    foreach ($app in $bloatApps) {
        Remove-AppxSafe $app
    }

    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarDa' 0
    Write-Log 'Widgets disabled' 'SUCCESS'

    Write-Log 'Bloatware removal complete' 'SUCCESS'
}

# ---- Category 6: Spotlight and Lock Screen Extras ----
function Invoke-DisableSpotlightExtras {
    Write-Host ''
    Write-Host '  -- Disabling Spotlight and Lock Screen Extras --' -ForegroundColor Magenta

    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsSpotlightFeatures' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableThirdPartySuggestions' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0

    Write-Log 'Spotlight/lock screen extras disabled' 'SUCCESS'
}

# ---- Main Menu ----
function Show-Menu {
    Show-Banner
    Write-Host '  Select optimizations to run (comma-separated, e.g. 1,3,4):' -ForegroundColor White
    Write-Host ''
    Write-Host '    1) Remove AI / Copilot' -ForegroundColor Yellow
    Write-Host '    2) Disable Unnecessary Services' -ForegroundColor Yellow
    Write-Host '    3) Telemetry and Privacy' -ForegroundColor Yellow
    Write-Host '    4) Remove Bloatware' -ForegroundColor Yellow
    Write-Host '    5) Disable Spotlight and Lock Screen Extras' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '    A) Run ALL' -ForegroundColor Green
    Write-Host '    Q) Quit' -ForegroundColor Red
    Write-Host ''
}

function Invoke-Main {
    Show-Menu
    $choice = Read-Host -Prompt '  Enter selection'

    if ($choice -eq 'Q' -or $choice -eq 'q') {
        Write-Host ''
        Write-Host '  Exiting. No changes made.' -ForegroundColor Gray
        return
    }

    # Optional Restore Point
    $rp = Read-Host -Prompt '  Create a System Restore Point first? Y or N'
    if ($rp -eq 'Y' -or $rp -eq 'y') {
        Write-Host ''
        Write-Host '  -- Creating System Restore Point --' -ForegroundColor Magenta
        try {
            Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description 'Pre-Win11-Optimization' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Log 'Restore point created' 'SUCCESS'
        }
        catch {
            Write-Log ('Could not create restore point - ' + $_) 'WARN'
        }
    }
    else {
        Write-Log 'Restore point skipped by user' 'INFO'
    }

    # Dispatch
    $map = @{
        '1' = { Invoke-RemoveAICopilot }
        '2' = { Invoke-DisableServices }
        '3' = { Invoke-TelemetryPrivacy }
        '4' = { Invoke-RemoveBloatware }
        '5' = { Invoke-DisableSpotlightExtras }
    }

    if ($choice -eq 'A' -or $choice -eq 'a') {
        $selections = @('1','2','3','4','5')
    }
    else {
        $selections = $choice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $map.ContainsKey($_) }
    }

    if ($selections.Count -eq 0) {
        Write-Host ''
        Write-Host '  Invalid selection.' -ForegroundColor Red
        return
    }

    foreach ($s in $selections) {
        & $map[$s]
    }

    # Summary
    Write-Host ''
    Write-Host '  ======================================================' -ForegroundColor Green
    Write-Host '              Optimization Complete!                     ' -ForegroundColor Green
    Write-Host '  ======================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host ('  Log saved to: ' + $LogFile) -ForegroundColor Gray
    Write-Host '  A restart is recommended to apply all changes.' -ForegroundColor Yellow
    Write-Host ''

    $restart = Read-Host -Prompt '  Restart now? Y or N'
    if ($restart -eq 'Y' -or $restart -eq 'y') {
        Restart-Computer -Force
    }
}

Invoke-Main
