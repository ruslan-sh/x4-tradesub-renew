[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot 'src')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "XML source directory does not exist: $SourceRoot"
}

$xmlFiles = @(Get-ChildItem -LiteralPath $SourceRoot -Recurse -File -Filter '*.xml')
if ($xmlFiles.Count -eq 0) {
    throw "No XML files found under: $SourceRoot"
}

$failed = $false
foreach ($file in $xmlFiles) {
    try {
        $document = [System.Xml.XmlDocument]::new()
        $document.PreserveWhitespace = $true
        $document.Load($file.FullName)
        Write-Host "XML parsed: $([IO.Path]::GetRelativePath($SourceRoot, $file.FullName))"
    } catch {
        $failed = $true
        Write-Error "XML parse failed: $($file.FullName)`n$($_.Exception.Message)" -ErrorAction Continue
    }
}

if ($failed) {
    exit 1
}

Write-Host "Parsed $($xmlFiles.Count) XML files."
exit 0
