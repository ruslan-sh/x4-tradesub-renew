function Read-ToolsConfig {
    param([Parameter(Mandatory)][string]$Path)

    $settings = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $settings
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) {
            continue
        }
        if ($line -notmatch '^([^=]+)=(.*)$') {
            throw "Invalid settings line in ${Path}: $line"
        }
        $settings[$Matches[1].Trim()] = $Matches[2].Trim()
    }
    return $settings
}

function Write-ToolsConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Settings
    )

    $lines = foreach ($key in $Settings.Keys) {
        "$key=$($Settings[$key])"
    }
    Set-Content -LiteralPath $Path -Value $lines
}
