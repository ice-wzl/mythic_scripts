function Invoke-UserEnum {
    $UsersRoot = "C:\Users"

# Standard user-content locations that should be recursively searched.
$UserDirs = @(
    "Desktop",
    "Documents",
    "Downloads",
    "Favorites",
    "Links",
    "Music",
    "Pictures",
    "Saved Games",
    "Videos",
    "OneDrive",
    ".ssh"
)

# Useful AppData locations that are small enough to enumerate recursively.
$ImportantAppDataDirs = @(
    "AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine",
    "AppData\Roaming\Microsoft\Credentials",
    "AppData\Local\Microsoft\Credentials",
    "AppData\Roaming\Microsoft\Vault",
    "AppData\Local\Microsoft\Vault",
    "AppData\Roaming\FileZilla",
    "AppData\Roaming\mRemoteNG",
    "AppData\Roaming\Microsoft\Windows\Recent",
    "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup",
    "AppData\Local\Packages\Microsoft.MicrosoftStickyNotes_8wekyb3d8bbwe\LocalState"
)

# Exact browser artifacts worth identifying.
# Full browser profiles and caches are not recursively enumerated.
$BrowserArtifactPaths = @(
    # Microsoft Edge
    "AppData\Local\Microsoft\Edge\User Data\Local State",
    "AppData\Local\Microsoft\Edge\User Data\Default\Login Data",
    "AppData\Local\Microsoft\Edge\User Data\Default\Web Data",
    "AppData\Local\Microsoft\Edge\User Data\Default\History",
    "AppData\Local\Microsoft\Edge\User Data\Default\Network\Cookies",
    "AppData\Local\Microsoft\Edge\User Data\Default\Cookies",
    "AppData\Local\Microsoft\Edge\User Data\Default\Preferences",
    "AppData\Local\Microsoft\Edge\User Data\Default\Secure Preferences",
    "AppData\Local\Microsoft\Edge\User Data\Default\Bookmarks",

    # Google Chrome
    "AppData\Local\Google\Chrome\User Data\Local State",
    "AppData\Local\Google\Chrome\User Data\Default\Login Data",
    "AppData\Local\Google\Chrome\User Data\Default\Web Data",
    "AppData\Local\Google\Chrome\User Data\Default\History",
    "AppData\Local\Google\Chrome\User Data\Default\Network\Cookies",
    "AppData\Local\Google\Chrome\User Data\Default\Cookies",
    "AppData\Local\Google\Chrome\User Data\Default\Preferences",
    "AppData\Local\Google\Chrome\User Data\Default\Secure Preferences",
    "AppData\Local\Google\Chrome\User Data\Default\Bookmarks"
)

# Firefox profiles have dynamically generated directory names.
$FirefoxArtifactNames = @(
    "logins.json",
    "key4.db",
    "key3.db",
    "cookies.sqlite",
    "places.sqlite",
    "formhistory.sqlite",
    "permissions.sqlite",
    "cert9.db",
    "cert8.db",
    "sessionstore.jsonlz4"
)

# All Users is normally a compatibility junction to shared application data.
# Only these targeted locations will be checked.
$AllUsersPaths = @(
    "ssh",
    "Desktop",
    "Documents",
    "Microsoft\Windows\Start Menu\Programs\Startup"
)

# Entries excluded from the normal profile loop.
$ExcludedProfiles = @(
    "All Users",
    "Default User"
)

$InterestingExtensions = @(
    ".exe",
    ".dll",
    ".bat",
    ".cmd",
    ".ps1",
    ".psm1",
    ".psd1",
    ".vbs",
    ".vbe",
    ".js",
    ".jse",
    ".wsf",
    ".hta",
    ".py",
    ".pl",
    ".rb",
    ".jar",

    ".config",
    ".conf",
    ".cfg",
    ".ini",
    ".xml",
    ".json",
    ".yaml",
    ".yml",

    ".txt",
    ".log",
    ".bak",
    ".old",
    ".backup",
    ".save",

    ".zip",
    ".7z",
    ".rar",
    ".tar",
    ".gz",

    ".kdbx",
    ".pem",
    ".key",
    ".ppk",
    ".pfx",
    ".p12",
    ".pub",

    ".rdp",
    ".ovpn",

    ".db",
    ".sqlite",
    ".sqlite3",

    ".xls",
    ".xlsx",
    ".doc",
    ".docx",
    ".pdf"
)

$InterestingNameRegex = '(?i)' + (
    @(
        'pass(word)?',
        'passwd',
        'cred',
        'secret',
        'token',
        'private',
        'admin',
        'backup',
        'config',
        'connection',
        'database',
        'wallet',
        'unattend',
        'sysprep',
        'web\.config',
        'id_rsa',
        'id_dsa',
        'id_ecdsa',
        'id_ed25519',
        'authorized_keys',
        'known_hosts',
        'history',
        'psreadline',
        'session',
        'ssh',
        'login data',
        'local state',
        'secure preferences',
        'bookmarks',
        'cookies',
        'places\.sqlite',
        'logins\.json',
        'key[34]\.db'
    ) -join '|'
)

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    return [bool](
        $Item.Attributes -band [IO.FileAttributes]::ReparsePoint
    )
}

