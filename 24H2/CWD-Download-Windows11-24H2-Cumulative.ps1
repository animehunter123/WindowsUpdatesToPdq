#requires -Version 5.1

<#
.SYNOPSIS
    Downloads the latest Windows 11 24H2 x64 cumulative security update
    from the Microsoft Update Catalog.

.DESCRIPTION
    This script searches the Microsoft Update Catalog for:

      Windows 11
      Version 24H2
      x64-based Systems
      Cumulative Update
      Security Updates

    It intentionally excludes:

      - Cumulative Update Preview
      - .NET Framework updates
      - Safe OS Dynamic Updates
      - Setup Dynamic Updates
      - ARM64 updates
      - x86 / 32-bit updates
      - Other architectures

    The resulting .MSU is saved into:

      .\YYYYMMDD-Windows11-24H2-Cumulative\<KB>\

    Example:

      .\20261008-Windows11-24H2-Cumulative\KB5129195\
          Windows11-24H2-KB5129195-x64.msu
          README.txt
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$SearchUrl = "https://www.catalog.update.microsoft.com/Search.aspx?q=Windows+11+24H2+x64+cumulative+update"

$DATE = Get-Date -Format 'yyyyMMdd'

$BaseFolder = Join-Path `
    $PSScriptRoot `
    ".\$DATE-Windows11-24H2-Cumulative"

# ------------------------------------------------------------
# Create output directory
# ------------------------------------------------------------

