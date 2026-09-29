[CmdletBinding()]
param(
    [ValidateSet('wizard', 'status', 'prepare', 'launch-pkgcontrol', 'launch-windowresizer', 'install', 'restore', 'guide')]
    [string]$Action = 'wizard',
    [string]$ImagePath = '',
    [ValidateSet('card', 'portrait')]
    [string]$ImageType = 'card',
    [string]$ModifiedPackage = '',
    [AllowEmptyString()]
    [ValidateSet('en', 'es', 'fr')]
    [string]$LanguageCode = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSCommandPath
$LocaleRoot = Join-Path $ProjectRoot 'locale'
$BackupRoot = Join-Path $ProjectRoot 'backups\steam-original'
$WorkRoot = Join-Path $ProjectRoot 'work'
$LogRoot = Join-Path $ProjectRoot 'logs'
$StatePath = Join-Path $WorkRoot 'state.json'
$AssetName = 'personalzone_player_bg_2'
$AppId = '3681810'

foreach ($directory in @($BackupRoot, $WorkRoot, $LogRoot)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

function Select-Language {
    if ($LanguageCode) {
        $languageCode = $LanguageCode
    } else {
        $englishFile = Join-Path $LocaleRoot 'en.json'
        if (-not (Test-Path -LiteralPath $englishFile -PathType Leaf)) { throw 'English locale file not found.' }
        $englishStrings = (Get-Content -LiteralPath $englishFile -Raw -Encoding UTF8 | ConvertFrom-Json).Text
        Write-Host $englishStrings.LanguagePrompt
        Write-Host $englishStrings.LanguageOptions
        while ($true) {
            $choice = (Read-Host $englishStrings.LanguageSelect).Trim()
            if (-not $choice) { $choice = '1' }
            if ($choice -in @('1', '2', '3')) { break }
            Write-Host $englishStrings.LanguageInvalid -ForegroundColor Yellow
        }
        $languageCode = @{ '1' = 'en'; '2' = 'es'; '3' = 'fr' }[$choice]
    }
    $languageFile = Join-Path $LocaleRoot ($languageCode + '.json')
    if (-not (Test-Path -LiteralPath $languageFile -PathType Leaf)) {
        $message = if ($englishStrings) { $englishStrings.LanguageMissing } else { 'Language file not found: {0}' }
        throw ([string]::Format($message, $languageFile))
    }
    $script:LocaleData = Get-Content -LiteralPath $languageFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $script:SelectedLanguageCode = $languageCode
}

function Get-Text {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$FormatArgs = @()
    )
    $property = $script:LocaleData.Text.PSObject.Properties[$Key]
    $template = if ($property) { [string]$property.Value } else { $Key }
    if ($FormatArgs.Count -gt 0) {
        return [string]::Format([Globalization.CultureInfo]::InvariantCulture, $template, $FormatArgs)
    }
    return $template
}

Select-Language
try { $Host.UI.RawUI.WindowTitle = Get-Text 'WindowTitle' } catch { }

function Write-Log {
    param([string]$Message)
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath (Join-Path $LogRoot 'BPSR-ImageChanger.log') -Value $line -Encoding UTF8
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-UiHeader {
    param([Parameter(Mandatory = $true)][string]$Title)
    $rule = '=' * 68
    Write-Host ''
    Write-Host $rule -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host $rule -ForegroundColor DarkCyan
}

function Write-UiSection {
    param([Parameter(Mandatory = $true)][string]$Title)
    Write-Host ''
    Write-Host "-- $Title" -ForegroundColor Cyan
    Write-Host ('-' * 68) -ForegroundColor DarkGray
}

function Write-UiField {
    param([Parameter(Mandatory = $true)][string]$Label, [AllowNull()][object]$Value)
    Write-Host ('  {0,-22} {1}' -f ($Label + ':'), $Value)
}

function Get-SteamLibraries {
    $steamRoots = @()
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        if (Test-Path -LiteralPath $key) {
            $entry = Get-ItemProperty -LiteralPath $key
            foreach ($property in @('SteamPath', 'InstallPath')) {
                $value = $entry.$property
                if ($value) { $steamRoots += ($value -replace '/', '\').TrimEnd('\') }
            }
        }
    }
    $programFiles32 = (Get-Item -Path 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue).Value
    if ($programFiles32) { $steamRoots += (Join-Path $programFiles32 'Steam') }
    $steamRoots = @($steamRoots | Where-Object { $_ } | Select-Object -Unique)

    $libraries = @()
    foreach ($steamRoot in $steamRoots) {
        $libraries += $steamRoot
        $config = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $config) {
            $vdf = Get-Content -LiteralPath $config -Raw
            foreach ($match in [regex]::Matches($vdf, '"path"\s+"([^"]+)"')) {
                $libraries += ($match.Groups[1].Value -replace '\\\\', '\')
            }
        }
    }
    @($libraries | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique)
}

function Get-GameInfo {
    $processes = @(Get-Process -Name 'BPSR_STEAM' -ErrorAction SilentlyContinue)
    $gameRoot = $null
    $manifestPath = $null
    $buildId = $null

    if ($processes.Count -eq 1) {
        try {
            if ($processes[0].Path) { $gameRoot = Split-Path -Parent $processes[0].Path }
        } catch { }
    } elseif ($processes.Count -gt 1) {
        throw (Get-Text 'GameMultipleInstances')
    }

    $libraries = @(Get-SteamLibraries)
    foreach ($library in $libraries) {
        $candidateManifest = Join-Path $library 'steamapps\appmanifest_3681810.acf'
        if (-not (Test-Path -LiteralPath $candidateManifest)) { continue }
        $manifest = Get-Content -LiteralPath $candidateManifest -Raw
        if ($manifest -notmatch '"appid"\s+"3681810"') { continue }
        if (-not $manifestPath) {
            $manifestPath = $candidateManifest
            $buildMatch = [regex]::Match($manifest, '"buildid"\s+"([^"]+)"')
            if ($buildMatch.Success) { $buildId = $buildMatch.Groups[1].Value }
        }
        if (-not $gameRoot) {
            $installMatch = [regex]::Match($manifest, '"installdir"\s+"([^"]+)"')
            if ($installMatch.Success) {
                $candidateRoot = Join-Path $library ('steamapps\common\' + $installMatch.Groups[1].Value + '\bpsr')
                if (Test-Path -LiteralPath (Join-Path $candidateRoot 'BPSR_STEAM.exe')) {
                    $gameRoot = $candidateRoot
                }
            }
        }
    }

    if (-not $gameRoot) {
        throw (Get-Text 'GameNotFound')
    }
    $container = Join-Path $gameRoot 'BPSR_STEAM_Data\StreamingAssets\container'
    $package = Join-Path $container 'm92.pkg'
    if (-not (Test-Path -LiteralPath $package)) { throw (Get-Text 'PackageNotFound' @($package)) }
    [pscustomobject]@{
        GameRoot   = $gameRoot
        Container  = $container
        Package    = $package
        Manifest   = $manifestPath
        BuildId    = $buildId
        IsRunning  = ($processes.Count -gt 0)
        ProcessIds = @($processes | ForEach-Object { $_.Id })
        SteamAppId = $AppId
    }
}

function Get-PngInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (Get-Text 'ImageNotFound' @($Path)) }
    try { Add-Type -AssemblyName System.Drawing.Common -ErrorAction Stop }
    catch { Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue }
    $image = [System.Drawing.Image]::FromFile($Path)
    try {
        if ($image.RawFormat.Guid.ToString() -ne 'b96b3caf-0728-11d3-9d7b-0000f81ef32e') {
            throw (Get-Text 'InvalidPng')
        }
        [pscustomobject]@{
            Path   = (Resolve-Path -LiteralPath $Path).Path
            Width  = $image.Width
            Height = $image.Height
            Bytes  = (Get-Item -LiteralPath $Path).Length
        }
    } finally { $image.Dispose() }
}

function Get-ExpectedDimensions {
    param([string]$Type)
    if ($Type -eq 'card') { return '1500x2500' }
    return '1500x1500'
}

function Get-AdminStatus {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Read-State {
    if (Test-Path -LiteralPath $StatePath) {
        try { return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) } catch { }
    }
    return $null
}

function Save-State {
    param($State)
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Set-StateProperty {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Value
    )
    if ($State -is [System.Collections.IDictionary]) {
        $State[$Name] = $Value
    } elseif ($State.PSObject.Properties[$Name]) {
        $State.$Name = $Value
    } else {
        Add-Member -InputObject $State -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Get-OriginalBackup {
    param($Game)
    $currentHash = (Get-FileHash -LiteralPath $Game.Package -Algorithm SHA256).Hash
    $previousState = Read-State
    if ($previousState -and $previousState.LastAppliedHash -eq $currentHash -and
        $previousState.OriginalBackupPath -and (Test-Path -LiteralPath $previousState.OriginalBackupPath)) {
        return [pscustomobject]@{ Path = $previousState.OriginalBackupPath; Hash = $previousState.BasePackageHash }
    }
    foreach ($candidate in @(Get-ChildItem -LiteralPath $BackupRoot -Filter 'm92*.pkg' -File -ErrorAction SilentlyContinue)) {
        $candidateHash = (Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash
        if ($candidateHash -eq $currentHash) {
            return [pscustomobject]@{ Path = $candidate.FullName; Hash = $candidateHash }
        }
    }
    $backupPath = Join-Path $BackupRoot ('m92-original-' + $currentHash.Substring(0, 12) + '.pkg')
    if (-not (Test-Path -LiteralPath $backupPath)) { Copy-Item -LiteralPath $Game.Package -Destination $backupPath }
    $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash
    if ($backupHash -ne $currentHash) { throw (Get-Text 'BackupMismatch') }
    [ordered]@{
        createdUtc = (Get-Date).ToUniversalTime().ToString('o')
        steamAppId = $AppId
        steamBuildId = $Game.BuildId
        sourcePath = $Game.Package
        backupPath = $backupPath
        sha256 = $backupHash
        assetToken = $AssetName
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($backupPath + '.json') -Encoding UTF8
    [pscustomobject]@{ Path = $backupPath; Hash = $backupHash }
}

function Resolve-Tool {
    param([string]$Name)
    $candidate = Join-Path $ProjectRoot $Name
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw (Get-Text 'ToolMissing' @($Name, $ProjectRoot))
    }
    $candidate
}

function Confirm-Launch {
    param([string]$Label)
    $answer = Read-Host (Get-Text 'LaunchConfirm' @($Label))
    $answer -match '^(s|si|sí|y|yes|o|oui)$'
}

function Read-YesNo {
    param([Parameter(Mandatory = $true)][string]$Prompt)
    Write-Host "  > $Prompt" -ForegroundColor Yellow
    while ($true) {
        $answer = (Read-Host (Get-Text 'ConfirmPrompt')).Trim().ToLowerInvariant()
        if ($answer -match '^(s|si|sí|y|yes|o|oui)$') { Write-Host (Get-Text 'Confirmed') -ForegroundColor Green; return $true }
        if ($answer -match '^(n|no|non)$') { Write-Host (Get-Text 'Cancelled') -ForegroundColor DarkYellow; return $false }
        Write-Host (Get-Text 'EnterYesNo') -ForegroundColor Yellow
    }
}

function Get-DefaultImagePath {
    if ($ImagePath) { return (Resolve-Path -LiteralPath $ImagePath).Path }
    if ($ImageType -eq 'portrait') {
        $portraitExample = Join-Path $ProjectRoot 'examples\Example-Portrait-1500x1500.png'
        if (Test-Path -LiteralPath $portraitExample) { return $portraitExample }
        return (Join-Path $ProjectRoot 'Joseleelsuper.png')
    }
    $default = Join-Path $ProjectRoot 'Joseleelsuper.png'
    if (Test-Path -LiteralPath $default) { return $default }
    $cardExample = Join-Path $ProjectRoot 'examples\Example-Card-1500x2500.png'
    if (Test-Path -LiteralPath $cardExample) { return $cardExample }
    Join-Path $ProjectRoot 'assets\Joseleelsuper.png'
}

function Write-PkgToolInstructions {
    param($Game, $Backup, $Image)
    $instructions = @(
        (Get-Text 'PkgTitle')
        ('=' * 36)
        ''
        (Get-Text 'PkgGamePackage' @('m92.pkg'))
        (Get-Text 'PkgOriginalCopy' @($Backup.Path))
        (Get-Text 'PkgPreparedCopy' @((Join-Path $WorkRoot 'm92.pkg')))
        (Get-Text 'PkgImage' @((Join-Path $WorkRoot 'custom.png')))
        (Get-Text 'PkgTextureKey' @($AssetName))
        ''
        (Get-Text 'PkgOpenInfo')
        ('  ' + (Join-Path $ProjectRoot 'PKGcontrolV6RC32Lite.exe'))
        ''
        (Get-Text 'PkgSteps')
        ('  2, ' + (Get-Text 'EnterKey'))
        ('  ' + (Join-Path $WorkRoot 'm92.pkg') + ', ' + (Get-Text 'EnterKey'))
        ('  ' + $AssetName + ', ' + (Get-Text 'EnterKey'))
        ('  ' + (Join-Path $WorkRoot 'custom.png') + ', ' + (Get-Text 'EnterTwice'))
        ('  N, ' + (Get-Text 'EnterKey'))
        ('  N, ' + (Get-Text 'EnterKey'))
        ''
        (Get-Text 'PkgWorkDirInfo')
        'm92_mod.pkg'
        (Get-Text 'PkgDoNotReplace')
    ) -join [Environment]::NewLine
    Set-Content -LiteralPath (Join-Path $WorkRoot 'PKGcontrol-pasos.txt') -Value $instructions -Encoding UTF8
}

function Invoke-Status {
    if ($Action -eq 'status') { Write-UiHeader -Title (Get-Text 'StatusTitle') }
    $game = Get-GameInfo
    $image = $null
    try { $image = Get-PngInfo -Path (Get-DefaultImagePath) } catch { }
    $tools = foreach ($name in @('PKGcontrolV6RC32Lite.exe', 'WindowResizer.exe')) {
        $path = Join-Path $ProjectRoot $name
        if (Test-Path -LiteralPath $path) {
            $signature = Get-AuthenticodeSignature -LiteralPath $path
            [pscustomobject]@{ Name = $name; Present = $true; Signature = $signature.Status; Bytes = (Get-Item -LiteralPath $path).Length }
        } else {
            [pscustomobject]@{ Name = $name; Present = $false; Signature = 'n/a'; Bytes = 0 }
        }
    }
    Write-UiSection -Title (Get-Text 'SectionInstallation')
    Write-UiField -Label (Get-Text 'FieldAppId') -Value $game.SteamAppId
    Write-UiField -Label (Get-Text 'FieldBuild') -Value $game.BuildId
    Write-UiField -Label (Get-Text 'FieldGameFolder') -Value $game.GameRoot
    Write-UiField -Label (Get-Text 'FieldTargetPackage') -Value $game.Package
    Write-UiField -Label (Get-Text 'FieldCurrentHash') -Value ((Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash)
    if ($game.IsRunning) {
        Write-Host ('  ' + (Get-Text 'GameRunningYes' @($game.ProcessIds -join ', '))) -ForegroundColor Yellow
    } else {
        Write-Host ('  ' + (Get-Text 'GameRunningNo')) -ForegroundColor Green
    }

    Write-UiSection -Title (Get-Text 'SectionImage')
    if ($image) {
        Write-UiField -Label (Get-Text 'FieldDimensions') -Value ('{0}x{1}' -f $image.Width, $image.Height)
        Write-UiField -Label (Get-Text 'FieldFile') -Value $image.Path
    } else {
        Write-Host ('  ' + (Get-Text 'NoDefaultPng')) -ForegroundColor Yellow
    }

    Write-UiSection -Title (Get-Text 'SectionTools')
    foreach ($tool in $tools) {
        if (-not $tool.Present) {
            Write-Host ('  ' + (Get-Text 'ToolMissingStatus' @($tool.Name))) -ForegroundColor Red
        } else {
            $sizeMiB = [math]::Round($tool.Bytes / 1MB, 1)
            $color = if ($tool.Signature -eq 'Valid') { 'Green' } else { 'Yellow' }
            Write-Host ('  ' + (Get-Text 'ToolPresentStatus' @($tool.Name, $tool.Signature, $sizeMiB))) -ForegroundColor $color
        }
    }
}

function Invoke-Prepare {
    $game = Get-GameInfo
    $imageFile = Get-DefaultImagePath
    $image = Get-PngInfo -Path $imageFile
    $expected = Get-ExpectedDimensions -Type $ImageType
    $actual = '{0}x{1}' -f $image.Width, $image.Height
    if ($actual -ne $expected) { throw (Get-Text 'PrepareWrongDimensions' @($ImageType, $expected, $actual)) }
    $backup = Get-OriginalBackup -Game $game
    Copy-Item -LiteralPath $backup.Path -Destination (Join-Path $WorkRoot 'm92.pkg') -Force
    Copy-Item -LiteralPath $image.Path -Destination (Join-Path $WorkRoot 'custom.png') -Force
    $previousState = Read-State
    $lastAppliedHash = $null
    if ($previousState -and $previousState.LastAppliedHash -eq (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash) {
        $lastAppliedHash = $previousState.LastAppliedHash
    }
    $state = [ordered]@{
        Version = 1; SteamAppId = $game.SteamAppId; SteamBuildId = $game.BuildId
        GameRoot = $game.GameRoot; Container = $game.Container; PackagePath = $game.Package
        AssetName = $AssetName; ImageType = $ImageType; ImagePath = $image.Path
        ImageSha256 = (Get-FileHash -LiteralPath $image.Path -Algorithm SHA256).Hash
        BasePackageHash = $backup.Hash; OriginalBackupPath = $backup.Path
        LastAppliedHash = $lastAppliedHash; LastAppliedUtc = $null; LastPreInstallBackup = $null
        RestoredUtc = $null; PreparedUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Save-State -State $state
    Write-PkgToolInstructions -Game $game -Backup $backup -Image $image
    Write-Log (Get-Text 'PrepareLog' @($actual, (Join-Path $WorkRoot 'm92.pkg')))
    Write-Host (Get-Text 'OriginalCopyVerified' @($backup.Path))
    Write-Host (Get-Text 'FollowPkgSteps' @((Join-Path $WorkRoot 'PKGcontrol-pasos.txt')))
    Write-Host (Get-Text 'AfterPkgSteps')
}

function Invoke-LaunchPkgControl {
    param([switch]$Confirmed)
    $tool = Resolve-Tool -Name 'PKGcontrolV6RC32Lite.exe'
    if (-not (Test-Path -LiteralPath (Join-Path $WorkRoot 'm92.pkg'))) { throw (Get-Text 'PrepareFirst') }
    if (-not $Confirmed -and -not (Confirm-Launch -Label 'PKGcontrolV6RC32Lite.exe')) { Write-Host (Get-Text 'LaunchDeclined'); return }
    $instructionsPath = Join-Path $WorkRoot 'PKGcontrol-pasos.txt'
    if (-not (Test-Path -LiteralPath $instructionsPath -PathType Leaf)) {
        $state = Read-State
        if (-not $state -or -not $state.OriginalBackupPath) { throw (Get-Text 'PrepareFirst') }
        $backup = [pscustomobject]@{ Path = $state.OriginalBackupPath }
        Write-PkgToolInstructions -Game $null -Backup $backup -Image $null
    }
    Start-Process -FilePath 'notepad.exe' -ArgumentList ('"{0}"' -f $instructionsPath)
    Start-Process -FilePath $tool -WorkingDirectory $WorkRoot
    Write-Log (Get-Text 'LaunchPkgLog')
}

function Invoke-LaunchWindowResizer {
    param([switch]$Confirmed)
    $tool = Resolve-Tool -Name 'WindowResizer.exe'
    if (-not $Confirmed -and -not (Confirm-Launch -Label 'WindowResizer.exe')) { Write-Host (Get-Text 'LaunchDeclined'); return }
    Start-Process -FilePath $tool -WorkingDirectory $ProjectRoot -Verb RunAs
    Write-Log (Get-Text 'LaunchWindowLog')
}

function Invoke-Install {
    if (-not (Get-AdminStatus)) { throw (Get-Text 'AdminInstallRequired') }
    $game = Get-GameInfo
    if ($game.IsRunning) { throw (Get-Text 'GameMustCloseInstall' @($game.ProcessIds -join ', ')) }
    $state = Read-State
    if (-not $state -or -not (Test-Path -LiteralPath $state.OriginalBackupPath)) { throw (Get-Text 'PrepareFirst') }
    $modified = if ($ModifiedPackage) { (Resolve-Path -LiteralPath $ModifiedPackage).Path } else { Join-Path $WorkRoot 'm92_mod.pkg' }
    if (-not (Test-Path -LiteralPath $modified -PathType Leaf)) { throw (Get-Text 'ModifiedPackageMissing' @($modified)) }
    $modifiedHash = (Get-FileHash -LiteralPath $modified -Algorithm SHA256).Hash
    if ($modifiedHash -eq $state.BasePackageHash) { throw (Get-Text 'ModifiedIsOriginal') }
    if ((Get-Item -LiteralPath $modified).Length -lt 1048576) { throw (Get-Text 'ModifiedTooSmall') }
    $installedHash = (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash
    $knownHashes = @($state.BasePackageHash, $state.LastAppliedHash) | Where-Object { $_ }
    if (($knownHashes -notcontains $installedHash) -and -not $Force) {
        throw (Get-Text 'InstalledPackageChanged')
    }

    $beforeDir = Join-Path $ProjectRoot 'backups\before-install'
    New-Item -ItemType Directory -Path $beforeDir -Force | Out-Null
    $before = Join-Path $beforeDir ('m92-before-install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.pkg')
    Copy-Item -LiteralPath $game.Package -Destination $before
    if ((Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash -ne $installedHash) { throw (Get-Text 'PreInstallBackupMismatch') }
    $temporary = Join-Path $game.Container ('m92.pkg.BPSR-ImageChanger-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $modified -Destination $temporary
    if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $modifiedHash) {
        Remove-Item -LiteralPath $temporary -Force
        throw (Get-Text 'TemporaryPackageMismatch')
    }
    Move-Item -LiteralPath $temporary -Destination $game.Package -Force
    if ((Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash -ne $modifiedHash) { throw (Get-Text 'PostInstallMismatch') }
    Set-StateProperty -State $state -Name 'LastAppliedHash' -Value $modifiedHash
    Set-StateProperty -State $state -Name 'LastAppliedUtc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
    Set-StateProperty -State $state -Name 'LastPreInstallBackup' -Value $before
    Save-State -State $state
    Write-Log (Get-Text 'InstallLog' @($before))
}

function Invoke-Restore {
    if (-not (Get-AdminStatus)) { throw (Get-Text 'AdminRestoreRequired') }
    $game = Get-GameInfo
    if ($game.IsRunning) { throw (Get-Text 'GameMustCloseRestore' @($game.ProcessIds -join ', ')) }
    $state = Read-State
    $backup = if ($state -and $state.OriginalBackupPath) { $state.OriginalBackupPath } else { Join-Path $BackupRoot 'm92.pkg' }
    if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw (Get-Text 'OriginalBackupMissing' @($backup)) }
    $backupHash = (Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash
    if ($state -and $state.BasePackageHash -and $backupHash -ne $state.BasePackageHash) { throw (Get-Text 'OriginalBackupHashMismatch') }
    $currentHash = (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash
    $beforeDir = Join-Path $ProjectRoot 'backups\before-restore'
    New-Item -ItemType Directory -Path $beforeDir -Force | Out-Null
    $before = Join-Path $beforeDir ('m92-before-restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.pkg')
    Copy-Item -LiteralPath $game.Package -Destination $before
    if ((Get-FileHash -LiteralPath $before -Algorithm SHA256).Hash -ne $currentHash) { throw (Get-Text 'PreRestoreBackupMismatch') }
    $temporary = Join-Path $game.Container ('m92.pkg.BPSR-ImageChanger-' + [guid]::NewGuid().ToString('N') + '.tmp')
    Copy-Item -LiteralPath $backup -Destination $temporary
    Move-Item -LiteralPath $temporary -Destination $game.Package -Force
    if ((Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash -ne $backupHash) { throw (Get-Text 'PostRestoreMismatch') }
    if ($state) {
        Set-StateProperty -State $state -Name 'LastAppliedHash' -Value $null
        Set-StateProperty -State $state -Name 'RestoredUtc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
        Save-State -State $state
    }
    Write-Log (Get-Text 'RestoreLog' @($before))
}

function Wait-ForGameClosed {
    while ($true) {
        $game = Get-GameInfo
        if (-not $game.IsRunning) { return $game }
        Write-Host (Get-Text 'WaitForGame' @($game.ProcessIds -join ', '))
        $answer = Read-Host (Get-Text 'WaitForGamePrompt')
        if ($answer.Trim() -match '^(x|cancelar|cancel|annuler)$') { throw (Get-Text 'ActionCancelled') }
    }
}

function Invoke-PrivilegedAction {
    param([ValidateSet('install', 'restore')][string]$PrivilegedAction)
    if (Get-AdminStatus) {
        if ($PrivilegedAction -eq 'install') { Invoke-Install } else { Invoke-Restore }
        return
    }

    Write-Host (Get-Text 'UacNotice')
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Action {1} -LanguageCode {2}' -f $PSCommandPath, $PrivilegedAction, $script:SelectedLanguageCode
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $ProjectRoot -Verb RunAs -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw (Get-Text 'ElevatedActionFailed' @($PrivilegedAction, $process.ExitCode)) }
}

function Show-CaptureSteps {
    Write-UiSection -Title (Get-Text 'CaptureTitle')
    if ($ImageType -eq 'card') { Write-Host (Get-Text 'CaptureCard') }
    else { Write-Host (Get-Text 'CapturePortrait') }
}

function Invoke-ReviewedRestore {
    param($State)
    if (-not $State -or -not $State.BasePackageHash) { throw (Get-Text 'NoPreparedOriginal') }
    Write-Host (Get-Text 'RestorePreview' @($State.OriginalBackupPath))
    Wait-ForGameClosed | Out-Null
    Invoke-PrivilegedAction -PrivilegedAction 'restore'
    $game = Get-GameInfo
    $restoredHash = (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash
    if ($restoredHash -ne $State.BasePackageHash) { throw (Get-Text 'RestoreHashMismatch') }
    Write-Host (Get-Text 'RestoredVerified') -ForegroundColor Green
}

function Invoke-CaptureAndRestore {
    Show-CaptureSteps
    if (Read-YesNo (Get-Text 'OpenWindowResizerPrompt')) {
        Invoke-LaunchWindowResizer -Confirmed
    }
    Write-Host ''
    Write-Host (Get-Text 'CloseGameAfterPhoto')
    $answer = Read-Host (Get-Text 'RestorePrompt')
    if ($answer.Trim().ToUpperInvariant() -notin @('RESTAURAR', 'RESTORE', 'RESTAURER')) {
        Write-Host (Get-Text 'PackageRemainsInstalled') -ForegroundColor Yellow
        return
    }
    Invoke-ReviewedRestore -State (Read-State)
}

function Invoke-Wizard {
    Write-UiHeader -Title (Get-Text 'WizardTitle')
    $state = Read-State
    if ($state -and $state.LastAppliedHash) {
        try {
            $game = Get-GameInfo
            $installedHash = (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash
        } catch { $installedHash = $null }
        if ($installedHash -and $installedHash -eq $state.LastAppliedHash) {
            if ($state.ImageType -in @('card', 'portrait')) { $script:ImageType = $state.ImageType }
            Write-UiSection -Title (Get-Text 'CustomPackageDetected')
            Write-UiField -Label (Get-Text 'FieldPackage') -Value $game.Package
            Write-UiField -Label 'SHA-256' -Value $installedHash
            Write-Host ''
            Write-Host (Get-Text 'InstalledPackageMenu')
            $resume = (Read-Host (Get-Text 'Choose123')).Trim()
            if ($resume -eq '1') { Invoke-CaptureAndRestore; return }
            if ($resume -eq '2') {
                if (Read-YesNo (Get-Text 'ConfirmRestoreOriginal')) { Invoke-ReviewedRestore -State $state }
                return
            }
            Write-Host (Get-Text 'NoChangesMade')
            return
        }
    }

    Write-UiSection -Title (Get-Text 'InitialCheck')
    Invoke-Status

    Write-UiSection -Title (Get-Text 'StageSelectImage')
    Write-Host (Get-Text 'ChooseImageUse') -ForegroundColor Gray
    Write-Host (Get-Text 'ImageChoiceCard')
    Write-Host (Get-Text 'ImageChoicePortrait')
    $typeDefault = if ($ImageType -eq 'portrait') { '2' } else { '1' }
    while ($true) {
        $typeChoice = (Read-Host (Get-Text 'ImageTypePrompt' @($typeDefault))).Trim()
        if (-not $typeChoice) { $typeChoice = $typeDefault }
        if ($typeChoice -eq '1') { $script:ImageType = 'card'; break }
        if ($typeChoice -eq '2') { $script:ImageType = 'portrait'; break }
        Write-Host (Get-Text 'Choose12') -ForegroundColor Yellow
    }

    $suggestedImage = if ($ImagePath) { $ImagePath } else { Get-DefaultImagePath }
    Write-Host (Get-Text 'SuggestedImage' @($suggestedImage)) -ForegroundColor Gray
    $imageInput = Read-Host (Get-Text 'ImagePathPrompt')
    if ($imageInput.Trim()) {
        $script:ImagePath = $imageInput.Trim().Trim('"')
        if (-not [IO.Path]::IsPathRooted($script:ImagePath)) { $script:ImagePath = Join-Path $ProjectRoot $script:ImagePath }
    } elseif (-not $ImagePath) {
        $script:ImagePath = $suggestedImage
    }

    $game = Get-GameInfo
    $image = Get-PngInfo -Path (Get-DefaultImagePath)
    $expected = Get-ExpectedDimensions -Type $ImageType
    $actual = '{0}x{1}' -f $image.Width, $image.Height
    if ($actual -ne $expected) { throw (Get-Text 'WizardWrongDimensions' @($actual, $ImageType, $expected)) }
    $packageHash = (Get-FileHash -LiteralPath $game.Package -Algorithm SHA256).Hash

    Write-UiSection -Title (Get-Text 'StageReviewBeforePrepare')
    $imageTypeLabel = if ($ImageType -eq 'card') { Get-Text 'ImageTypeCard' } else { Get-Text 'ImageTypePortrait' }
    Write-UiField -Label (Get-Text 'FieldImageType') -Value "$imageTypeLabel ($expected)"
    Write-UiField -Label (Get-Text 'FieldImage') -Value $image.Path
    Write-UiField -Label (Get-Text 'FieldAppIdBuild') -Value "$($game.SteamAppId) / $($game.BuildId)"
    Write-UiField -Label (Get-Text 'FieldTargetPackage') -Value $game.Package
    Write-UiField -Label (Get-Text 'FieldCurrentHash') -Value $packageHash
    $runningLabel = if ($game.IsRunning) { Get-Text 'GameRunningYesShort' @($game.ProcessIds -join ', ') } else { Get-Text 'GameRunningNoShort' }
    $runningColor = if ($game.IsRunning) { 'Yellow' } else { 'Green' }
    Write-Host (Get-Text 'GameRunningField' @($runningLabel)) -ForegroundColor $runningColor
    if (-not (Read-YesNo (Get-Text 'ConfirmPrepare'))) {
        Write-Host (Get-Text 'PrepareCancelled')
        return
    }

    Invoke-Prepare
    Write-UiSection -Title (Get-Text 'StagePrepareComplete')

    $modifiedPath = Join-Path $WorkRoot 'm92_mod.pkg'
    $useExisting = $false
    if (Test-Path -LiteralPath $modifiedPath -PathType Leaf) {
        $existing = Get-Item -LiteralPath $modifiedPath
        $existingHash = (Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash
        Write-UiSection -Title (Get-Text 'PreviousPkgResult')
        Write-UiField -Label (Get-Text 'FieldFile') -Value $modifiedPath
        Write-UiField -Label (Get-Text 'FieldModified') -Value $existing.LastWriteTime
        Write-UiField -Label (Get-Text 'FieldSize') -Value ('{0:N1} MiB' -f ($existing.Length / 1MB))
        Write-UiField -Label 'SHA-256' -Value $existingHash
        $preparedState = Read-State
        Write-UiField -Label (Get-Text 'FieldPreparedBaseHash') -Value $preparedState.BasePackageHash
        $useExisting = Read-YesNo (Get-Text 'UsePreviousResultPrompt')
        if (-not $useExisting) {
            $archive = Join-Path $WorkRoot ('m92_mod-previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.pkg')
            Move-Item -LiteralPath $modifiedPath -Destination $archive
            Write-Host (Get-Text 'PreviousResultArchived' @($archive))
        }
    }

    if (-not $useExisting) {
        Write-Host (Get-Text 'PkgUnsignedNotice') -ForegroundColor Yellow
        if (Read-YesNo (Get-Text 'OpenPkgControlPrompt')) {
            Invoke-LaunchPkgControl -Confirmed
        } else {
            Write-Host (Get-Text 'OpenPkgControlManually')
        }
        Write-Host (Get-Text 'FollowPkgSteps' @((Join-Path $WorkRoot 'PKGcontrol-pasos.txt')))
        [void](Read-Host (Get-Text 'PkgFinishedPrompt'))
        if (-not (Test-Path -LiteralPath $modifiedPath -PathType Leaf)) { throw (Get-Text 'ModifiedResultMissing' @($modifiedPath)) }
    }

    $modifiedHash = (Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash
    $modifiedBytes = (Get-Item -LiteralPath $modifiedPath).Length
    $state = Read-State
    if ($modifiedHash -eq $state.BasePackageHash) { throw (Get-Text 'ModifiedIsOriginal') }
    if ($modifiedBytes -lt 1048576) { throw (Get-Text 'ModifiedTooSmall') }
    Write-UiSection -Title (Get-Text 'StageReviewBeforeInstall')
    Write-UiField -Label (Get-Text 'FieldResult') -Value $modifiedPath
    Write-UiField -Label (Get-Text 'FieldSize') -Value ('{0:N1} MiB' -f ($modifiedBytes / 1MB))
    Write-UiField -Label 'SHA-256' -Value $modifiedHash
    Write-UiField -Label (Get-Text 'FieldDestination') -Value $game.Package
    Write-Host (Get-Text 'GameMustBeClosed') -ForegroundColor Gray
    if (-not (Read-YesNo (Get-Text 'InstallResultPrompt'))) {
        Write-Host (Get-Text 'InstallCancelled')
        return
    }
    Wait-ForGameClosed | Out-Null
    Invoke-PrivilegedAction -PrivilegedAction 'install'
    $installedGame = Get-GameInfo
    $installedHash = (Get-FileHash -LiteralPath $installedGame.Package -Algorithm SHA256).Hash
    if ($installedHash -ne $modifiedHash) { throw (Get-Text 'InstallReviewMismatch') }
    Write-Host (Get-Text 'InstallHashVerified') -ForegroundColor Green
    Invoke-CaptureAndRestore
}

function Show-Guide {
    Get-Text 'ManualGuide'
}

switch ($Action) {
    'wizard'               { Invoke-Wizard }
    'status'               { Invoke-Status }
    'prepare'              { Invoke-Prepare }
    'launch-pkgcontrol'    { Invoke-LaunchPkgControl }
    'launch-windowresizer' { Invoke-LaunchWindowResizer }
    'install'              { Invoke-Install }
    'restore'              { Invoke-Restore }
    'guide'                { Show-Guide }
}
