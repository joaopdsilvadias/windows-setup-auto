<#
.SYNOPSIS
  Instala apps via winget e otimiza o Windows.
.EXAMPLE
  .\setup.ps1                 # menu interativo
  .\setup.ps1 -Install        # so instala apps
  .\setup.ps1 -Optimize       # so otimiza
  .\setup.ps1 -All            # tudo, sem perguntar
#>
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Optimize,
    [switch]$Debloat,
    [switch]$Drivers,
    [switch]$Privacy,
    [switch]$All
)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile = Join-Path $Root "setup-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Start-Transcript -Path $LogFile | Out-Null

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "  [SKIP] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

# ---------- Admin check ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Fail "Execute como Administrador (use o run.bat)."
    Stop-Transcript | Out-Null
    exit 1
}

# ---------- Menu ----------
if (-not ($Install -or $Optimize -or $Debloat -or $Drivers -or $Privacy -or $All)) {
    Write-Host "`n  1) Instalar apps"
    Write-Host "  2) Otimizar Windows"
    Write-Host "  3) Remover bloatware (opcional)"
    Write-Host "  4) Tudo (instalar + otimizar, sem bloatware)"
    Write-Host "  5) Tudo + remover bloatware"
    Write-Host "  6) Instalar drivers"
    Write-Host "  7) Privacidade (reforcada)"
    Write-Host "  0) Sair"
    switch (Read-Host "`nEscolha") {
        '1' { $Install = $true }
        '2' { $Optimize = $true }
        '3' { $Debloat = $true }
        '4' { $All = $true }
        '5' { $All = $true; $Debloat = $true }
        '6' { $Drivers = $true }
        '7' { $Privacy = $true }
        default { Stop-Transcript | Out-Null; exit 0 }
    }
}
if ($All) { $Install = $true; $Optimize = $true }

# ======================================================================
#  INSTALAR APPS
# ======================================================================
function Install-Apps {
    Write-Step "Instalando apps via winget"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Fail "winget nao encontrado. Instale 'App Installer' pela Microsoft Store e rode de novo."
        return
    }

    $cfg = Get-Content (Join-Path $Root 'apps.json') -Raw | ConvertFrom-Json
    $apps = $cfg.apps | Where-Object { $_.enabled }
    $installed = (winget list --accept-source-agreements 2>$null | Out-String)

    $i = 0
    foreach ($app in $apps) {
        $i++
        Write-Host "[$i/$($apps.Count)] $($app.name)" -ForegroundColor White
        if ($installed -match [regex]::Escape($app.id)) {
            Write-Skip "ja instalado"
            continue
        }
        winget install --id $app.id -e --silent `
            --accept-package-agreements --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "instalado" }
        else { Write-Fail "codigo $LASTEXITCODE (veja o log)" }
    }

    Write-Step "Atualizando o que ja esta instalado"
    winget upgrade --all --silent --accept-package-agreements --accept-source-agreements | Out-Null
}

# ======================================================================
#  OTIMIZACOES
# ======================================================================
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

function Optimize-Windows {
    Write-Step "Criando ponto de restauracao"
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        Checkpoint-Computer -Description "Antes do windows-setup-auto" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok "ponto de restauracao criado"
    } catch { Write-Skip "nao foi possivel criar ($($_.Exception.Message))" }

    Write-Step "Plano de energia: Alto desempenho"
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    if ($LASTEXITCODE -ne 0) {
        powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c | Out-Null
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    }
    Write-Ok "aplicado"

    Write-Step "Privacidade / telemetria"
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Write-Ok "telemetria minima, anuncios e sugestoes desativados"

    Write-Step "Game DVR / Game Bar"
    Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
    Write-Ok "desativado"

    Write-Step "Explorer (conforto de dev)"
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'HideFileExt' 0           # mostrar extensoes
    Set-Reg $adv 'Hidden' 1                # mostrar ocultos
    Set-Reg $adv 'LaunchTo' 1              # abrir em Este Computador
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1
    Write-Ok "extensoes visiveis, arquivos ocultos, long paths"

    Write-Step "Efeitos visuais (desempenho)"
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
    Set-Reg $adv 'TaskbarAnimations' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0
    Write-Ok "animacoes reduzidas, sem atraso de inicializacao"

    Write-Step "Servicos desnecessarios"
    foreach ($svc in 'DiagTrack', 'dmwappushservice', 'MapsBroker', 'RetailDemo') {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            Set-Service $svc -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Ok "$svc desativado"
        }
    }

    Write-Step "Hibernacao / Fast Startup"
    powercfg /hibernate off
    Write-Ok "hibernacao desativada (libera espaco do hiberfil.sys)"

    Write-Step "Limpeza de temporarios"
    $before = (Get-PSDrive C).Free
    foreach ($p in $env:TEMP, "$env:WINDIR\Temp", "$env:WINDIR\SoftwareDistribution\Download") {
        if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    $freed = [math]::Round(((Get-PSDrive C).Free - $before) / 1MB)
    Write-Ok "$freed MB liberados"

    Write-Step "Otimizando SSD (TRIM)"
    Optimize-Volume -DriveLetter C -ReTrim -ErrorAction SilentlyContinue
    Write-Ok "concluido"

    Write-Host "`nReinicie o PC para aplicar tudo." -ForegroundColor Magenta
}