function Test-ShouldSkip {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    # Common Windows metadata file with little enumeration value.
    if ($Item.Name -ieq "desktop.ini") {
        return $true
    }

    # Common temporary database files that usually add noise.
    if (
        $Item.Name -match '(?i)-journal$' -or
        $Item.Name -match '(?i)-wal$' -or
        $Item.Name -match '(?i)-shm$'
    ) {
        return $true
    }

    return $false
}

function Test-IsInteresting {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    if (Test-ShouldSkip -Item $Item) {
        return $false
    }

    if ($Item.PSIsContainer) {
        return $Item.Name -match $InterestingNameRegex
    }

    $Extension = $Item.Extension.ToLowerInvariant()

    return (
        $InterestingExtensions -contains $Extension -or
        $Item.Name -match $InterestingNameRegex
    )
}

function Write-ItemResult {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    if (Test-ShouldSkip -Item $Item) {
        return
    }

    $Marker = if (Test-IsInteresting -Item $Item) {
        "[!]"
    }
    else {
        "[ ]"
    }

    if ($Item.PSIsContainer) {
        Write-Output "$Marker DIR  $($Item.FullName)"
    }
    else {
        Write-Output "$Marker FILE $($Item.FullName) [$($Item.Length) bytes]"
    }
}

function Test-DirectoryAccess {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        Get-Item `
            -LiteralPath $Path `
            -Force `
            -ErrorAction Stop |
            Out-Null

        Get-ChildItem `
            -LiteralPath $Path `
            -Force `
            -ErrorAction Stop |
            Select-Object -First 1 |
            Out-Null

        return $true
    }
    catch {
        return $false
    }
}

