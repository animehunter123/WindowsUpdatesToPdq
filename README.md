# Description

1. This has NTLite Photos for the WIM Update process for the lab image we use (for MDT/SCCM/WAPT etc).

2. This has the scripts we use on the NAS to download the _PATCH TUESDAY_ *x64-only, monthly cumulative security update only* of either 24H2 or 26H2.

These are then loaded into PDQ on the lab and will update in-place. 

If you wish to go from 24H2 > 25H2 or higher you MUST ONLY F12 your BOX COMPLETELY (This is JTs recommendation).



# Usage:

* Run this script, it will make a YYYYmmdd folder for "this months tuesday update" with Cumulative Update file (has security updates as well inside of it)

* Burn to high side and import it into PDQ

Just FYI... Then for high side add them into pdq.

WIN11 24H2 >> ONLY UPDATES TO >> WIN11 24H2 (LATEST MONTHLY PATCH TUESDAY)
WIN11 26H2 >> ONLY UPDATES TO >> WIN11 26H2 (LATEST MONTHLY PATCH TUESDAY)


# Sample output of running the script
```powershell
$ .\Download-Windows11-26H2-Cumulative.ps1

============================================================
 Windows 11 26H2 x64 Cumulative Update Downloader
============================================================

Search URL:
https://www.catalog.update.microsoft.com/Search.aspx?q=Windows+11+26H2+x64+cumulative+update

Output folder:
\\MYTRUENAS01\software\WindowsUpdatesToPdq\26H2\.\20261008-Windows11-26H2-Cumulative

Downloading Microsoft Update Catalog search page...
Catalog page downloaded successfully.
Parsing Microsoft Update Catalog results...
Found 20 table rows.

Matching x64 Windows 11 26H2 cumulative updates:
  KB5129195
    Date: 2026-09-29
    GUID: be656f78-0714-440c-a0be-b27b4f9e5d71

============================================================
 MATCH FOUND
============================================================

KB:          KB5129195
GUID:        be656f78-0714-440c-a0be-b27b4f9e5d71
Architecture: x64 ONLY
Date:        2026-09-29


Getting download information for be656f78-0714-440c-a0be-b27b4f9e5d71 ...

Download URL found:
https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/471c8f54-b9fc-491d-9944-234d5db009f0/public/windows11.0-kb5129195-x64_ed361878ec2b56a7dfdb8f256565263a7fdc8eaa.msu

Downloading KB5129195...

Destination:
\\MYTRUENAS01\software\WindowsUpdatesToPdq\26H2\.\20261008-Windows11-26H2-Cumulative\KB5129195\Windows11-26H2-KB5129195-x64.msu

Attempting BITS download...
BITS download completed.

Download verified.
File size: 4424.5 MB

Calculating SHA256...

SHA256:
B33FF7AAB5BBBBB73867F3F5C2F492FE97C0129B96AA1941BC270610D7876DFA

============================================================
 COMPLETE
============================================================

KB:
KB5129195

MSU:
\\MYTRUENAS01\software\WindowsUpdatesToPdq\26H2\.\20261008-Windows11-26H2-Cumulative\KB5129195\Windows11-26H2-KB5129195-x64.msu

SHA256:
B33FF7AAB5BBBBB73867F3F5C2F492FE97C0129B96AA1941BC270610D7876DFA

PDQ-ready folder:
\\MYTRUENAS01\software\WindowsUpdatesToPdq\26H2\.\20261008-Windows11-26H2-Cumulative\KB5129195

Architecture: x64 ONLY
Windows version: 26H2
```




# Useful AI-EXPLANATION to read if you have further questions
-----
-----
-----
-----




Yep. If your goal is **offline PDQ deployment of only the normal monthly Windows 11 24H2 security/cumulative update**, you can keep this very simple.

The important distinction is: **don't download the Preview, Safe OS Dynamic Update, Setup Dynamic Update, or other optional packages.** The Microsoft Update Catalog currently lists the normal 24H2 cumulative security update separately. 

### 1. Find the correct update

Go to the official:

