[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('config', 'sync', 'package', 'release', 'publish', 'steam-readme')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$ChangeNote,

    [string]$ProfileId,

    [switch]$Packaged,
    [switch]$Repack,
    [string]$ToolsPath,
    [string]$XRCatToolPath,
    [string]$WorkshopToolPath,
    [switch]$KeepVersion,
    [switch]$UpdateNameAndDescription,

    [Parameter(DontShow)]
    [string]$X4Root
)

$ErrorActionPreference = 'Stop'

$sourceRoot = Join-Path $PSScriptRoot 'src'
$releaseRoot = Join-Path $PSScriptRoot 'dist'
$packageRoot = Join-Path $PSScriptRoot 'dist\tradesub_renew'
$configPath = Join-Path $PSScriptRoot '.tools.ini'
. (Join-Path $PSScriptRoot 'tools-config.ps1')

function Get-ConfiguredToolPath {
    param(
        [System.Collections.IDictionary]$Settings,
        [Parameter(Mandatory)][string]$SettingName,
        [Parameter(Mandatory)][string]$ToolName
    )

    $configuredPath = $Settings[$SettingName]
    if ([string]::IsNullOrWhiteSpace($configuredPath)) {
        throw "$ToolName is not configured. Run either:`n.\tool.ps1 config -ToolsPath `"<X Tools directory>`"`nor:`n.\tool.ps1 config -${SettingName} `"<path-to-$ToolName.exe>`""
    }
    if (-not (Test-Path -LiteralPath $configuredPath -PathType Leaf)) {
        throw "$ToolName is configured but does not exist: $configuredPath`nRun .\tool.ps1 config to set a valid path."
    }
    return (Resolve-Path -LiteralPath $configuredPath).Path
}

function Resolve-NamedExecutable {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedName
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "Tool path must identify a file: $Path"
    }
    if ([IO.Path]::GetFileName($resolvedPath) -cne $ExpectedName) {
        throw "Tool path must end with $ExpectedName`: $Path"
    }
    return $resolvedPath
}

function Invoke-Config {
    param([System.Collections.IDictionary]$Settings)

    if ([string]::IsNullOrWhiteSpace($ProfileId) -and
        [string]::IsNullOrWhiteSpace($ToolsPath) -and
        [string]::IsNullOrWhiteSpace($XRCatToolPath) -and
        [string]::IsNullOrWhiteSpace($WorkshopToolPath)) {
        throw 'No configuration was supplied. Set ProfileId, ToolsPath, XRCatToolPath, or WorkshopToolPath.'
    }

    $updates = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($ProfileId)) {
        if ($ProfileId -notmatch '^\d+$') {
            throw 'ProfileId must contain digits only.'
        }
        $updates['ProfileId'] = $ProfileId
    }

    if (-not [string]::IsNullOrWhiteSpace($ToolsPath)) {
        $resolvedToolsPath = (Resolve-Path -LiteralPath $ToolsPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolvedToolsPath -PathType Container)) {
            throw "ToolsPath must identify a directory: $ToolsPath"
        }
        $catalogCandidate = Join-Path $resolvedToolsPath 'XRCatTool.exe'
        $workshopCandidate = Join-Path $resolvedToolsPath 'WorkshopTool.exe'
        if (Test-Path -LiteralPath $catalogCandidate -PathType Leaf) {
            $updates['XRCatToolPath'] = (Resolve-Path -LiteralPath $catalogCandidate).Path
        }
        if (Test-Path -LiteralPath $workshopCandidate -PathType Leaf) {
            $updates['WorkshopToolPath'] = (Resolve-Path -LiteralPath $workshopCandidate).Path
        }
        if (-not $updates.Contains('XRCatToolPath') -and -not $updates.Contains('WorkshopToolPath')) {
            throw "ToolsPath contains neither XRCatTool.exe nor WorkshopTool.exe: $resolvedToolsPath"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($XRCatToolPath)) {
        $updates['XRCatToolPath'] = Resolve-NamedExecutable -Path $XRCatToolPath -ExpectedName 'XRCatTool.exe'
    }
    if (-not [string]::IsNullOrWhiteSpace($WorkshopToolPath)) {
        $updates['WorkshopToolPath'] = Resolve-NamedExecutable -Path $WorkshopToolPath -ExpectedName 'WorkshopTool.exe'
    }

    $Settings.Remove('XToolsPath')
    foreach ($key in $updates.Keys) {
        $Settings[$key] = $updates[$key]
    }
    Write-ToolsConfig -Path $configPath -Settings $Settings
    Write-Host "Configuration saved at: $configPath"
}

