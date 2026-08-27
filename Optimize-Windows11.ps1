#Requires -RunAsAdministrator
# Windows 11 Optimization Script v2.1 - Interactive Menu
# Updated for 24H2/25H2 AI features (Recall, Click to Do, Input Insights, AI Fabric)
# Creates a restore point before changes. Logs to %TEMP%.
# Preserves: Print Spooler, Windows Search, Windows Scan, WIA (scanner drivers), WSL, VMware
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
    $protected = @(
        'Spooler', 'WSearch', 'WiaRpc', 'StiSvc', 'PrintWorkflowUserSvc',
        'LxssManager', 'WslService',
        'VMAuthdService', 'VMnetDHCP', 'VMUSBArbService', 'VMwareHostd'
    )
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
    Write-Host '         Windows 11 Optimization Script v2.1            ' -ForegroundColor DarkCyan
    Write-Host '          Run as Administrator - 24H2/25H2              ' -ForegroundColor DarkCyan
    Write-Host '  ======================================================' -ForegroundColor DarkCyan
    Write-Host ''
}
# ---- Category 1: AI / Copilot Removal ----
function Invoke-RemoveAICopilot {
    Write-Host ''
    Write-Host '  -- Removing AI / Copilot Features --' -ForegroundColor Magenta
    # Appx packages - Copilot and AI components
    Remove-AppxSafe '*Microsoft.Copilot*'
    Remove-AppxSafe '*Microsoft.Windows.Ai*'
    Remove-AppxSafe '*MicrosoftWindows.Client.AIX*'
    Remove-AppxSafe '*Microsoft.Windows.AI.Copilot.Provider*'
    Remove-AppxSafe '*MicrosoftWindows.Client.Photon*'
    Remove-AppxSafe '*Microsoft.549981C3F5F10*'
    # Disable Copilot via Group Policy registry
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    # 25H2 Copilot removal policy - April 2026
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Copilot' 'RemoveCopilotApp' 1
    # Disable Recall and AI data analysis
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'TurnOffSavingSnapshots' 1
    # Attempt DISM removal of Recall optional feature (25H2+)
    Write-Log 'Attempting DISM removal of Recall optional feature...' 'INFO'
    $dismResult = dism /online /Disable-Feature /FeatureName:'Recall' /NoRestart 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Recall removed via DISM' 'SUCCESS'
    }
    else {
        Write-Log 'Recall not available as optional feature on this build - registry controls applied' 'WARN'
    }
    # Disable Click to Do (25H2 context menu AI actions)
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
    # Disable Input Insights (typing behavior tracking)
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\input\Settings' 'InsightsEnabled' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableInputInsights' 1
    # Disable AI features in Paint, Photos, and Snipping Tool
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableImageCreator' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableCocreator' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableGenerativeFill' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableGenerativeErase' 1
    # Disable Bing / AI in Windows Search
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    # Disable Copilot in Edge
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'CopilotCDPPageContext' 0
    # Disable AI Fabric Service if present (25H2 background AI service)
    Disable-ServiceSafe 'AIFabricService'       'AI Fabric Service'
    Disable-ServiceSafe 'AIF'                   'AI Fabric'
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
    # Disable Automatic Restart Sign-On (ARSO) - prevents background session at login screen
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'DisableAutomaticRestartSignOn' 1
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
# ---- Category 4: Bloatware Removal ----
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
# ---- Category 5: Spotlight and Lock Screen Extras ----
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
# ---- Category 6: Performance and Update Control ----
function Invoke-PerformanceUpdates {
    Write-Host ''
    Write-Host '  -- Performance and Update Control --' -ForegroundColor Magenta
    # ---- Boot Optimization ----
    bcdedit /timeout 3 | Out-Null
    Write-Log 'Boot timeout set to 3 seconds' 'SUCCESS'
    Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
    # Disable tips and welcome experience after updates
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    # ---- Memory Optimization ----
    # Disable SysMain (Superfetch) - speculative RAM preloading, negligible on NVMe
    Disable-ServiceSafe 'SysMain'              'SysMain / Superfetch'
    # Disable Reserved Storage (~7GB held back for updates)
    dism /online /Set-ReservedStorageState /State:Disabled 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'Reserved Storage disabled - ~7GB reclaimed' 'SUCCESS'
    }
    else {
        Write-Log 'Reserved Storage already disabled or not available' 'WARN'
    }
    # Disable all background UWP app activity
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2
    # Disable clipboard cloud sync and history
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowClipboardHistory' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'AllowCrossDeviceClipboard' 0
    # ---- CPU / Scheduling ----
    # Favor foreground apps in scheduler (0x26 = short quantum, variable, foreground boost)
    Set-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 38
    # ---- Gaming Performance ----
    # Disable Game Bar overlay
    Set-RegistryValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Set-RegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    # Disable fullscreen optimizations globally (reduces DWM input latency)
    Set-RegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
    Set-RegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
    Set-RegistryValue 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
    # ---- Disk I/O (NVMe) ----
    # Disable NTFS last access timestamp updates (reduces write I/O)
    fsutil behavior set disablelastaccess 1 2>$null
    Write-Log 'NTFS last access timestamps disabled' 'SUCCESS'
    # Disable 8.3 short filename creation (legacy DOS compat)
    fsutil behavior set disable8dot3 1 2>$null
    Write-Log '8.3 short filename creation disabled' 'SUCCESS'
    # ---- Network Optimization (1Gbps Ethernet) ----
    # Disable Nagle algorithm and set TCP ACK frequency per interface
    $ifPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $interfaces = Get-ChildItem $ifPath -ErrorAction SilentlyContinue
    $nagleCount = 0
    foreach ($iface in $interfaces) {
        $ip = (Get-ItemProperty $iface.PSPath -ErrorAction SilentlyContinue).IPAddress
        if ($ip) {
            Set-ItemProperty $iface.PSPath -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            Set-ItemProperty $iface.PSPath -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
            $nagleCount++
        }
    }
    Write-Log ('Nagle disabled on ' + $nagleCount + ' network interfaces') 'SUCCESS'
    # Disable network throttling (multimedia scheduler 10 packets/ms limit)
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 0xFFFFFFFF
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 0
    # Increase network priority for gaming
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'GPU Priority' 8
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Priority' 6
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Scheduling Category' 'High' 'String'
    # ---- Power Plan ----
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    if ($LASTEXITCODE -ne 0) {
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    }
    Write-Log 'Power plan set to High Performance' 'SUCCESS'
    # Configure sleep and display timeouts on active plan
    # Never sleep - AC or DC
    powercfg /change standby-timeout-ac 0 2>$null
    powercfg /change standby-timeout-dc 0 2>$null
    # Never hibernate
    powercfg /change hibernate-timeout-ac 0 2>$null
    powercfg /change hibernate-timeout-dc 0 2>$null
    # Display off after 60 minutes - AC and DC
    powercfg /change monitor-timeout-ac 60 2>$null
    powercfg /change monitor-timeout-dc 60 2>$null
    Write-Log 'Sleep disabled, display timeout set to 60 min' 'SUCCESS'
    # ---- Disable Delivery Optimization ----
    Disable-ServiceSafe 'DoSvc'                'Delivery Optimization'
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' 'DODownloadMode' 0
    Write-Log 'Delivery Optimization fully disabled' 'SUCCESS'
    # ---- Windows Update: Notify Only, No Auto-Install, No Auto-Reboot ----
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 2
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' 1
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AlwaysAutoRebootAtScheduledTime' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'SetComplianceDeadline' 0
    Set-RegistryValue 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'SetAutoRestartNotificationDisable' 0
    # Disable wake timers (prevents WU from waking PC to reboot)
    powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 2>$null
    powercfg /SETDCVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 0 2>$null
    powercfg /SETACTIVE SCHEME_CURRENT 2>$null
    Write-Log 'Wake timers disabled' 'SUCCESS'
    Write-Log 'Windows Update set to notify only - auto-install and auto-reboot disabled' 'SUCCESS'
    # ---- Clean Temp Files ----
    $tempPaths = @($env:TEMP, (Join-Path $env:WINDIR 'Temp'), (Join-Path $env:WINDIR 'Prefetch'))
    foreach ($p in $tempPaths) {
        if (Test-Path $p) {
            $count = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue).Count
            Remove-Item (Join-Path $p '*') -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log ('Cleaned ' + $count + ' items from ' + $p) 'SUCCESS'
        }
    }
    Write-Log 'Performance and update control complete' 'SUCCESS'
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
    Write-Host '    6) Performance and Update Control' -ForegroundColor Yellow
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
        '6' = { Invoke-PerformanceUpdates }
    }
    if ($choice -eq 'A' -or $choice -eq 'a') {
        $selections = @('1','2','3','4','5','6')
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