if (-not (Test-Path $BaseFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $BaseFolder `
        -Force |
        Out-Null
}

# ------------------------------------------------------------
# Display header
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Windows 11 24H2 x64 Cumulative Security Update Downloader" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Architecture filter: x64 ONLY" -ForegroundColor Green
Write-Host ""

Write-Host "Searching Microsoft Update Catalog..." -ForegroundColor Yellow
Write-Host ""

# ------------------------------------------------------------
# HTTP headers
# ------------------------------------------------------------

$Headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
}

# ------------------------------------------------------------
# Download Catalog search page
# ------------------------------------------------------------

try {

    $Response = Invoke-WebRequest `
        -Uri $SearchUrl `
        -Headers $Headers `
        -UseBasicParsing
}
catch {

    Write-Host ""
    Write-Host "ERROR: Could not access Microsoft Update Catalog." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    exit 1
}

$Html = $Response.Content

# ------------------------------------------------------------
# Find table rows
#
# Microsoft changes the exact HTML markup occasionally.
# Therefore we:
#
#   1. Find table rows.
#   2. Convert the row to readable text.
#   3. Search the readable text.
#
# ------------------------------------------------------------

$RowMatches = [regex]::Matches(
    $Html,
    '(?is)<tr\b[^>]*>.*?</tr>'
)

Write-Host "Catalog rows found: $($RowMatches.Count)" -ForegroundColor Gray
Write-Host ""

# ------------------------------------------------------------
# Parse candidates
# ------------------------------------------------------------

$Candidates = @()

foreach ($Match in $RowMatches) {

    $RowHtml = $Match.Value

    # --------------------------------------------------------
    # Convert HTML row into plain text
    # --------------------------------------------------------

    $RowText = $RowHtml

    # Remove scripts/styles first
    $RowText = [regex]::Replace(
        $RowText,
        '(?is)<script\b.*?</script>',
        ' '
    )

    $RowText = [regex]::Replace(
        $RowText,
        '(?is)<style\b.*?</style>',
        ' '
    )

    # Remove HTML tags
    $RowText = [regex]::Replace(
        $RowText,
        '<[^>]+>',
        ' '
    )

    # Decode HTML entities
    $RowText = [System.Net.WebUtility]::HtmlDecode($RowText)

    # Normalize whitespace
    $RowText = $RowText -replace '\s+', ' '
    $RowText = $RowText.Trim()

    # --------------------------------------------------------
    # REQUIRED ARCHITECTURE
    #
    # The update MUST explicitly say:
    #
    #     x64-based Systems
    #
    # This means ARM64/x86/etc. cannot qualify.
    # --------------------------------------------------------

    if ($RowText -notmatch '(?i)\bx64-based Systems\b') {
        continue
    }

    # --------------------------------------------------------
    # Explicitly reject other architectures
    # --------------------------------------------------------

    if ($RowText -match '(?i)\bARM64\b') {
        continue
    }

    if ($RowText -match '(?i)\bx86\b') {
        continue
    }

    if ($RowText -match '(?i)\b32-bit\b') {
        continue
    }

    # --------------------------------------------------------
    # REQUIRED PRODUCT / VERSION
    # --------------------------------------------------------

    if ($RowText -notmatch '(?i)Windows 11') {
        continue
    }

    if ($RowText -notmatch '(?i)version 24H2') {
        continue
    }

    # --------------------------------------------------------
    # REQUIRED UPDATE TYPE
    # --------------------------------------------------------

    if ($RowText -notmatch '(?i)Cumulative Update') {
        continue
    }

    if ($RowText -notmatch '(?i)Windows 11 Security Updates') {
        continue
    }

    # --------------------------------------------------------
    # EXCLUSIONS
    # --------------------------------------------------------

    # Preview
    if ($RowText -match '(?i)Cumulative Update Preview') {
        continue
    }

    # .NET
    if ($RowText -match '(?i)\.NET Framework') {
        continue
    }

    # Dynamic Updates
    if ($RowText -match '(?i)Dynamic Update') {
        continue
    }

    # Safe OS
    if ($RowText -match '(?i)Safe OS') {
        continue
    }

    # Setup Dynamic Update
    if ($RowText -match '(?i)Setup Dynamic') {
        continue
    }

    # --------------------------------------------------------
    # Extract KB number
    # --------------------------------------------------------

    $KbMatch = [regex]::Match(
        $RowText,
        '(?i)\bKB(\d{6,8})\b'
    )

    if (-not $KbMatch.Success) {
        continue
    }

    $KB = "KB$($KbMatch.Groups[1].Value)"

    # --------------------------------------------------------
    # Extract UpdateID GUID
    #
    # The Catalog uses this GUID when calling
    # DownloadDialog.aspx.
    # --------------------------------------------------------

    $GuidMatch = [regex]::Match(
        $RowHtml,
        '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    )

    if (-not $GuidMatch.Success) {

        Write-Host "WARNING: Could not find UpdateID for $KB" -ForegroundColor Yellow

        continue
    }

    $UpdateGuid = $GuidMatch.Value

    # --------------------------------------------------------
    # Store candidate
    # --------------------------------------------------------

    $Candidates += [PSCustomObject]@{
        KB         = $KB
        Title      = $RowText
        UpdateGuid = $UpdateGuid
        Html       = $RowHtml
    }
}

# ------------------------------------------------------------
# Make sure we found something
# ------------------------------------------------------------

if ($Candidates.Count -eq 0) {

    Write-Host ""
    Write-Host "ERROR: No matching Windows 11 24H2 x64 cumulative" -ForegroundColor Red
    Write-Host "security update was found." -ForegroundColor Red
    Write-Host ""

    Write-Host "The script requires:" -ForegroundColor Yellow
    Write-Host "  Windows 11"
    Write-Host "  Version 24H2"
    Write-Host "  x64-based Systems"
    Write-Host "  Cumulative Update"
    Write-Host "  Windows 11 Security Updates"
    Write-Host ""

    Write-Host "Search URL:" -ForegroundColor Yellow
    Write-Host $SearchUrl
    Write-Host ""

    # Save the returned HTML for troubleshooting.
    $DebugHtml = Join-Path `
        $BaseFolder `
        "Catalog-Debug.html"

    $Html | Set-Content `
        -Path $DebugHtml `
        -Encoding UTF8

    Write-Host "The Catalog HTML was saved here for troubleshooting:" -ForegroundColor Yellow
    Write-Host $DebugHtml
    Write-Host ""

    exit 1
}

# ------------------------------------------------------------
# Display candidates
# ------------------------------------------------------------

Write-Host "Matching x64-only updates found:" -ForegroundColor Green
Write-Host ""

foreach ($Candidate in $Candidates) {

    Write-Host "  $($Candidate.KB)" -ForegroundColor White
    Write-Host "  $($Candidate.Title)" -ForegroundColor Gray
    Write-Host "  UpdateID: $($Candidate.UpdateGuid)" -ForegroundColor DarkGray
    Write-Host ""
}

# ------------------------------------------------------------
# Select newest entry
#
# Use the highest KB number.
# ------------------------------------------------------------

$Selected = $Candidates |
    Sort-Object {
        [int64]($_.KB -replace '^KB', '')
    } -Descending |
    Select-Object -First 1

$KB = $Selected.KB

$UpdateGuid = $Selected.UpdateGuid

# ------------------------------------------------------------
# Display selected update
# ------------------------------------------------------------

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Selected x64 update: $KB" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Title:" -ForegroundColor Yellow
Write-Host $Selected.Title
Write-Host ""

Write-Host "Architecture:" -ForegroundColor Yellow
Write-Host "x64 ONLY"
Write-Host ""

Write-Host "UpdateID:" -ForegroundColor Yellow
Write-Host $UpdateGuid
Write-Host ""

# ------------------------------------------------------------
# Microsoft Update Catalog Download Dialog
# ------------------------------------------------------------

Write-Host "Requesting Microsoft Catalog download information..." -ForegroundColor Yellow
Write-Host ""

$DownloadPage = "https://www.catalog.update.microsoft.com/DownloadDialog.aspx"

$Body = @{
    updateIDs = "[{`"size`":0,`"updateID`":`"$UpdateGuid`",`"uidInfo`":`"$UpdateGuid`"}]"
}

