[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string]$InputPath,

    [Parameter(Mandatory, Position = 1)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Convert-InlineMarkdownToSteam {
    param([AllowEmptyString()][string]$Text)

    $codeSpans = [Collections.Generic.List[string]]::new()
    $Text = [regex]::Replace($Text, '`([^`]+)`', {
        param($match)
        $index = $codeSpans.Count
        $codeSpans.Add($match.Groups[1].Value)
        return "@@STEAM_CODE_$index@@"
    })
    $Text = [regex]::Replace($Text, '!\[([^\]]*)\]\([^)]+\)', '$1')
    $Text = [regex]::Replace($Text, '\[([^\]]+)\]\(([^)]+)\)', {
        param($match)
        $label = $match.Groups[1].Value
        $target = $match.Groups[2].Value
        if ($target -match '^https?://') {
            return "[url=$target]$label[/url]"
        }
        return $label
    })
    $Text = [regex]::Replace($Text, '\*\*(.+?)\*\*', '[b]$1[/b]')
    $Text = [regex]::Replace($Text, '__(.+?)__', '[b]$1[/b]')
    $Text = [regex]::Replace($Text, '~~(.+?)~~', '[strike]$1[/strike]')
    $Text = [regex]::Replace($Text, '(?<!\*)\*([^*\r\n]+)\*(?!\*)', '[i]$1[/i]')
    $Text = [regex]::Replace($Text, '(?<![\w_])_([^_\r\n]+)_(?![\w_])', '[i]$1[/i]')
    for ($index = 0; $index -lt $codeSpans.Count; $index++) {
        $Text = $Text.Replace("@@STEAM_CODE_$index@@", "[code]$($codeSpans[$index])[/code]")
    }
    return $Text
}

function Add-PendingBlankLines {
    param(
        [Parameter(Mandatory)][ref]$Output,
        [int]$Count
    )

    for ($index = 0; $index -lt $Count; $index++) {
        $Output.Value.Add('')
    }
    return 0
}

function Convert-MarkdownToSteam {
    param([Parameter(Mandatory)][string]$Markdown)

    $output = [Collections.Generic.List[string]]::new()
    $listType = $null
    $pendingListBlankCount = 0
    $inCodeBlock = $false
    $codeBlockIndent = 0
    $codeFenceMarker = $null
    $lines = $Markdown -split "\r?\n"

    foreach ($line in $lines) {
        $fenceMatch = [regex]::Match($line, '^(\s*)(```|~~~)')
        if ($fenceMatch.Success -and (-not $inCodeBlock -or $fenceMatch.Groups[2].Value -eq $codeFenceMarker)) {
            $fenceIndent = $fenceMatch.Groups[1].Value.Length
            if ($listType -and -not $inCodeBlock -and $fenceIndent -eq 0) {
                $output.Add("[/$listType]")
                $listType = $null
                $pendingListBlankCount = Add-PendingBlankLines -Output ([ref]$output) -Count $pendingListBlankCount
            } elseif ($listType -and -not $inCodeBlock) {
                $pendingListBlankCount = Add-PendingBlankLines -Output ([ref]$output) -Count $pendingListBlankCount
            }
            $output.Add($(if ($inCodeBlock) { '[/code]' } else { '[code]' }))
            $inCodeBlock = -not $inCodeBlock
            $codeBlockIndent = if ($inCodeBlock) { $fenceIndent } else { 0 }
            $codeFenceMarker = if ($inCodeBlock) { $fenceMatch.Groups[2].Value } else { $null }
            continue
        }
        if ($inCodeBlock) {
            $codeLine = if ($codeBlockIndent -gt 0) {
                [regex]::Replace($line, "^\s{0,$codeBlockIndent}", '', 1)
            } else {
                $line
            }
            $output.Add($codeLine)
            continue
        }

        if ($listType -and [string]::IsNullOrWhiteSpace($line)) {
            $pendingListBlankCount++
            continue
        }

        $nextListType = if ($line -match '^\s*[-+*]\s+(.+)$') {
            'list'
        } elseif ($line -match '^\s*\d+[.)]\s+(.+)$') {
            'olist'
        } else {
            $null
        }
        if ($listType -and $nextListType -ne $listType) {
            $output.Add("[/$listType]")
            $listType = $null
            $pendingListBlankCount = Add-PendingBlankLines -Output ([ref]$output) -Count $pendingListBlankCount
        }
        if ($nextListType) {
            if (-not $listType) {
                $listType = $nextListType
                $output.Add("[$listType]")
            } else {
                $pendingListBlankCount = Add-PendingBlankLines -Output ([ref]$output) -Count $pendingListBlankCount
            }
            $output.Add('[*]' + (Convert-InlineMarkdownToSteam -Text $Matches[1]))
            continue
        }

        if ($line -match '^(#{1,6})\s+(.+?)\s*#*\s*$') {
            $level = $Matches[1].Length
            $heading = Convert-InlineMarkdownToSteam -Text $Matches[2]
            $output.Add($(if ($level -le 3) { "[h$level]$heading[/h$level]" } else { "[b]$heading[/b]" }))
        } elseif ($line -match '^\s*(\*\s*\*\s*\*|-\s*-\s*-|_\s*_\s*_)\s*$') {
            $output.Add('[hr][/hr]')
        } elseif ($line -match '^>\s?(.*)$') {
            $output.Add('[quote]' + (Convert-InlineMarkdownToSteam -Text $Matches[1]) + '[/quote]')
        } else {
            $output.Add((Convert-InlineMarkdownToSteam -Text $line))
        }
    }
    if ($listType) {
        $output.Add("[/$listType]")
        $pendingListBlankCount = Add-PendingBlankLines -Output ([ref]$output) -Count $pendingListBlankCount
    }
    if ($inCodeBlock) {
        throw "$InputPath contains an unclosed fenced code block."
    }
    return $output -join [Environment]::NewLine
}

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "Markdown input does not exist: $InputPath"
}
$resolvedInputPath = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
$steamText = Convert-MarkdownToSteam -Markdown (Get-Content -LiteralPath $resolvedInputPath -Raw)
Set-Content -LiteralPath $resolvedOutputPath -Value $steamText -Encoding utf8
Write-Host "Steam-formatted Markdown created at: $resolvedOutputPath"