# ======================================================================
#  REMOVER BLOATWARE (opcional)
# ======================================================================
function Remove-Bloatware {
    Write-Step "Removendo bloatware (apps Appx)"

    $cfg = Get-Content (Join-Path $Root 'bloatware.json') -Raw | ConvertFrom-Json
    $items = $cfg.packages | Where-Object { $_.enabled }

    Write-Host "Serao removidos (se existirem):" -ForegroundColor Yellow
    $items | ForEach-Object { Write-Host "  - $($_.name)" }
    if ((Read-Host "`nConfirmar? (s/N)") -notmatch '^[sSyY]') {
        Write-Skip "cancelado"
        return
    }

    $installed = Get-AppxPackage -AllUsers
    $provisioned = Get-AppxProvisionedPackage -Online

    foreach ($item in $items) {
        $found = $installed | Where-Object { $_.Name -like $item.pattern }
        $prov  = $provisioned | Where-Object { $_.DisplayName -like $item.pattern }
        if (-not $found -and -not $prov) { Write-Skip "$($item.name): nao encontrado"; continue }

        try {
            $found | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop }
            # remove tambem do provisionamento, para nao voltar em novos usuarios
            $prov | ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null }
            Write-Ok $item.name
        } catch {
            Write-Fail "$($item.name): $($_.Exception.Message)"
        }
    }
    Write-Host "`nApps removidos podem ser reinstalados pela Microsoft Store." -ForegroundColor DarkGray

    if ($cfg.removeOneDrive) { Remove-OneDrive }
}

function Remove-OneDrive {
    Write-Step "Removendo OneDrive"
    Write-Host "ATENCAO: arquivos que existem so na nuvem (nao baixados) deixam de aparecer no PC." -ForegroundColor Yellow
    Write-Host "Sua pasta OneDrive local NAO sera apagada, mas confirme que tudo esta sincronizado." -ForegroundColor Yellow
    if ((Read-Host "`nRemover o OneDrive? (s/N)") -notmatch '^[sSyY]') { Write-Skip "cancelado"; return }

    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $setup = @("$env:SystemRoot\SysWOW64\OneDriveSetup.exe", "$env:SystemRoot\System32\OneDriveSetup.exe") |
             Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($setup) {
        Start-Process $setup -ArgumentList '/uninstall' -Wait
        Write-Ok "OneDrive desinstalado"
    } else {
        winget uninstall --id Microsoft.OneDrive -e --silent 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { Write-Ok "OneDrive desinstalado (winget)" }
        else { Write-Skip "OneDrive nao encontrado" }
    }

    # impede reinstalacao automatica e remove do painel de navegacao do Explorer
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    $clsid = 'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}'
    if (Test-Path $clsid) { Set-ItemProperty $clsid -Name 'System.IsPinnedToNameSpaceTree' -Value 0 -ErrorAction SilentlyContinue }
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'OneDrive' -ErrorAction SilentlyContinue
    Write-Ok "reinstalacao automatica bloqueada e atalho removido do Explorer"
}

