[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function New-ReleaseFixture {
    param([Parameter(Mandatory)][string]$Root)

    New-Item -ItemType Directory -Path (Join-Path $Root 'tradesub_renew') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'tradesub_renew\content.xml') -Value '<content id="tradesub_renew" />'
    Set-Content -LiteralPath (Join-Path $Root 'tradesub_renew\ext_01.cat') -Value 'new catalog'
}

function Invoke-TestInstaller {
    param(
        [Parameter(Mandatory)][string]$Installer,
        [Parameter(Mandatory)][string]$X4Root,
        [string[]]$Answers = @()
    )

    $answerQueue = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in $Answers) {
        $answerQueue.Enqueue($answer)
    }

    function Read-Host {
        param([string]$Prompt)
        if ($answerQueue.Count -eq 0) {
            throw "Unexpected installer prompt: $Prompt"
        }
        return $answerQueue.Dequeue()
    }

    & $Installer -X4Root $X4Root
    Assert-True ($answerQueue.Count -eq 0) 'The installer did not consume all expected answers.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceInstaller = Join-Path $repositoryRoot 'install.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("x4-installer-test-" + [guid]::NewGuid().ToString('N'))

try {
    Assert-True (Test-Path -LiteralPath $sourceInstaller -PathType Leaf) 'The release installer does not exist.'

    $singleRelease = Join-Path $testRoot 'single\release'
    New-ReleaseFixture -Root $singleRelease
    Copy-Item -LiteralPath $sourceInstaller -Destination $singleRelease
    $singleX4Root = Join-Path $testRoot 'single\X4'
    New-Item -ItemType Directory -Path (Join-Path $singleX4Root '111') -Force | Out-Null
    Invoke-TestInstaller -Installer (Join-Path $singleRelease 'install.ps1') -X4Root $singleX4Root
    Assert-True (Test-Path -LiteralPath (Join-Path $singleX4Root '111\extensions\tradesub_renew\ext_01.cat')) 'One detected profile must be selected without a prompt.'

    $multipleRelease = Join-Path $testRoot 'multiple\release'
    New-ReleaseFixture -Root $multipleRelease
    Copy-Item -LiteralPath $sourceInstaller -Destination $multipleRelease
    $multipleX4Root = Join-Path $testRoot 'multiple\X4'
    New-Item -ItemType Directory -Path (Join-Path $multipleX4Root '111'), (Join-Path $multipleX4Root '222') -Force | Out-Null
    Invoke-TestInstaller -Installer (Join-Path $multipleRelease 'install.ps1') -X4Root $multipleX4Root -Answers @('2')
    Assert-True (Test-Path -LiteralPath (Join-Path $multipleX4Root '222\extensions\tradesub_renew\ext_01.cat')) 'The selected profile must receive the mod.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $multipleX4Root '111\extensions\tradesub_renew'))) 'An unselected profile must not be changed.'

    $manualRelease = Join-Path $testRoot 'manual\release'
    New-ReleaseFixture -Root $manualRelease
    Copy-Item -LiteralPath $sourceInstaller -Destination $manualRelease
    $emptyX4Root = Join-Path $testRoot 'manual\X4'
    $manualProfile = Join-Path $testRoot 'manual\custom-profile'
    New-Item -ItemType Directory -Path $emptyX4Root, $manualProfile -Force | Out-Null
    Invoke-TestInstaller -Installer (Join-Path $manualRelease 'install.ps1') -X4Root $emptyX4Root -Answers @($manualProfile)
    Assert-True (Test-Path -LiteralPath (Join-Path $manualProfile 'extensions\tradesub_renew\ext_01.cat')) 'A manually supplied profile must receive the mod.'

    $declineRelease = Join-Path $testRoot 'decline\release'
    New-ReleaseFixture -Root $declineRelease
    Copy-Item -LiteralPath $sourceInstaller -Destination $declineRelease
    $declineX4Root = Join-Path $testRoot 'decline\X4'
    $declineDestination = Join-Path $declineX4Root '111\extensions\tradesub_renew'
    New-Item -ItemType Directory -Path $declineDestination -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $declineDestination 'stale.txt') -Value 'keep me'
    Invoke-TestInstaller -Installer (Join-Path $declineRelease 'install.ps1') -X4Root $declineX4Root -Answers @('n')
    Assert-True (Test-Path -LiteralPath (Join-Path $declineDestination 'stale.txt')) 'Declining replacement must preserve the existing mod.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $declineDestination 'ext_01.cat'))) 'Declining replacement must not copy new files.'

    $replaceRelease = Join-Path $testRoot 'replace\release'
    New-ReleaseFixture -Root $replaceRelease
    Copy-Item -LiteralPath $sourceInstaller -Destination $replaceRelease
    $replaceX4Root = Join-Path $testRoot 'replace\X4'
    $replaceDestination = Join-Path $replaceX4Root '111\extensions\tradesub_renew'
    New-Item -ItemType Directory -Path $replaceDestination -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $replaceDestination 'stale.txt') -Value 'remove me'
    Invoke-TestInstaller -Installer (Join-Path $replaceRelease 'install.ps1') -X4Root $replaceX4Root -Answers @('y')
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $replaceDestination 'stale.txt'))) 'Approved replacement must clear stale files.'
    Assert-True (Test-Path -LiteralPath (Join-Path $replaceDestination 'ext_01.cat')) 'Approved replacement must copy new files.'

    Write-Host 'install.tests.ps1 passed'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