function Invoke-Package {
    param([System.Collections.IDictionary]$Settings)

    $catalogTool = Get-ConfiguredToolPath -Settings $Settings -SettingName 'XRCatToolPath' -ToolName 'XRCatTool'
    $installerPath = Join-Path $PSScriptRoot 'install.ps1'
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "Required release installer does not exist: $installerPath"
    }
    $manifestPath = Join-Path $sourceRoot 'content.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required mod manifest does not exist: $manifestPath"
    }

    foreach ($directory in @('aiscripts', 'libraries', 't')) {
        $directoryPath = Join-Path $sourceRoot $directory
        if (-not (Test-Path -LiteralPath $directoryPath -PathType Container)) {
            throw "Required mod directory does not exist: $directoryPath"
        }
    }

    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    Get-ChildItem -LiteralPath $packageRoot -Force | Remove-Item -Recurse -Force
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $packageRoot 'content.xml')

    $previewPath = Join-Path $sourceRoot 'preview.png'
    if (Test-Path -LiteralPath $previewPath -PathType Leaf) {
        Copy-Item -LiteralPath $previewPath -Destination (Join-Path $packageRoot 'preview.png')
    }

    $catalogPath = Join-Path $packageRoot 'ext_01.cat'
    $global:LASTEXITCODE = 0
    & $catalogTool -in $sourceRoot -out $catalogPath -include '^(aiscripts|libraries|t)/'
    if ($LASTEXITCODE -ne 0) {
        throw "XRCatTool failed with exit code $LASTEXITCODE."
    }

    $dataPath = [IO.Path]::ChangeExtension($catalogPath, '.dat')
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf) -or
        -not (Test-Path -LiteralPath $dataPath -PathType Leaf)) {
        throw 'XRCatTool did not create ext_01.cat and ext_01.dat.'
    }

    Copy-Item -LiteralPath $installerPath -Destination (Join-Path $releaseRoot 'install.ps1') -Force

    Write-Host "Trade Subscription Renew release packaged at: $releaseRoot"
}

function Invoke-Release {
    param([System.Collections.IDictionary]$Settings)

    $manifestPath = Join-Path $sourceRoot 'content.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required mod manifest does not exist: $manifestPath"
    }
    [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
    $version = [string]$manifest.content.version
    if ($version -notmatch '^\d+$') {
        throw 'The content.xml version must contain digits only.'
    }

    Invoke-Package -Settings $Settings

    $archivePath = Join-Path $releaseRoot "release_v$version.zip"
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }
    Compress-Archive -LiteralPath @(
        (Join-Path $releaseRoot 'install.ps1'),
        $packageRoot
    ) -DestinationPath $archivePath -CompressionLevel Optimal

    Write-Host "Trade Subscription Renew release archive created at: $archivePath"
}

function Invoke-SteamReadme {
    $readmePath = Join-Path $PSScriptRoot 'README.md'
    if (-not (Test-Path -LiteralPath $readmePath -PathType Leaf)) {
        throw "Required README does not exist: $readmePath"
    }
    $steamReadmePath = Join-Path $releaseRoot 'README.steam.txt'
    $converterPath = Join-Path $PSScriptRoot 'convert-markdown-to-steam.ps1'
    if (-not (Test-Path -LiteralPath $converterPath -PathType Leaf)) {
        throw "Required Markdown converter does not exist: $converterPath"
    }
    & $converterPath -InputPath $readmePath -OutputPath $steamReadmePath
}