$DownloadUrl = $null

try {

    $DownloadResponse = Invoke-WebRequest `
        -Uri $DownloadPage `
        -Method Post `
        -Body $Body `
        -Headers $Headers `
        -UseBasicParsing

    $DownloadHtml = $DownloadResponse.Content

}
catch {

    Write-Host ""
    Write-Host "ERROR: Could not contact the Microsoft Catalog download dialog." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    exit 1
}

# ------------------------------------------------------------
# Find MSU URL
# ------------------------------------------------------------

$UrlMatches = [regex]::Matches(
    $DownloadHtml,
    '(?i)https?://[^''"<> ]+?\.msu(?:\?[^''"<> ]*)?'
)

if ($UrlMatches.Count -gt 0) {

    $DownloadUrl = $UrlMatches[0].Value
}

# ------------------------------------------------------------
# Try a second pattern if necessary
# ------------------------------------------------------------

if (-not $DownloadUrl) {

    $UrlMatches = [regex]::Matches(
        $DownloadHtml,
        '(?i)(?:url|downloadUrl|FileUrl)\s*=\s*[''"]([^''"]+\.msu[^''"]*)[''"]'
    )

    if ($UrlMatches.Count -gt 0) {

        $DownloadUrl = $UrlMatches[0].Groups[1].Value
    }
}

# ------------------------------------------------------------
# Stop if download URL wasn't found
# ------------------------------------------------------------

if (-not $DownloadUrl) {

    Write-Host ""
    Write-Host "ERROR: Microsoft Catalog did not expose the MSU download URL." -ForegroundColor Red
    Write-Host ""

    $DebugDownload = Join-Path `
        $BaseFolder `
        "$KB-DownloadDialog-Debug.html"

    $DownloadHtml | Set-Content `
        -Path $DebugDownload `
        -Encoding UTF8

    Write-Host "The download dialog response was saved here:" -ForegroundColor Yellow
    Write-Host $DebugDownload
    Write-Host ""

    exit 1
}

# ------------------------------------------------------------
# Clean URL
# ------------------------------------------------------------

$DownloadUrl = [System.Net.WebUtility]::HtmlDecode(
    $DownloadUrl
)

$DownloadUrl = $DownloadUrl `
    -replace '&amp;', '&' `
    -replace '&#x3a;', ':' `
    -replace '\\/', '/'

Write-Host "Download URL found." -ForegroundColor Green
Write-Host ""

# ------------------------------------------------------------
# Create KB directory
# ------------------------------------------------------------

$KbFolder = Join-Path `
    $BaseFolder `
    $KB

if (-not (Test-Path $KbFolder)) {

    New-Item `
        -ItemType Directory `
        -Path $KbFolder `
        -Force |
        Out-Null
}

# ------------------------------------------------------------
# Destination filename
# ------------------------------------------------------------

$Destination = Join-Path `
    $KbFolder `
    "Windows11-24H2-$KB-x64.msu"

# ------------------------------------------------------------
# Skip if already downloaded
# ------------------------------------------------------------

if (Test-Path $Destination) {

    $ExistingSize = (Get-Item $Destination).Length

    if ($ExistingSize -gt 0) {

        Write-Host ""
        Write-Host "File already exists:" -ForegroundColor Yellow
        Write-Host $Destination
        Write-Host ""

        Write-Host "Size: $([math]::Round($ExistingSize / 1GB, 2)) GB" -ForegroundColor Gray
        Write-Host ""

        Write-Host "Nothing to download." -ForegroundColor Green
        Write-Host ""

        exit 0
    }
}

# ------------------------------------------------------------
# Download MSU
# ------------------------------------------------------------

Write-Host "Downloading x64 MSU:" -ForegroundColor Yellow
Write-Host $Selected.Title
Write-Host ""

Write-Host "Destination:" -ForegroundColor Yellow
Write-Host $Destination
Write-Host ""

try {

    Start-BitsTransfer `
        -Source $DownloadUrl `
        -Destination $Destination `
        -DisplayName "Windows 11 24H2 x64 $KB"

}
catch {

    Write-Host ""
    Write-Host "BITS download failed." -ForegroundColor Yellow
    Write-Host "Trying Invoke-WebRequest instead..." -ForegroundColor Yellow
    Write-Host ""

    try {

        Invoke-WebRequest `
            -Uri $DownloadUrl `
            -OutFile $Destination `
            -UseBasicParsing

    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Download failed." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""

        if (Test-Path $Destination) {

            Remove-Item `
                $Destination `
                -Force
        }

        exit 1
    }
}

# ------------------------------------------------------------
# Verify file exists
# ------------------------------------------------------------

if (-not (Test-Path $Destination)) {

    Write-Host ""
    Write-Host "ERROR: Download completed but file does not exist." -ForegroundColor Red
    Write-Host ""

    exit 1
}

$FileInfo = Get-Item $Destination

# ------------------------------------------------------------
# Verify file isn't empty
# ------------------------------------------------------------

if ($FileInfo.Length -eq 0) {

    Write-Host ""
    Write-Host "ERROR: Downloaded file is 0 bytes." -ForegroundColor Red
    Write-Host ""

    Remove-Item `
        $Destination `
        -Force

    exit 1
}

# ------------------------------------------------------------
# Calculate SHA256
# ------------------------------------------------------------

Write-Host ""
Write-Host "Calculating SHA256..." -ForegroundColor Yellow

$Hash = Get-FileHash `
    -Path $Destination `
    -Algorithm SHA256

# ------------------------------------------------------------
# Write metadata
# ------------------------------------------------------------

$Metadata = @"
Windows 11 24H2 x64 Cumulative Security Update
================================================

KB:
$KB

Architecture:
x64 ONLY

Title:
$($Selected.Title)

UpdateID:
$UpdateGuid

Downloaded:
$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

File:
$($FileInfo.Name)

Size:
$([math]::Round($FileInfo.Length / 1GB, 2)) GB

SHA256:
$($Hash.Hash)

Source:
$SearchUrl
"@

$MetadataPath = Join-Path `
    $KbFolder `
    "README.txt"

$Metadata | Set-Content `
    -Path $MetadataPath `
    -Encoding UTF8

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " DOWNLOAD COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "KB:" -ForegroundColor Yellow
Write-Host "  $KB"
Write-Host ""

Write-Host "Architecture:" -ForegroundColor Yellow
Write-Host "  x64 ONLY"
Write-Host ""

Write-Host "File:" -ForegroundColor Yellow
Write-Host "  $Destination"
Write-Host ""

Write-Host "Size:" -ForegroundColor Yellow
Write-Host "  $([math]::Round($FileInfo.Length / 1GB, 2)) GB"
Write-Host ""

Write-Host "SHA256:" -ForegroundColor Yellow
Write-Host "  $($Hash.Hash)"
Write-Host ""

Write-Host "Metadata:" -ForegroundColor Yellow
Write-Host "  $MetadataPath"
Write-Host ""

Write-Host "Ready to copy into your PDQ repository." -ForegroundColor Green
Write-Host ""