function Get-SafeDirectoryListing {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    Write-Output ""
    Write-Output "--- Recursive: $Path ---"

    try {
        if ($Recurse) {
            Get-ChildItem `
                -LiteralPath $Path `
                -Force `
                -Recurse `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    -not (Test-IsReparsePoint -Item $_)
                } |
                ForEach-Object {
                    Write-ItemResult -Item $_
                }
        }
        else {
            Get-ChildItem `
                -LiteralPath $Path `
                -Force `
                -ErrorAction SilentlyContinue |
                ForEach-Object {
                    Write-ItemResult -Item $_
                }
        }
    }
    catch {
        Write-Output "[-] Enumeration failed: $Path"
        Write-Output "    $($_.Exception.Message)"
    }
}

function Get-BrowserArtifacts {
    param(
        [Parameter(Mandatory)]
        [string]$UserPath
    )

    $FoundHeading = $false

    foreach ($RelativePath in $BrowserArtifactPaths) {
        $Path = Join-Path $UserPath $RelativePath

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            if (-not $FoundHeading) {
                Write-Output ""
                Write-Output "--- Browser Artifacts ---"
                $FoundHeading = $true
            }

            $Item = Get-Item `
                -LiteralPath $Path `
                -Force `
                -ErrorAction SilentlyContinue

            if ($null -ne $Item) {
                Write-ItemResult -Item $Item
            }
        }
    }

    $FirefoxProfilesRoot = Join-Path `
        $UserPath `
        "AppData\Roaming\Mozilla\Firefox\Profiles"

    if (-not (Test-Path -LiteralPath $FirefoxProfilesRoot -PathType Container)) {
        return
    }

    $FirefoxProfiles = Get-ChildItem `
        -LiteralPath $FirefoxProfilesRoot `
        -Directory `
        -Force `
        -ErrorAction SilentlyContinue

    foreach ($Profile in $FirefoxProfiles) {
        foreach ($ArtifactName in $FirefoxArtifactNames) {
            $ArtifactPath = Join-Path $Profile.FullName $ArtifactName

            if (Test-Path -LiteralPath $ArtifactPath -PathType Leaf) {
                if (-not $FoundHeading) {
                    Write-Output ""
                    Write-Output "--- Browser Artifacts ---"
                    $FoundHeading = $true
                }

                $Item = Get-Item `
                    -LiteralPath $ArtifactPath `
                    -Force `
                    -ErrorAction SilentlyContinue

                if ($null -ne $Item) {
                    Write-ItemResult -Item $Item
                }
            }
        }
    }
}

Write-Output "============================================================"
Write-Output " C:\USERS ENUMERATION"
Write-Output "============================================================"

Get-ChildItem `
    -LiteralPath $UsersRoot `
    -Directory `
    -Force `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -notin $ExcludedProfiles
    } |
    ForEach-Object {

        $UserPath = $_.FullName
        $UserName = $_.Name

        Write-Output ""
        Write-Output "==================== $UserName ===================="

        if (-not (Test-DirectoryAccess -Path $UserPath)) {
            Write-Output "[-] No access: $UserPath"
            return
        }

        Write-Output "[+] Access: $UserPath"

        # Enumerate files and directories directly in the profile root.
        # This catches files such as:
        #
        # C:\Users\eric.wallows\admintool.exe
        Write-Output ""
        Write-Output "--- Profile Root: $UserPath ---"

        Get-ChildItem `
            -LiteralPath $UserPath `
            -Force `
            -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-ItemResult -Item $_
            }

        # Recursively enumerate standard user-content directories.
        foreach ($Directory in $UserDirs) {
            $Path = Join-Path $UserPath $Directory

            if (Test-Path -LiteralPath $Path -PathType Container) {
                Get-SafeDirectoryListing -Path $Path -Recurse
            }
        }

        # Recursively enumerate selected high-value AppData locations.
        Write-Output ""
        Write-Output "--- Selected AppData Locations ---"

        foreach ($RelativePath in $ImportantAppDataDirs) {
            $Path = Join-Path $UserPath $RelativePath

            if (Test-Path -LiteralPath $Path -PathType Container) {
                Get-SafeDirectoryListing -Path $Path -Recurse
            }
        }

        # Print only exact browser artifacts.
        Get-BrowserArtifacts -UserPath $UserPath

        # Recursively inspect unexpected real directories directly beneath
        # each profile root.
        #
        # AppData and standard user directories are excluded because they were
        # already handled above.
        #
        # Reparse points are excluded to prevent junction loops.
        $AdditionalDirectories = Get-ChildItem `
            -LiteralPath $UserPath `
            -Directory `
            -Force `
            -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-IsReparsePoint -Item $_) -and
                $_.Name -notin $UserDirs -and
                $_.Name -ne "AppData"
            }

        if ($AdditionalDirectories) {
            Write-Output ""
            Write-Output "--- Additional Profile-Root Directories ---"

            foreach ($Directory in $AdditionalDirectories) {
                Get-SafeDirectoryListing `
                    -Path $Directory.FullName `
                    -Recurse
            }
        }
    }

# Handle C:\Users\All Users separately.
# Do not enumerate its root or recursively walk the Microsoft subtree.
Write-Output ""
Write-Output "============================================================"
Write-Output " ALL USERS TARGETED ENUMERATION"
Write-Output "============================================================"

$FoundAllUsersPath = $false

foreach ($RelativePath in $AllUsersPaths) {
    $Path = Join-Path $UsersRoot "All Users\$RelativePath"

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $FoundAllUsersPath = $true

        Get-SafeDirectoryListing `
            -Path $Path `
            -Recurse
    }
}

if (-not $FoundAllUsersPath) {
    Write-Output "[-] No targeted All Users paths were accessible or present."
}

Write-Output ""
Write-Output "============================================================"
Write-Output " ENUMERATION COMPLETE"
Write-Output " [!] indicates a potentially interesting item"
Write-Output "============================================================"
}