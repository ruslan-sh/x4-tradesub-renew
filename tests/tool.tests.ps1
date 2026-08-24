[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Message
    )

    try {
        & $Action
    } catch {
        if ($_.Exception.Message -match $Pattern) {
            return
        }
        throw "$Message Actual error: $($_.Exception.Message)"
    }
    throw "$Message No error was raised."
}

function New-TestMod {
    param([Parameter(Mandatory)][string]$Root)

    New-Item -ItemType Directory -Path (Join-Path $Root 'src\aiscripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'src\libraries') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'src\t') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Root 'src\content.xml') -Value '<content id="tradesub_renew" name="Test" description="Test mod" version="101" />'
    Set-Content -LiteralPath (Join-Path $Root 'src\aiscripts\test.xml') -Value '<aiscript />'
    Set-Content -LiteralPath (Join-Path $Root 'src\libraries\test.xml') -Value '<diff />'
    Set-Content -LiteralPath (Join-Path $Root 'src\t\test.xml') -Value '<language />'
    [IO.File]::WriteAllBytes((Join-Path $Root 'src\preview.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10, 0))
    Set-Content -LiteralPath (Join-Path $Root 'README.md') -Value @'
# Test Mod

Use **bold**, *italic*, `code`, and [the guide](https://example.com/guide).
Use __more bold__, _more italic_, and ~~removed text~~.
See the [Developer guide](#developer-guide).

> Quoted **text**.

---

![Preview](preview.png)

- First item
- Second item

1. First step

   ```powershell
   .\tool.ps1 sync
   ```

2. Second step

~~~text
tilde fence
~~~
'@
}

function New-FakeTools {
    param([Parameter(Mandatory)][string]$Root)

    $toolsRoot = Join-Path $Root 'X Tools'
    New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null

    @'
param(
    [Alias('in')][string]$InputPath,
    [Alias('out')][string]$OutputPath,
    [Alias('include')][string]$IncludePaths
)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'catalog-arguments.txt') -Value @('-in', $InputPath, '-out', $OutputPath, '-include', $IncludePaths)
Set-Content -LiteralPath $OutputPath -Value 'catalog'
Set-Content -LiteralPath ([IO.Path]::ChangeExtension($OutputPath, '.dat')) -Value 'data'
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath (Join-Path $toolsRoot 'XRCatTool.ps1')

    @'
param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
Set-Content -LiteralPath (Join-Path $PSScriptRoot 'workshop-arguments.txt') -Value $Arguments
$pathIndex = [Array]::IndexOf($Arguments, '-path')
$manifestPath = Join-Path $Arguments[$pathIndex + 1] 'content.xml'
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
if ($Arguments[0] -eq 'publishx4') {
    $manifest.content.id = 'ws_1234567890'
    $manifest.content.SetAttribute('sync', 'false')
} else {
    $lastUpdate = if ($manifest.content.HasAttribute('lastupdate')) { [int]$manifest.content.lastupdate } else { 0 }
    $manifest.content.SetAttribute('lastupdate', [string]($lastUpdate + 1))
}
$manifest.Save($manifestPath)
$global:LASTEXITCODE = 0
'@ | Set-Content -LiteralPath (Join-Path $toolsRoot 'WorkshopTool.ps1')

    return $toolsRoot
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("x4-tool-test-" + [guid]::NewGuid().ToString('N'))

try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tool.ps1') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tools-config.ps1') -Destination $testRoot
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'install.ps1') -Destination $testRoot
    New-TestMod -Root $testRoot
    $toolsRoot = New-FakeTools -Root $testRoot
    $tool = Join-Path $testRoot 'tool.ps1'

    $x4Root = Join-Path $testRoot 'X4'
    New-Item -ItemType Directory -Path (Join-Path $x4Root '123') -Force | Out-Null
    Assert-Throws -Action { & $tool sync -X4Root $x4Root } -Pattern '^ProfileId is not configured\.' -Message 'Sync must direct the user to config when ProfileId is missing.'

    $catalogExe = Join-Path $testRoot 'Catalog\XRCatTool.exe'
    $workshopExe = Join-Path $testRoot 'Workshop\WorkshopTool.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $catalogExe), (Split-Path -Parent $workshopExe) -Force | Out-Null
    Set-Content -LiteralPath $catalogExe -Value 'test executable'
    Set-Content -LiteralPath $workshopExe -Value 'test executable'

    & $tool config -ProfileId 123 -XRCatToolPath $catalogExe
    $configPath = Join-Path $testRoot '.tools.ini'
    $config = Get-Content -LiteralPath $configPath -Raw
    Assert-True ($config -match '(?m)^ProfileId=123\r?$') 'Config must store ProfileId.'
    Assert-True ($config -match '(?m)^XRCatToolPath=') 'Config must store a separately configured catalog tool.'
    Assert-True ($config -notmatch '(?m)^WorkshopToolPath=') 'Config must not require the Workshop tool.'
    Assert-True ($config -notmatch '(?m)^XToolsPath=') 'Config must not write the removed shared-path setting.'

    & $tool config -WorkshopToolPath $workshopExe
    $config = Get-Content -LiteralPath $configPath -Raw
    Assert-True ($config -match '(?m)^XRCatToolPath=') 'Config must preserve an unspecified catalog tool.'
    Assert-True ($config -match '(?m)^WorkshopToolPath=') 'Config must store a separately configured Workshop tool.'

    $sharedToolsRoot = Join-Path $testRoot 'Shared Tools'
    New-Item -ItemType Directory -Path $sharedToolsRoot -Force | Out-Null
    Copy-Item -LiteralPath $catalogExe -Destination (Join-Path $sharedToolsRoot 'XRCatTool.exe')
    & $tool config -ToolsPath $sharedToolsRoot
    $config = Get-Content -LiteralPath $configPath -Raw
    Assert-True ($config -match [regex]::Escape((Join-Path $sharedToolsRoot 'XRCatTool.exe'))) 'ToolsPath must store each expected executable that exists.'
    Assert-True ($config -match '(?m)^WorkshopToolPath=') 'ToolsPath must preserve a separately configured tool that is not in the directory.'

    $configBeforeInvalidUpdate = $config
    Assert-Throws -Action { & $tool config -ProfileId 999 -WorkshopToolPath (Join-Path $testRoot 'missing\WorkshopTool.exe') } -Pattern 'Cannot find path' -Message 'Config must reject a missing tool path.'
    Assert-True ((Get-Content -LiteralPath $configPath -Raw) -eq $configBeforeInvalidUpdate) 'Config must not save any setting when validation fails.'

    Set-Content -LiteralPath $configPath -Value @(
        'ProfileId=123'
        "XRCatToolPath=$(Join-Path $toolsRoot 'XRCatTool.ps1')"
        "WorkshopToolPath=$(Join-Path $toolsRoot 'WorkshopTool.ps1')"
    )

    & $tool steam-readme
    $steamReadmePath = Join-Path $testRoot 'dist\README.steam.txt'
    Assert-True (Test-Path -LiteralPath $steamReadmePath -PathType Leaf) 'Steam README conversion must create dist\README.steam.txt.'
    $steamReadme = (Get-Content -LiteralPath $steamReadmePath -Raw) -replace "`r`n", "`n"
    $expectedSteamReadme = @'
[h1]Test Mod[/h1]

Use [b]bold[/b], [i]italic[/i], [code]code[/code], and [url=https://example.com/guide]the guide[/url].
Use [b]more bold[/b], [i]more italic[/i], and [strike]removed text[/strike].
See the Developer guide.

[quote]Quoted [b]text[/b].[/quote]

[hr][/hr]

Preview

[list]
[*]First item
[*]Second item
[/list]

[olist]
[*]First step

[code]
.\tool.ps1 sync
[/code]

[*]Second step
[/olist]

[code]
tilde fence
[/code]
'@ -replace "`r`n", "`n"
    $conversionMessage = 'Steam README conversion must map supported Markdown to Steam formatting tags. ' +
        'Expected: ' + (ConvertTo-Json $expectedSteamReadme.TrimEnd() -Compress) +
        ' Actual: ' + (ConvertTo-Json $steamReadme.TrimEnd() -Compress)
    Assert-True ($steamReadme.TrimEnd() -eq $expectedSteamReadme.TrimEnd()) $conversionMessage

    & $tool package
    $packageRoot = Join-Path $testRoot 'dist\tradesub_renew'
    Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'content.xml') -PathType Leaf) 'Package must contain content.xml.'
    Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'preview.png') -PathType Leaf) 'Package must contain preview.png.'
    Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'ext_01.cat') -PathType Leaf) 'Package must contain ext_01.cat.'
    Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'ext_01.dat') -PathType Leaf) 'Package must contain ext_01.dat.'
    Assert-True (Test-Path -LiteralPath (Join-Path $testRoot 'dist\install.ps1') -PathType Leaf) 'Release root must contain install.ps1.'

    & $tool release
    $releaseArchive = Join-Path $testRoot 'dist\release_v101.zip'
    Assert-True (Test-Path -LiteralPath $releaseArchive -PathType Leaf) 'Release must create dist\release_v101.zip from manifest version 101.'
    $archive = [IO.Compression.ZipFile]::OpenRead($releaseArchive)
    try {
        $archiveFiles = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object FullName)
        foreach ($expectedEntry in @(
            'install.ps1',
            'tradesub_renew/content.xml',
            'tradesub_renew/preview.png',
            'tradesub_renew/ext_01.cat',
            'tradesub_renew/ext_01.dat'
        )) {
            Assert-True ($archiveFiles -contains $expectedEntry) "Release archive must contain $expectedEntry."
        }
        Assert-True ($archiveFiles.Count -eq 5) 'Release archive must contain only the installer and packaged mod files.'
    } finally {
        $archive.Dispose()
    }

    $destinationRoot = Join-Path $x4Root '123\extensions\tradesub_renew'
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $destinationRoot 'stale.txt') -Value 'stale'

    & $tool sync -X4Root $x4Root
    Assert-True (Test-Path -LiteralPath (Join-Path $destinationRoot 'aiscripts\test.xml')) 'Loose sync must copy src recursively.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destinationRoot 'stale.txt'))) 'Sync must clean the destination.'

    Remove-Item -LiteralPath (Join-Path $packageRoot 'ext_01.cat'), (Join-Path $packageRoot 'ext_01.dat')
    & $tool sync -X4Root $x4Root -Packaged -Repack
    Assert-True (Test-Path -LiteralPath (Join-Path $destinationRoot 'ext_01.cat')) 'Repack must build before packaged sync.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $destinationRoot 'aiscripts'))) 'Packaged sync must not retain loose files.'

    & $tool publish
    [xml]$sourceManifest = Get-Content -LiteralPath (Join-Path $testRoot 'src\content.xml') -Raw
    Assert-True ($sourceManifest.content.id -eq 'ws_1234567890') 'Initial publish must persist the Workshop ID.'
    Assert-True ($sourceManifest.content.sync -eq 'false') 'Initial publish must persist disabled Workshop sync.'

    & $tool publish 'Improve station selection' -UpdateNameAndDescription
    $workshopArguments = Get-Content -LiteralPath (Join-Path $toolsRoot 'workshop-arguments.txt')
    Assert-True ($workshopArguments[0] -eq 'update') 'An existing Workshop item must use update.'
    Assert-True ($workshopArguments -contains '-changenote') 'Update must pass a change note.'
    Assert-True ($workshopArguments -contains 'Improve station selection') 'Update must pass the positional change note.'
    Assert-True ($workshopArguments -contains '-namedesc') 'Requested metadata refresh must be passed to WorkshopTool.'
    [xml]$sourceManifest = Get-Content -LiteralPath (Join-Path $testRoot 'src\content.xml') -Raw
    Assert-True ($sourceManifest.content.version -eq '102') 'A normal update must increment the version.'

    & $tool publish 'Documentation correction' -KeepVersion
    $workshopArguments = Get-Content -LiteralPath (Join-Path $toolsRoot 'workshop-arguments.txt')
    Assert-True ($workshopArguments -contains '-minor') 'KeepVersion must map to WorkshopTool minor mode.'
    [xml]$sourceManifest = Get-Content -LiteralPath (Join-Path $testRoot 'src\content.xml') -Raw
    Assert-True ($sourceManifest.content.version -eq '102') 'KeepVersion must preserve the source version.'

    Write-Host 'tool.tests.ps1 passed'
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