function Invoke-Sync {
    param([System.Collections.IDictionary]$Settings)

    if ($Repack -and -not $Packaged) {
        throw 'Repack can only be used with Packaged.'
    }
    $selectedSourceRoot = if ($Packaged) { $packageRoot } else { $sourceRoot }
    $configuredProfileId = $Settings['ProfileId']
    if ([string]::IsNullOrWhiteSpace($configuredProfileId)) {
        throw "ProfileId is not configured. Run:`n.\tool.ps1 config -ProfileId <player-id>"
    }
    if ($configuredProfileId -notmatch '^\d+$') {
        throw 'Cached ProfileId must contain digits only.'
    }
    if ($Repack) {
        Get-ConfiguredToolPath -Settings $Settings -SettingName 'XRCatToolPath' -ToolName 'XRCatTool' | Out-Null
        Invoke-Package -Settings $Settings
    }

    if ([string]::IsNullOrWhiteSpace($X4Root)) {
        $script:X4Root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Egosoft\X4'
    }
    $resolvedX4Root = (Resolve-Path -LiteralPath $X4Root).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $x4Prefix = $resolvedX4Root + [IO.Path]::DirectorySeparatorChar
    $profileCandidate = Join-Path $resolvedX4Root $configuredProfileId
    if (-not (Test-Path -LiteralPath $profileCandidate -PathType Container)) {
        throw "X4 profile directory does not exist: $profileCandidate"
    }
    $profileRoot = (Resolve-Path -LiteralPath $profileCandidate).Path
    if (-not $profileRoot.StartsWith($x4Prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "X4 profile path must stay under: $resolvedX4Root"
    }

    $extensionsCandidate = Join-Path $profileRoot 'extensions'
    $extensionsRoot = if (Test-Path -LiteralPath $extensionsCandidate -PathType Container) {
        (Resolve-Path -LiteralPath $extensionsCandidate).Path
    } else {
        [IO.Path]::GetFullPath($extensionsCandidate)
    }
    $destinationCandidate = Join-Path $extensionsRoot 'tradesub_renew'
    $destinationRoot = if (Test-Path -LiteralPath $destinationCandidate -PathType Container) {
        (Resolve-Path -LiteralPath $destinationCandidate).Path
    } else {
        [IO.Path]::GetFullPath($destinationCandidate)
    }
    if (-not $extensionsRoot.StartsWith($x4Prefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $destinationRoot.StartsWith($x4Prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Sync destination must stay under: $resolvedX4Root"
    }

    $manifestPath = Join-Path $selectedSourceRoot 'content.xml'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Required mod manifest does not exist: $manifestPath"
    }
    if ($Packaged) {
        foreach ($fileName in @('ext_01.cat', 'ext_01.dat')) {
            $packageFile = Join-Path $selectedSourceRoot $fileName
            if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) {
                throw "Required packaged mod file does not exist: $packageFile"
            }
        }
    }

    if (Test-Path -LiteralPath $destinationRoot) {
        Remove-Item -LiteralPath $destinationRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($sourceFile in Get-ChildItem -LiteralPath $selectedSourceRoot -Recurse -File) {
        $relativePath = [IO.Path]::GetRelativePath($selectedSourceRoot, $sourceFile.FullName)
        $destinationPath = Join-Path $destinationRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
        Write-Host "Synced $relativePath"
    }

    $mode = if ($Packaged) { 'packaged' } else { 'loose' }
    Write-Host "Trade Subscription Renew synced in $mode mode to: $destinationRoot"
}

function Assert-ValidPreview {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required Workshop preview does not exist: $Path"
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
    if ($bytes.Length -lt $signature.Length) {
        throw "Workshop preview is not a valid PNG file: $Path"
    }
    for ($index = 0; $index -lt $signature.Length; $index++) {
        if ($bytes[$index] -ne $signature[$index]) {
            throw "Workshop preview is not a valid PNG file: $Path"
        }
    }
}

function Invoke-Publish {
    param([System.Collections.IDictionary]$Settings)

    $sourceManifestPath = Join-Path $sourceRoot 'content.xml'
    $sourcePreviewPath = Join-Path $sourceRoot 'preview.png'
    Assert-ValidPreview -Path $sourcePreviewPath
    [xml]$sourceManifest = Get-Content -LiteralPath $sourceManifestPath -Raw
    $isUpdate = $sourceManifest.content.id -match '^ws_\d+$'
    if ($isUpdate -and [string]::IsNullOrWhiteSpace($ChangeNote)) {
        throw 'A change note is required when updating an existing Workshop item.'
    }
    if (-not $isUpdate -and ($KeepVersion -or $UpdateNameAndDescription)) {
        throw 'KeepVersion and UpdateNameAndDescription can only be used for an existing Workshop item.'
    }

    Get-ConfiguredToolPath -Settings $Settings -SettingName 'XRCatToolPath' -ToolName 'XRCatTool' | Out-Null
    $workshopTool = Get-ConfiguredToolPath -Settings $Settings -SettingName 'WorkshopToolPath' -ToolName 'WorkshopTool'
    Invoke-Package -Settings $Settings
    $stagedManifestPath = Join-Path $packageRoot 'content.xml'
    $stagedPreviewPath = Join-Path $packageRoot 'preview.png'
    [xml]$stagedManifest = Get-Content -LiteralPath $stagedManifestPath -Raw

    $arguments = if ($isUpdate) {
        if (-not $KeepVersion) {
            $version = 0
            if (-not [int]::TryParse($stagedManifest.content.version, [ref]$version)) {
                throw 'The content.xml version must be an integer.'
            }
            $stagedManifest.content.version = [string]($version + 1)
            $stagedManifest.Save($stagedManifestPath)
        }
        $updateArguments = @('update', '-path', $packageRoot, '-changenote', $ChangeNote, '-preview', $stagedPreviewPath)
        if ($KeepVersion) {
            $updateArguments += '-minor'
        }
        if ($UpdateNameAndDescription) {
            $updateArguments += @('-namedesc', 'up')
        }
        $updateArguments
    } else {
        @('publishx4', '-path', $packageRoot, '-preview', $stagedPreviewPath)
    }

    $manifestBeforeUpload = Get-Content -LiteralPath $stagedManifestPath -Raw
    $global:LASTEXITCODE = 0
    & $workshopTool @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "WorkshopTool failed with exit code $LASTEXITCODE."
    }
    $manifestAfterUpload = Get-Content -LiteralPath $stagedManifestPath -Raw
    if ($manifestAfterUpload -eq $manifestBeforeUpload) {
        throw 'WorkshopTool did not update content.xml. The upload may have been canceled.'
    }

    [xml]$publishedManifest = $manifestAfterUpload
    if ($publishedManifest.content.id -notmatch '^ws_\d+$') {
        throw 'WorkshopTool did not write a valid Workshop item ID to content.xml.'
    }
    Copy-Item -LiteralPath $stagedManifestPath -Destination $sourceManifestPath -Force
    Write-Host "Trade Subscription Renew published as Workshop item: $($publishedManifest.content.id)"
}

$settings = Read-ToolsConfig -Path $configPath
if ($Command -ne 'config' -and
    (-not [string]::IsNullOrWhiteSpace($ProfileId) -or
     -not [string]::IsNullOrWhiteSpace($ToolsPath) -or
     -not [string]::IsNullOrWhiteSpace($XRCatToolPath) -or
     -not [string]::IsNullOrWhiteSpace($WorkshopToolPath))) {
    throw 'ProfileId and tool paths can only be set with the config command.'
}
switch ($Command) {
    'config' {
        Invoke-Config -Settings $settings
    }
    'package' {
        Invoke-Package -Settings $settings
    }
    'release' {
        Invoke-Release -Settings $settings
    }
    'sync' {
        Invoke-Sync -Settings $settings
    }
    'publish' {
        Invoke-Publish -Settings $settings
    }
    'steam-readme' {
        Invoke-SteamReadme
    }
}
