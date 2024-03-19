# Author: BolverBlitz (Marc)
# Github: https://github.com/BolverBlitz/HCL-Communities-Cloner
# This is free to use and modify. (MIT)

# COLORFUL LOGS <3
# Most logs are with color so you can spot issues right away
# Red: Human should check
# Magenta: Deleting Files
# Green: Writing Files
# Yellow: Slow actions
# Gray: Markers where the script currently is (Community or Folder)
# Cyan: Modifying Metadata of files / folders

# How to get your token: (The cookieDomain is right next to the token)
# Open community
# Press F12 (Don´t do that when a scamer asks you this, but i´m a nice guy - So Don´t worry about it"
# Go to "Network" tab
# Press F5
# Click on the very first thing from the list
# Click on cookies in the section that just opend by your click (Sometimes you have to douple click)
# Look for "LtpaToken2" and richtklick the value in the cell behind and click copy
# Make a file where this script is located. The file must be named ltpaToken.txt and write your token inside this file.

param (
    [string]$communityRoute = "allmy",
    [int]$waitInLoop = 0
)

$sVersion = "3.2.0"

# Path to 7-Zip Executable (Needed for deflation, because otherwise UTF8 Chars will be broken)
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"

if (!(Test-Path $sevenZipPath)) {
  Write-Error "7-Zip.exe not found!!"
  exit
}

# Base URL of the API (Edit Stuff here)
$cookieDomain = ""  # Update this to the domain of your API
$baseServer = ""
$baseUri = "$baseServer/files/form/api"

$cookieFile = "./ltpaToken.txt"
$communityFile = "./communitys.txt"

if ($communityRoute -notin @("allmy", "owned")) {
    # Check if only a valid parameter was passed
    throw "Invalid value: $communityRoute. The variable must be either 'allmy' or 'owned'."
}

try {
    $cookieValue = Get-Content $cookieFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Host "Need help? https://github.com/BolverBlitz/HCL-Communities-Cloner?tab=readme-ov-file#how-to-obtain-your-ltpatoken2"
    Write-Error "Cookie Monster wants COOKIES!!! (Get your LtpaToken2 Token and put it into a file named ltpaToken.txt) - I promise, its fine"
    exit
}

# Check if we have auth cookie
if (-not $cookieValue) {
    Write-Host "Need help? Edit this file and look at info i left here"
    Write-Error "Cookie Monster wants COOKIES!!! (Get your LtpaToken2 Token and put it into a file named ltpaToken.txt) - I promise, its fine"
    exit
}

# Make current Timestamp
$epochStart = Get-Date -Date "1970-01-01T00:00:00Z"
$currentDate = Get-Date
$preventCache = [math]::Round((New-TimeSpan -Start $epochStart -End $currentDate).TotalMilliseconds)

# Make session
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# Add auth cookie(s)
$cookie = New-Object System.Net.Cookie
$cookie.Name = "LtpaToken2"
$cookie.Value = $cookieValue
$cookie.Domain = "$cookieDomain"
$session.Cookies.Add($cookie)

# Special Cases for Community Name Filtering
$specialCasePatterns = @()
function Special-Case-Function {
    param(
        [string]$title
    )
}


# A Function that you pass a function that gets retryed in case of failure on the first try
function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 15,
        [int]$DelayInMSSeconds = 100
    )

    $retryCount = 0
    while ($true) {
        try {
            & $ScriptBlock
            break  # Exit loop if successful
        } catch {
            if ($retryCount -lt $MaxRetries) {
                Start-Sleep -Milliseconds $DelayInMSSeconds
                $retryCount++
            } else {
                Write-Host "Operation failed after $MaxRetries retries."
                throw  # Re-throw the exception to signal ultimate failure
            }
        }
    }
}

# Log a message to console and disk
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        [string]$txtColor = "White",
        [string]$LogFilePath = "./log.txt",  # Default log path
        [string]$ELogFilePath = "./error.txt"  # Default error log path
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$($timestamp): $Message"
    Write-Host $logEntry -ForegroundColor $txtColor

    # Choose the appropriate log file based on the text color
    $targetLogFilePath = $LogFilePath
    if ($txtColor -eq "Red") {
        $targetLogFilePath = $ELogFilePath
    }

    # Log the message to the chosen log file
    Invoke-WithRetry -ScriptBlock {
        $logEntry | Out-File -FilePath $targetLogFilePath -Append -Encoding UTF8 -ErrorAction Stop
    }
}

