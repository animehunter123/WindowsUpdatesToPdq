#requires -Version 5.1

<#
.SYNOPSIS
    Downloads the latest Windows 11 26H2 x64 cumulative security update
    from the Microsoft Update Catalog.

.DESCRIPTION
    Searches the Microsoft Update Catalog for the latest Windows 11 26H2
    cumulative security update for x64 systems.

    ONLY downloads:
      - Windows 11
      - Version 26H2
      - x64
      - Cumulative Update
      - Windows 11 Security Updates

    Explicitly excludes:
      - ARM64
      - x86 / 32-bit
      - Preview updates
      - .NET Framework updates
      - Dynamic Updates
      - Safe OS Dynamic Updates
      - Setup Dynamic Updates
      - Other unrelated updates

    The resulting folder can be copied directly into a PDQ Deploy
    repository.

.OUTPUT
    .\YYYYMMDD-Windows11-26H2-Cumulative\
        KBxxxxxxx\
            Windows11-26H2-KBxxxxxxx-x64.msu
            README.txt
#>

$ErrorActionPreference = "Stop"
$ProgressPreference=0

# ============================================================================
# CONFIGURATION
# ============================================================================

$SearchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=Windows+11+26H2+x64+cumulative+update"

$DATE = Get-Date -Format 'yyyyMMdd'

$BaseFolder = Join-Path $PSScriptRoot ".\$DATE-Windows11-26H2-Cumulative"

# ============================================================================
# FUNCTIONS
# ============================================================================

function Get-CleanText {
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $Text = $Html

    # Remove scripts and styles first.
    $Text = [regex]::Replace(
        $Text,
        '(?is)<script[^>]*>.*?</script>',
        ' '
    )

    $Text = [regex]::Replace(
        $Text,
        '(?is)<style[^>]*>.*?</style>',
        ' '
    )

    # Remove HTML tags.
    $Text = [regex]::Replace(
        $Text,
        '(?is)<[^>]+>',
        ' '
    )

    # Decode HTML entities.
    $Text = [System.Net.WebUtility]::HtmlDecode($Text)

    # Normalize whitespace.
    $Text = [regex]::Replace(
        $Text,
        '\s+',
        ' '
    )

    return $Text.Trim()
}


function Get-DownloadUrl {
    param(
        [Parameter(Mandatory)]
        [string]$Guid
    )

    Write-Host ""
    Write-Host "Getting download information for $Guid ..." -ForegroundColor Cyan

    $DialogUrl = "https://www.catalog.update.microsoft.com/DownloadDialog.aspx"

    $Body = @{
        updateIDs = "[{`"size`":0,`"updateID`":`"$Guid`"}]"
    }

    try {
        $Response = Invoke-WebRequest `
            -Uri $DialogUrl `
            -Method Post `
            -Body $Body `
            -UseBasicParsing
    }
    catch {
        Write-Warning "DownloadDialog request failed: $($_.Exception.Message)"
        return $null
    }

    $Html = $Response.Content

    # Look for direct .msu URLs.
    $Matches = [regex]::Matches(
        $Html,
        '(?i)https?://[^"''<>\s]+\.msu'
    )

    if ($Matches.Count -eq 0) {
        Write-Warning "No .msu download URL was found."
        return $null
    }

    foreach ($Match in $Matches) {

        $Url = $Match.Value

        # Decode HTML entities if necessary.
        $Url = [System.Net.WebUtility]::HtmlDecode($Url)

        # Remove escaped characters.
        $Url = $Url.Replace('\u0026', '&')
        $Url = $Url.Replace('\&', '&')

        if ($Url -match '(?i)\.msu($|[?&])') {
            return $Url
        }
    }

    return $null
}