# ======================================================================
#  DRIVERS (opcional)
# ======================================================================
function Install-Drivers {
    Write-Step "Detectando hardware"
    $gpus  = (Get-CimInstance Win32_VideoController).Name
    $cpu   = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
    $maker = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    Write-Host "  CPU:        $cpu"
    Write-Host "  GPU(s):     $($gpus -join ', ')"
    Write-Host "  Fabricante: $maker"

    # --- 1) Drivers via Windows Update (chipset, rede, audio, etc.) ---
    Write-Step "Drivers via Windows Update"
    try {
        if (-not (Get-Module -ListAvailable PSWindowsUpdate)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
            Install-Module PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop

        $updates = Get-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -ErrorAction Stop
        if (-not $updates) {
            Write-Ok "nenhum driver pendente"
        } else {
            $updates | ForEach-Object { Write-Host "  - $($_.Title)" }
            if ((Read-Host "`nInstalar estes drivers? (s/N)") -match '^[sSyY]') {
                Get-WindowsUpdate -MicrosoftUpdate -UpdateType Driver -AcceptAll -Install -IgnoreReboot | Out-Null
                Write-Ok "drivers instalados"
            } else { Write-Skip "cancelado" }
        }
    } catch {
        Write-Fail "Windows Update: $($_.Exception.Message)"
    }

    # --- 2) Ferramentas oficiais dos fabricantes (via winget) ---
    Write-Step "Ferramentas oficiais do fabricante"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Skip "winget nao encontrado"
        return
    }

    $tools = @()
    if ($gpus -match 'NVIDIA')                { $tools += @{ n='NVIDIA App (driver da GPU)'; id='Nvidia.NvidiaApp' } }
    if ($gpus -match 'Intel' -or $cpu -match 'Intel') {
                                                $tools += @{ n='Intel Driver & Support Assistant'; id='Intel.IntelDriverAndSupportAssistant' } }
    if ($maker -match 'Dell')                 { $tools += @{ n='Dell Command Update'; id='Dell.CommandUpdate' } }
    if ($maker -match 'LENOVO')               { $tools += @{ n='Lenovo System Update'; id='Lenovo.SystemUpdate' } }
    if ($gpus -match 'AMD|Radeon' -or $cpu -match 'AMD') {
        Write-Host "  AMD: nao ha pacote winget confiavel. Baixe o Adrenalin/Chipset em https://www.amd.com/support" -ForegroundColor Yellow
    }

    foreach ($t in $tools) {
        Write-Host "  $($t.n)" -ForegroundColor White
        winget install --id $t.id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
        if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) { Write-Ok "pronto" }
        else { Write-Fail "codigo $LASTEXITCODE (confira o ID com: winget search)" }
    }

    Write-Host "`nReinicie o PC para finalizar os drivers." -ForegroundColor Magenta
}

# ======================================================================
#  PRIVACIDADE REFORCADA (opcional)
# ======================================================================
function Set-Privacy {
    Write-Step "Privacidade reforcada"
    Write-Host "Isto desativa localizacao, historico de atividades, Recall/Copilot," -ForegroundColor Yellow
    Write-Host "sincronizacao de area de transferencia e tarefas de telemetria." -ForegroundColor Yellow
    if ((Read-Host "`nConfirmar? (s/N)") -notmatch '^[sSyY]') { Write-Skip "cancelado"; return }

    Write-Step "Identificadores e personalizacao"
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0                       # personalizacao de digitacao
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AppHost' 'EnableWebContentEvaluation' 0
    Write-Ok "ID de anuncio, idioma, digitacao e SmartScreen de apps"

    Write-Step "Telemetria e diagnostico"
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0          # 0 so vale em Enterprise; Pro usa o minimo
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    foreach ($task in @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting')) {
        schtasks /Change /TN $task /Disable 2>$null | Out-Null
    }
    Write-Ok "telemetria, relatorios de erro e tarefas CEIP desativados"

    Write-Step "Historico de atividades e area de transferencia"
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg $sys 'EnableActivityFeed' 0
    Set-Reg $sys 'PublishUserActivities' 0
    Set-Reg $sys 'UploadUserActivities' 0
    Set-Reg $sys 'AllowCrossDeviceClipboard' 0
    Set-Reg 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' 0
    Write-Ok "timeline e sincronizacao entre dispositivos desativados"

    Write-Step "Localizacao"
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'String'
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
    Write-Ok "localizacao desativada"

    Write-Step "Recall, Copilot e busca na web"
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1       # Recall
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'CortanaConsent' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 0
    Write-Ok "Recall, Copilot e pesquisa web desativados"

    Write-Step "Outros"
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\WcmSvc\wifinetworksetup' 'AutoConnectAllowedOEM' 0           # hotspots abertos
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0    # sem P2P de updates
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableSoftLanding' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
    Write-Ok "Wi-Fi Sense, P2P de updates e conteudo promovido desativados"

    Write-Host "`nReinicie para aplicar. Algumas politicas so aparecem em Configuracoes apos reiniciar." -ForegroundColor Magenta
}

if ($Install)  { Install-Apps }
if ($Optimize) { Optimize-Windows }
if ($Debloat)  { Remove-Bloatware }
if ($Drivers)  { Install-Drivers }
if ($Privacy)  { Set-Privacy }

Write-Host "`nLog salvo em: $LogFile" -ForegroundColor DarkGray
Stop-Transcript | Out-Null