[Microsoft Update Catalog — Windows 11 24H2 x64](https://www.catalog.update.microsoft.com/Search.aspx?q=cumulative+update+for+windows+11+version+24H2+x64-based+systems&utm_source=chatgpt.com)

Search for:

```text
Windows 11 24H2 x64 cumulative update
```

For example, the current September 2026 entry is:

```text
2026-09 Cumulative Update for Windows 11,
version 24H2 for x64-based Systems
(KB5129195)
```

The Catalog identifies it as:

```text
Windows 11 Security Updates
```

and **not** as a Preview update. 

#### Pick this

```text
2026-09 Cumulative Update for Windows 11,
version 24H2 for x64-based Systems
(KB5129195)
```

assuming you're deploying that month's patch.

#### Do NOT pick these

```text
Cumulative Update Preview
Safe OS Dynamic Update
Setup Dynamic Update
.NET Update
Servicing Stack Update
Windows Defender updates
```

For your stated goal, you want the regular:

> **Cumulative Update for Windows 11, version 24H2 for x64-based Systems**

---

## 2. Download the `.msu`

Click **Download** beside the correct Catalog entry.

You'll get an `.msu`, something like:

```text
windows11.0-kb5129195-x64_....msu
```

Put it somewhere on your PDQ server/repository, for example:

```text
D:\PDQRepository\Windows11-24H2\
```

I would rename it something obvious:

```text
Windows11-24H2-KB5129195-x64.msu
```

That makes your PDQ repository much easier to understand six months from now.

---

## 3. Create a PDQ Deploy package

In **PDQ Deploy**:

```text
New Package
```

Name it:

```text
Windows 11 24H2 - KB5129195
```

Then:

```text
New Step
    Install
```

For **Install File**, select:

```text
Windows11-24H2-KB5129195-x64.msu
```

PDQ Deploy supports `.MSU` files directly and uses `wusa.exe` to install them. 

---

## 4. Configure the MSU install

For the Install step, use:

```text
Operation: Install
Quiet: Yes
```

For reboot behavior, I'd initially use:

```text
Restart: Prompt / No immediate restart
```

or whatever your PDQ policy is for rebooting.

The important thing is that you **don't need to manually construct a `wusa.exe` command** for a normal MSU. PDQ's Install step handles MSU installation and exposes the appropriate MSU options. 

Conceptually, Windows is doing:

```cmd
wusa.exe Windows11-24H2-KB5129195-x64.msu /quiet
```

---

## 5. Make sure you're targeting 24H2

This is the part I'd be careful about.

Create a PDQ collection containing your:

```text
Windows 11 24H2
```

machines.

Then deploy the package to that collection.

You don't want to accidentally throw a 24H2-specific package at:

```text
Windows 11 23H2
Windows 10
Windows Server
Windows 11 ARM64
```

For your environment, I'd make the PDQ collection something like:

```text
Windows 11
└── 24H2
    └── x64
```

---

## 6. Test on one machine first

Before deploying to everything:

```text
PC01
```

Deploy:

```text
Windows 11 24H2 - KB5129195
```

Then check:

```cmd
winver
```

or:

```powershell
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber
```

You can also check the KB:

```powershell
Get-HotFix -Id KB5129195
```

If installed, you'll get the KB information back.

---

## 7. Then deploy to the PDQ collection

Once your test machine works:

```text
Deploy
    Windows 11 24H2 - KB5129195
    ↓
    Windows 11 24H2 x64 collection
```

PDQ supports deploying packages directly to target machines or collections/schedules. 

---

### One important thing for your offline homelab

Since you're deliberately doing this **offline**, I'd actually organize your repository like this:

```text
D:\PDQRepository\
└── Microsoft\
    └── Windows11\
        └── 24H2\
            ├── 2026-09\
            │   └── Windows11-24H2-KB5129195-x64.msu
            ├── 2026-10\
            │   └── Windows11-24H2-KBxxxxx-x64.msu
            └── ...
```

Then your PDQ packages become:

```text
Microsoft - Windows 11 24H2 - 2026-09 - KB5129195
Microsoft - Windows 11 24H2 - 2026-10 - KBxxxxx
Microsoft - Windows 11 24H2 - 2026-11 - KBxxxxx
```

That gives you a **very clean offline patch repository**.

#### And you don't need to download a pile of prerequisite updates

For the normal monthly cumulative security update, don't go grabbing every individual KB you see in the Catalog. The cumulative update is designed to contain the applicable fixes for that release. The Catalog does, however, show several *different* update types alongside it, which is why it can look confusing. 

**So your workflow is basically:**

```text
Microsoft Update Catalog
        ↓
Windows 11 24H2 x64
        ↓
" Cumulative Update "
        ↓
NOT "Preview"
        ↓
Download .MSU
        ↓
Copy to PDQ Repository
        ↓
PDQ Install Step
        ↓
Test 1 PC
        ↓
Deploy to Windows 11 24H2 collection
```

If you're doing this for your **offline 24H2 → 26H2 work**, there's one wrinkle: **don't mix the 26H2 enablement/feature update files into this PDQ monthly-patching package**. Keep the monthly 24H2 cumulative updates as their own PDQ packages.