function Get-LatestUpdateRow {
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    Write-Host "Parsing Microsoft Update Catalog results..." -ForegroundColor Cyan

    # Find individual table rows instead of relying on one giant
    # exact HTML structure. Microsoft changes the Catalog HTML occasionally.
    $Rows = [regex]::Matches(
        $Html,
        '(?is)<tr[^>]*>.*?</tr>'
    )

    Write-Host "Found $($Rows.Count) table rows." -ForegroundColor DarkGray

    $Candidates = @()

    foreach ($Row in $Rows) {

        $RowHtml = $Row.Value
        $RowText = Get-CleanText -Html $RowHtml

        if ([string]::IsNullOrWhiteSpace($RowText)) {
            continue
        }

        # --------------------------------------------------------------------
        # REQUIRED: Windows 11 26H2
        # --------------------------------------------------------------------

        if ($RowText -notmatch '(?i)\bWindows 11\b') {
            continue
        }

        if ($RowText -notmatch '(?i)\b26H2\b') {
            continue
        }

        # --------------------------------------------------------------------
        # REQUIRED: Cumulative Update
        # --------------------------------------------------------------------

        if ($RowText -notmatch '(?i)\bCumulative Update\b') {
            continue
        }

        # --------------------------------------------------------------------
        # REQUIRED: Windows 11 Security Updates
        # --------------------------------------------------------------------

        if ($RowText -notmatch '(?i)\bWindows 11 Security Updates\b') {
            continue
        }

        # --------------------------------------------------------------------
        # REQUIRED: x64 ONLY
        # --------------------------------------------------------------------

        if ($RowText -notmatch '(?i)\bx64-based Systems\b') {
            continue
        }

        # --------------------------------------------------------------------
        # EXCLUDE OTHER ARCHITECTURES
        # --------------------------------------------------------------------

        if ($RowText -match '(?i)\bARM64\b') {
            continue
        }

        if ($RowText -match '(?i)\bx86\b') {
            continue
        }

        if ($RowText -match '(?i)\b32-bit\b') {
            continue
        }

        # --------------------------------------------------------------------
        # EXCLUDE PREVIEW UPDATES
        # --------------------------------------------------------------------

        if ($RowText -match '(?i)\bPreview\b') {
            continue
        }

        # --------------------------------------------------------------------
        # EXCLUDE .NET UPDATES
        # --------------------------------------------------------------------

        if ($RowText -match '(?i)\.NET Framework') {
            continue
        }

        if ($RowText -match '(?i)\.NET') {
            continue
        }

        # --------------------------------------------------------------------
        # EXCLUDE DYNAMIC / SAFE OS / SETUP UPDATES
        # --------------------------------------------------------------------

        if ($RowText -match '(?i)\bDynamic Update\b') {
            continue
        }

        if ($RowText -match '(?i)\bSafe OS\b') {
            continue
        }

        if ($RowText -match '(?i)\bSetup Dynamic\b') {
            continue
        }

        # --------------------------------------------------------------------
        # EXTRACT KB
        # --------------------------------------------------------------------

        $KbMatch = [regex]::Match(
            $RowText,
            '(?i)\bKB\d{6,8}\b'
        )

        if (-not $KbMatch.Success) {
            continue
        }

        $KB = $KbMatch.Value.ToUpper()

        # --------------------------------------------------------------------
        # EXTRACT UPDATE GUID
        # --------------------------------------------------------------------

        $GuidMatch = [regex]::Match(
            $RowHtml,
            '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        )

        if (-not $GuidMatch.Success) {
            continue
        }

        $GUID = $GuidMatch.Value

        # --------------------------------------------------------------------
        # EXTRACT DATE IF AVAILABLE
        # --------------------------------------------------------------------

        $DateMatch = [regex]::Match(
            $RowText,
            '(?i)\b\d{1,2}/\d{1,2}/\d{4}\b'
        )

        $UpdateDate = $null

        if ($DateMatch.Success) {
            try {
                $UpdateDate = [datetime]::Parse(
                    $DateMatch.Value,
                    [System.Globalization.CultureInfo]::InvariantCulture
                )
            }
            catch {
                $UpdateDate = $null
            }
        }

        $Candidates += [PSCustomObject]@{
            KB          = $KB
            GUID        = $GUID
            UpdateDate  = $UpdateDate
            RowText     = $RowText
        }
    }

    if ($Candidates.Count -eq 0) {
        return $null
    }

    Write-Host ""
    Write-Host "Matching x64 Windows 11 26H2 cumulative updates:" -ForegroundColor Green

    foreach ($Candidate in $Candidates) {

        Write-Host "  $($Candidate.KB)" -ForegroundColor White

        if ($Candidate.UpdateDate) {
            Write-Host "    Date: $($Candidate.UpdateDate.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
        }

        Write-Host "    GUID: $($Candidate.GUID)" -ForegroundColor DarkGray
    }

    # Prefer the update with the newest date.
    $WithDates = @(
        $Candidates |
            Where-Object { $null -ne $_.UpdateDate } |
            Sort-Object UpdateDate -Descending
    )

    if ($WithDates.Count -gt 0) {
        return $WithDates[0]
    }

    # If no date could be parsed, use the first matching result.
    return $Candidates[0]
}


# ============================================================================
# CREATE OUTPUT DIRECTORY
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows 11 26H2 x64 Cumulative Update Downloader" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Search URL:" -ForegroundColor Yellow
Write-Host $SearchUrl
Write-Host ""

Write-Host "Output folder:" -ForegroundColor Yellow
Write-Host $BaseFolder
Write-Host ""

if (-not (Test-Path $BaseFolder)) {
    New-Item `
        -ItemType Directory `
        -Path $BaseFolder `
        -Force | Out-Null
}

# ============================================================================
# DOWNLOAD MICROSOFT UPDATE CATALOG PAGE
# ============================================================================

Write-Host "Downloading Microsoft Update Catalog search page..." -ForegroundColor Cyan

try {
    $Response = Invoke-WebRequest `
        -Uri $SearchUrl `
        -UseBasicParsing
}
catch {
    Write-Error "Failed to download Microsoft Update Catalog page."
    Write-Error $_.Exception.Message
    exit 1
}

$Html = $Response.Content

if ([string]::IsNullOrWhiteSpace($Html)) {
    Write-Error "Microsoft Update Catalog returned an empty page."
    exit 1
}

Write-Host "Catalog page downloaded successfully." -ForegroundColor Green

# ============================================================================
# FIND LATEST MATCHING UPDATE
# ============================================================================

$Update = Get-LatestUpdateRow -Html $Html

if ($null -eq $Update) {

    Write-Host ""
    Write-Host "ERROR: No matching Windows 11 26H2 x64 cumulative security update found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Search URL:" -ForegroundColor Yellow
    Write-Host $SearchUrl
    Write-Host ""

    exit 1
}

$KB   = $Update.KB
$GUID = $Update.GUID

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " MATCH FOUND" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "KB:          $KB" -ForegroundColor White
Write-Host "GUID:        $GUID" -ForegroundColor White
Write-Host "Architecture: x64 ONLY" -ForegroundColor White

if ($Update.UpdateDate) {
    Write-Host "Date:        $($Update.UpdateDate.ToString('yyyy-MM-dd'))" -ForegroundColor White
}

Write-Host ""

# ============================================================================
# GET DOWNLOAD URL
# ============================================================================

$DownloadUrl = Get-DownloadUrl -Guid $GUID

if ([string]::IsNullOrWhiteSpace($DownloadUrl)) {

    Write-Error "Could not obtain an MSU download URL for $KB."
    exit 1
}

Write-Host ""
Write-Host "Download URL found:" -ForegroundColor Green
Write-Host $DownloadUrl
Write-Host ""

# ============================================================================
# CREATE KB DIRECTORY
# ============================================================================

$KbFolder = Join-Path $BaseFolder $KB

if (-not (Test-Path $KbFolder)) {
    New-Item `
        -ItemType Directory `
        -Path $KbFolder `
        -Force | Out-Null
}

$OutputFile = Join-Path `
    $KbFolder `
    "Windows11-26H2-$KB-x64.msu"

# ============================================================================
# DOWNLOAD MSU
# ============================================================================

Write-Host "Downloading $KB..." -ForegroundColor Cyan
Write-Host ""
Write-Host "Destination:" -ForegroundColor Yellow
Write-Host $OutputFile
Write-Host ""

$Downloaded = $false

# ============================================================================
# TRY BITS FIRST
# ============================================================================

try {

    Write-Host "Attempting BITS download..." -ForegroundColor Cyan

    Start-BitsTransfer `
        -Source $DownloadUrl `
        -Destination $OutputFile `
        -DisplayName "Windows 11 26H2 $KB x64" `
        -Description "Downloading Windows 11 26H2 x64 cumulative update" `
        -ErrorAction Stop

    $Downloaded = $true

    Write-Host "BITS download completed." -ForegroundColor Green
}
catch {

    Write-Warning "BITS download failed:"
    Write-Warning $_.Exception.Message

    Write-Host ""
    Write-Host "Falling back to Invoke-WebRequest..." -ForegroundColor Yellow

    try {

        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $OutputFile `
            -UseBasicParsing `
            -ErrorAction Stop

        $Downloaded = $true

        Write-Host "Invoke-WebRequest download completed." -ForegroundColor Green
    }
    catch {

        Write-Error "Download failed."
        Write-Error $_.Exception.Message

        exit 1
    }
}

# ============================================================================
# VERIFY FILE
# ============================================================================

if (-not (Test-Path $OutputFile)) {

    Write-Error "Download completed but the MSU file does not exist."
    exit 1
}

$FileInfo = Get-Item $OutputFile

if ($FileInfo.Length -eq 0) {

    Write-Error "Downloaded MSU is 0 bytes."
    exit 1
}

Write-Host ""
Write-Host "Download verified." -ForegroundColor Green
Write-Host "File size: $([math]::Round($FileInfo.Length / 1MB, 2)) MB" -ForegroundColor White

# ============================================================================
# SHA256
# ============================================================================

Write-Host ""
Write-Host "Calculating SHA256..." -ForegroundColor Cyan

$Hash = Get-FileHash `
    -Path $OutputFile `
    -Algorithm SHA256

Write-Host ""
Write-Host "SHA256:" -ForegroundColor Yellow
Write-Host $Hash.Hash -ForegroundColor White

# ============================================================================
# WRITE README
# ============================================================================

$ReadmePath = Join-Path $KbFolder "README.txt"

$Readme = @"
Windows 11 26H2 Cumulative Security Update
============================================

KB:
$KB

Architecture:
x64 ONLY

Product:
Windows 11

Version:
26H2

Update Type:
Cumulative Update

Category:
Windows 11 Security Updates

Update GUID:
$GUID

Download Date:
$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

File:
$($FileInfo.Name)

Size:
$([math]::Round($FileInfo.Length / 1MB, 2)) MB

SHA256:
$($Hash.Hash)

Microsoft Update Catalog Search:
$SearchUrl

This package was selected specifically for:
    Windows 11
    Version 26H2
    x64
    Cumulative Update
    Windows 11 Security Updates

Excluded:
    ARM64
    x86
    32-bit
    Preview
    .NET
    Dynamic Update
    Safe OS Dynamic Update
    Setup Dynamic Update
"@

Set-Content `
    -Path $ReadmePath `
    -Value $Readme `
    -Encoding UTF8

# ============================================================================
# FINAL OUTPUT
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "KB:" -ForegroundColor Yellow
Write-Host $KB

Write-Host ""
Write-Host "MSU:" -ForegroundColor Yellow
Write-Host $OutputFile

Write-Host ""
Write-Host "SHA256:" -ForegroundColor Yellow
Write-Host $Hash.Hash

Write-Host ""
Write-Host "PDQ-ready folder:" -ForegroundColor Yellow
Write-Host $KbFolder

Write-Host ""
Write-Host "Architecture: x64 ONLY" -ForegroundColor Green
Write-Host "Windows version: 26H2" -ForegroundColor Green
Write-Host ""
