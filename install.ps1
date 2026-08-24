[CmdletBinding()]
param(
    [Parameter(DontShow)]
    [string]$X4Root
)

$ErrorActionPreference = 'Stop'

$modDirectoryName = 'tradesub_renew'
$releaseModRoot = Join-Path $PSScriptRoot $modDirectoryName
$manifestPath = Join-Path $releaseModRoot 'content.xml'

if (-not (Test-Path -LiteralPath $releaseModRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "The release is incomplete. Cannot find $modDirectoryName\content.xml next to install.ps1."
}

if ([string]::IsNullOrWhiteSpace($X4Root)) {
    $X4Root = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Egosoft\X4'
}

function Read-ProfileSelection {
    param([Parameter(Mandatory)][IO.DirectoryInfo[]]$Profiles)

    Write-Host 'Multiple X4 profiles were found:'
    for ($index = 0; $index -lt $Profiles.Count; $index++) {
        Write-Host "  $($index + 1). $($Profiles[$index].FullName)"
    }

    while ($true) {
        $selection = Read-Host "Select a profile (1-$($Profiles.Count))"
        $selectedIndex = 0
        if ([int]::TryParse($selection, [ref]$selectedIndex) -and
            $selectedIndex -ge 1 -and
            $selectedIndex -le $Profiles.Count) {
            return $Profiles[$selectedIndex - 1].FullName
        }
        Write-Warning 'Enter one of the listed profile numbers.'
    }
}

function Read-ManualProfilePath {
    while ($true) {
        $candidate = (Read-Host 'Enter the full path to your X4 player profile').Trim().Trim('"')
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        Write-Warning "The profile directory does not exist: $candidate"
    }
}

$profiles = if (Test-Path -LiteralPath $X4Root -PathType Container) {
    @(Get-ChildItem -LiteralPath $X4Root -Directory | Where-Object Name -Match '^\d+$' | Sort-Object Name)
} else {
    @()
}

$profileRoot = if ($profiles.Count -eq 1) {
    Write-Host "Using X4 profile: $($profiles[0].FullName)"
    $profiles[0].FullName
} elseif ($profiles.Count -gt 1) {
    Read-ProfileSelection -Profiles $profiles
} else {
    Write-Host "No X4 player profile was found under: $X4Root"
    Read-ManualProfilePath
}

$profileRoot = (Resolve-Path -LiteralPath $profileRoot).Path.TrimEnd(
    [IO.Path]::DirectorySeparatorChar,
    [IO.Path]::AltDirectorySeparatorChar
)
$profilePrefix = $profileRoot + [IO.Path]::DirectorySeparatorChar
$extensionsCandidate = Join-Path $profileRoot 'extensions'
$extensionsRoot = if (Test-Path -LiteralPath $extensionsCandidate -PathType Container) {
    (Resolve-Path -LiteralPath $extensionsCandidate).Path
} else {
    [IO.Path]::GetFullPath($extensionsCandidate)
}
$destinationCandidate = Join-Path $extensionsRoot $modDirectoryName
$destinationRoot = if (Test-Path -LiteralPath $destinationCandidate -PathType Container) {
    (Resolve-Path -LiteralPath $destinationCandidate).Path
} else {
    [IO.Path]::GetFullPath($destinationCandidate)
}

if (-not $extensionsRoot.StartsWith($profilePrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not $destinationRoot.StartsWith($profilePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "The installation destination must stay under the selected profile: $profileRoot"
}

if (Test-Path -LiteralPath $destinationRoot) {
    while ($true) {
        $answer = (Read-Host "Trade Subscription Renew is already installed at $destinationRoot. Clear and replace it? [y/N]").Trim()
        if ($answer -match '^(?i:y|yes)$') {
            break
        }
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -match '^(?i:n|no)$') {
            Write-Host 'Installation canceled. The existing mod was not changed.'
            return
        }
        Write-Warning 'Enter Y to replace the existing mod or N to cancel.'
    }
    Remove-Item -LiteralPath $destinationRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
foreach ($sourceFile in Get-ChildItem -LiteralPath $releaseModRoot -Recurse -File) {
    $relativePath = [IO.Path]::GetRelativePath($releaseModRoot, $sourceFile.FullName)
    $destinationPath = Join-Path $destinationRoot $relativePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
    Copy-Item -LiteralPath $sourceFile.FullName -Destination $destinationPath -Force
}

Write-Host "Trade Subscription Renew installed at: $destinationRoot"