function Check-ScriptVersion {
    $url = "https://api.github.com/repos/BolverBlitz/HCL-Communities-Cloner/releases/latest"

    try {
        $latestRelease = Invoke-RestMethod -Uri $url
        $latestVersion = $latestRelease.tag_name

        if ($sVersion -eq $latestVersion) {
            Write-Log "Your script is up to date. Current version: $sVersion." "Green"
        } elseif ($sVersion -gt $latestVersion) {
            Write-Log "Your script is ahead of the latest release. Your version: $sVersion. Latest release: $latestVersion." "Yellow"
        } else {
            Write-Log "A new version of the script is available: $latestVersion. Your current version:$sVersion." "Magenta"
        }
    } catch {
        Write-Error "An error occurred while checking the script version: $_"
    }
}


# Download a File
function Download-File {
    param (
        [Parameter(Mandatory=$true)]
        [string]$fileUrl,
        [Parameter(Mandatory=$true)]
        [string]$localPath,
        [Parameter(Mandatory=$true)]
        [string]$lastModifiedDate
    )

    # Target Folder exists
    $directoryPath = Split-Path -Path $localPath -Parent
    try {
        if (-not [System.IO.Directory]::Exists($directoryPath)) {
            [System.IO.Directory]::CreateDirectory($directoryPath) | Out-Null
        }
    }
    catch {
        Write-Log "Failed to process entries: $_" "Red"
    }

    # Create a tempFolder to store the file because Invoke-WebRequest can´t handle [] in folders or files
    $tempDirectory = Join-Path -Path $PSScriptRoot -ChildPath "_script_Temp"
    
    # Temp Folder exists
    if (-not [System.IO.Directory]::Exists($tempDirectory)) {
        [System.IO.Directory]::CreateDirectory($tempDirectory) | Out-Null
    }

    $tempFileName = [IO.Path]::GetRandomFileName()
    $tempPath = Join-Path -Path $tempDirectory -ChildPath $tempFileName

    try {
        Invoke-WebRequest -Uri $fileUrl -WebSession $session -OutFile $tempPath -ErrorAction Stop

        if (-not [System.IO.Directory]::Exists($directoryPath)) {
            [System.IO.Directory]::CreateDirectory($directoryPath) | Out-Null
        }

        # Useing copy because move con´t overwrite files
        [System.IO.File]::Copy($tempPath, $localPath, $true)

        Invoke-WithRetry -ScriptBlock {
            # Convert the ISO 8601 formatted date strings to DateTime objects and set the last write time
            $lastModifiedDateTime = [datetime]::Parse($lastModifiedDate, [Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::SetLastWriteTime($localPath, $lastModifiedDateTime)
        }
    } catch {
        Write-Log "Failed to download the file or move it to the final location: $_" "Red"
    } finally {
        # Clean up the temporary directory after use
        Remove-Item -Path $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Handle URL Encodings
function Sanitize-Title {
    param (
        [Parameter(Mandatory=$true)]
        [string]$title
    )
    $invalidChars = [System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars()
    $sanitizedTitle = $title
    foreach ($char in $invalidChars) {
        $sanitizedTitle = $sanitizedTitle.Replace([string]$char, '')
    }
    return $sanitizedTitle
}

# Process the tree of folder (Calls itself Recersive, no emergeny brakes) - If something goes wrong, powershell better has a stackpointer overflow lol
function Process-Entries {
    param (
        [string]$uuid,
        [string]$parentPath = ".",  # Default Path
        [switch]$isCommunity = $false # Parameter if the uuid is a community or folder id
    )

    # Switch API Endpoint based on function parameter
    if ($isCommunity) {
        Write-Log "Making a Community Request for $parentPath" "Gray"
        $url = "$baseUri/communitycollection/$uuid/feed?pageSize=500&acls=true&collectionAcls=true&category=collection&type=all&sK=updated&sO=desc"
    } else {
        $url = "$baseUri/collection/$uuid/feed?page=1&pageSize=500&sK=modified&sO=dsc&sC=all&acls=true&collectionAcls=true&includePolicy=true&category=all&includeAncestors=true"
    }

    try {
        $ErrorActionPreference = 'Stop'
        $response = Invoke-WebRequest -Uri $url -WebSession $session
        $xml = [xml]$response.Content
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
        $ErrorActionPreference = 'SilentlyContinue'

        # Handle HTTP Status Code
        switch ($statusCode) {
            'Unauthorized' { Write-Log "Error (401): Cookie Monster dosn´t like old cookies :(" "Red" }
            'InternalServerError' { Write-Log "Error (500): The server encountered an internal error." "Red" }
            Default { Write-Log "Error: An unexpected error occurred. Status code: $statusCode" "Red" }
        }
    }

    # Set fucking Atom namespace
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("td", "urn:ibm.com/td")
    $ns.AddNamespace("atom", "http://www.w3.org/2005/Atom")

    # Loop over all items within a uuid
    foreach ($entry in $xml.SelectNodes("//atom:feed/atom:entry", $ns)) {
        Start-Sleep -Milliseconds $waitInLoop
        $title = $entry.SelectSingleNode("atom:title", $ns).'#text'
        $safeTitle = Sanitize-Title -title $title
        $entryPath = Join-Path $parentPath $safeTitle
        $category = $entry.SelectSingleNode("atom:category/@term", $ns).Value

        # Write-Host $entry.OuterXml

        switch ($category) {
            "document" {
                $downloadLink = $entry.SelectSingleNode("atom:link[4]/@href", $ns).Value
                $lastModifiedDate = $entry.SelectSingleNode("td:modified", $ns).'#text'

                Write-Log "Downloading file: $title to $entryPath modifyed at $lastModifiedDate" "Green"
                Download-File -fileUrl $downloadLink -localPath $entryPath -lastModifiedDate $lastModifiedDate
            }
            "collection" {
                $newUuidRaw = $entry.SelectSingleNode("atom:id", $ns).'#text'
                $newUuid = $newUuidRaw -split ":" | Select-Object -Last 1
                if (-Not (Test-Path $entryPath)) {
                    # Get modify date of the folder
                    $lastModifiedDate = $entry.SelectSingleNode("td:modified", $ns).'#text'
                    $lastModifiedDateTime = [datetime]::Parse($lastModifiedDate, [Globalization.CultureInfo]::InvariantCulture)
                    # Try to create the Folder
                    try {
                        [System.IO.Directory]::CreateDirectory($entryPath) | Out-Null
                    } catch {
                        Write-Error "Failed to create directory at path: $entryPath. Error: $_"
                    }
                    Set-ItemProperty -Path $entryPath -Name LastWriteTime -Value $lastModifiedDateTime # Set last modify date for the folder
                }
                Write-Log "Processing folder: $title with UUID $newUuid at $entryPath" "Gray"
                Process-Entries -uuid $newUuid -parentPath $entryPath
            }
            default {
                Write-Log "Unknown category $category for $title" "Red"
            }
        }
    }

    # Loop over all items within a uuid (again) to set all modify dates for the folder
    foreach ($entry in $xml.SelectNodes("//atom:feed/atom:entry", $ns)) {
        Start-Sleep -Milliseconds $waitInLoop
        $title = $entry.SelectSingleNode("atom:title", $ns).'#text'
        $safeTitle = Sanitize-Title -title $title
        $entryPath = Join-Path $parentPath $safeTitle
        $category = $entry.SelectSingleNode("atom:category/@term", $ns).Value

        switch ($category) {
            "document" {
                # Nothing to do here since we already applyed the modify date after downloading
            }
            "collection" {
                $newUuidRaw = $entry.SelectSingleNode("atom:id", $ns).'#text'
                $newUuid = $newUuidRaw -split ":" | Select-Object -Last 1
                $lastModifiedDate = $entry.SelectSingleNode("td:modified", $ns).'#text'
                $lastModifiedDateTime = [datetime]::Parse($lastModifiedDate, [Globalization.CultureInfo]::InvariantCulture)
                Set-ItemProperty -Path $entryPath -Name LastWriteTime -Value $lastModifiedDateTime # Set last modify date for the folder
                Write-Log "Applying modify date to folder: $title with UUID $newUuid at $entryPath" "Gray"
            }
            default {
                Write-Log "Unknown category $category for $title" "Red"
            }
        }
    }
}

# Download all Files and then dedupe them based on the already downloaded folders
function Process-Files {
    param (
        [string]$uuid,
        [string]$parentPath = "."  # Default Path
    )

    $fileUrl = "$baseUri/communitycollection/$uuid/media/files.zip"

    if (!(Test-Path -LiteralPath $parentPath)) {
        New-Item -ItemType Directory -Path $parentPath > $null
    }

    Write-Log "Downloading and unzipping all files for Community $parentPath with UUID $uuid (This may take a while)" "Yellow"
    $communityFilePath = Join-Path $parentPath "$uuid-files.zip"
    Invoke-WebRequest -Uri $fileUrl -WebSession $session -OutFile $communityFilePath

    $communityFilePathUnZip = Join-Path $parentPath "$uuid-files"
    # Using 7-Zip to extract files; ensure $sevenZipPath is correctly specified
    & $sevenZipPath x "$communityFilePath" -o"$communityFilePathUnZip" -aoa -sccUTF-8 2>$errorLog | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Error "An error occurred during extraction with 7-zip. $errorLog."
        exit $LASTEXITCODE
    }

    Remove-Item -LiteralPath $communityFilePath # Delete ZIP File from local FS

    if (!(Test-Path -LiteralPath $communityFilePathUnZip)) {
        Write-Log "Community $parentPath with UUID $uuid may not contain files, as the ZIP Archive resulted in 0 Files" "Red"
        return
    }

    $rootFolder = $parentPath
    $allFilesFolderName = "$uuid-files"

    $directories = Get-ChildItem -LiteralPath $rootFolder -Directory | Where-Object Name -ne $allFilesFolderName

    $filesInDirectories = @()

    foreach ($dir in $directories) {
        $filesInDirectories += Get-ChildItem -LiteralPath $dir.FullName -File -Recurse | Where-Object DirectoryName -notlike "*\$allFilesFolderName*" | ForEach-Object { $_.Name }
    }

    $filesInDirectories = $filesInDirectories | Select-Object -Unique

    $allFilesFolderPath = Join-Path -Path $rootFolder -ChildPath $allFilesFolderName

    $allFiles = Get-ChildItem -LiteralPath $allFilesFolderPath -File

    foreach ($file in $allFiles) {
        if ($filesInDirectories -contains $file.Name) {
            Write-Log "Deleting file: $($file.FullName)" "Magenta"
            Remove-Item -LiteralPath $file.FullName
        }
    }

}


# Collect all communitys for "my" or "owned" with UUIDs and Names
function Process-Communitys {
    param (
        [Parameter(Mandatory=$true)]
        [string[]]$filteredCommunityValue,
        [switch]$genCommunity = $false
    )
    $url = "$baseServer/communities/service/atom/forms/catalog/$($communityRoute)?results=500&start=0&sortKey=update_date&sortOrder=desc&facet=%7B%22id%22%3A%22tag%22%2C%22count%22%3A%2030%7D&format=XML&dojo.preventCache=$preventCache"
    $ErrorActionPreference = 'Stop'

    try {

        $response = Invoke-WebRequest -Uri $url -WebSession $session
        if ($response.Headers.'Content-Type' -match 'text/html') {
            # Check if the HTML content includes the specific error message.
            if ($response.Content -match "We\'ve encountered a problem") {
                Write-Log "Error: The API returned an HTML page indicating a problem was encountered." "Red"
                Write-Log "This most likly means your token isn´t correct (Make sure its still valid)." "Red"
                exit
            } else {
                Write-Log "Error: The API returned an HTML page indicating a problem was encountered." "Red"
                write-Output $response.Content
                exit
            }
        }
        $xml = [xml]$response.Content
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
        $ErrorActionPreference = 'SilentlyContinue'

        # Handle HTTP Status Code
        switch ($statusCode) {
            'Unauthorized' { Write-Log "Error (401): Cookie Monster dosn´t like old cookies :(" "Red" }
            'InternalServerError' { Write-Log "Error (500): The server encountered an internal error." "Red" }
            Default { Write-Log "Error: An unexpected error occurred. Status code: $statusCode" "Red" }
        }
    }

    # Set Atom namespace
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("td", "urn:ibm.com/td")
    $ns.AddNamespace("atom", "http://www.w3.org/2005/Atom")

    # A list to store communitys, used for generating community file
    $titlesList = New-Object System.Collections.Generic.List[System.String]

    # Loop over all items within a uuid to check for special cases
    foreach ($entry in $xml.SelectNodes("//atom:feed/atom:entry", $ns)) {
        $id = $entry.SelectSingleNode("atom:id", $ns).'#text'
        $titleNode = $entry.SelectSingleNode("atom:title", $ns)
        $title = $null # Define empty var
        if ($titleNode) {
            $title = $titleNode.get_InnerXml()
            $title = $title -replace '<atom:title>|</atom:title>', ''
        }
        $title = [regex]::Replace($title, '<!\[CDATA\[(.*?)\]\]>', '$1') # Clean up the title

        # Check if we should generate the file and add titles
        if($genCommunity) {
            $titlesList.Add($title)
        }

        foreach ($pattern in $specialCasePatterns) {
            if ($title.Contains($pattern)) {
                Special-Case-Function $title
            }
        }
    }
    
    if($genCommunity) {
        # Write the list of titles to the file
        $titlesList | Out-File -FilePath $communityFile
        exit
    }

    # Loop over all items within a uuid
    foreach ($entry in $xml.SelectNodes("//atom:feed/atom:entry", $ns)) {
        $id = $entry.SelectSingleNode("atom:id", $ns).'#text'
        $titleNode = $entry.SelectSingleNode("atom:title", $ns)
        $title = $null # Define empty var
        if ($titleNode) {
            $title = $titleNode.get_InnerXml()
            $title = $title -replace '<atom:title>|</atom:title>', ''
        }
        $title = [regex]::Replace($title, '<!\[CDATA\[(.*?)\]\]>', '$1') # Clean up the title

        if ("ALL" -in $filteredCommunityValue -or $title -in $filteredCommunityValue) {
            Process-Entries -uuid $id -parentPath $title -isCommunity $true
            Process-Files -uuid $id -parentPath $title
        } else {
            Write-Log "Skipping $title with UUID $id because it's not in communitys.txt" "Yellow"
        }
    }
}

# Check if the CommunityFile exists and if not then generate a new one
try {
    $communityValue = Get-Content $communityFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Error "A Community Config File was created, please add a NOT Operator (!) infront of all Communitys you want to exclude"
    Process-Communitys -genCommunity $true
}

# Start Program
Clear-Host
Write-Host ""
Write-Host "########################"
Write-Host "# HCL Community Cloner #"
Write-Host "# By BolverBlitz(Marc) #"
Write-Host "#    Version $sVersion     #"
Write-Host "########################"
Write-Host ""
Write-Host "Give it a Star: https://github.com/BolverBlitz/HCL-Communities-Cloner"
Write-Host ""
Check-ScriptVersion
Write-Log "Starting program with a internal delay of $waitInLoop ms"
if ($communityRoute -eq "allmy") { $communityOf = "Checking all communitys you are a member of." }
if ($communityRoute -eq "owned") { $communityOf = "Checking only communitys you are a owner of." }
Write-Log $communityOf # Log one of the Lines above

$filteredCommunityValue = $communityValue | Where-Object {$_ -notmatch '^!'} # Filter all excluded Communits (! at the start is excluding)

if("ALL" -in $filteredCommunityValue) {
    $promtMessage = "$($communityOf)`nDo you want to proceed cloning all of those communitys?`n"
} else {
    $promtMessage = "$($communityOf)`nDo you want to proceed cloning the following $($filteredCommunityValue.Count) communitys?`n"
    foreach ($community in $filteredCommunityValue) {
        $promtMessage = "$($promtMessage)- $community`n"
    }
}
Write-Host ""

Add-Type -AssemblyName System.Windows.Forms
$result = [System.Windows.Forms.MessageBox]::Show("$promtMessage", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo)
if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    Process-Communitys -filteredCommunityValue $filteredCommunityValue
} else {
    Write-Host "Exiting..."
    exit
}
