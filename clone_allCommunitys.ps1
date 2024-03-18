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
    [string]$communityRoute = "my",
    [int]$waitInLoop = 0
)

# Path to 7-Zip Executable (Needed for deflation, because otherwise UTF8 Chars will be broken)
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe"

if (!(Test-Path $sevenZipPath)) {
  Write-Error "7-Zip.exe not found!!"
  exit
}

# Base URL of the API (Edit Stuff here)
$cookieDomain = "" # Update this to the domain of your API
$baseServer = ""
$baseUri = "$baseServer/files/form/api"

$cookieFile = "./ltpaToken.txt"
$communityFile = "./communitys.txt"

if ($communityRoute -notin @("my", "owned")) {
    # Check if only a valid parameter was passed
    throw "Invalid value: $communityRoute. The variable must be either 'my' or 'owned'."
}

try {
    $cookieValue = Get-Content $cookieFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Host "Need help? Edit this file and look at info i left here"
    Write-Error "Cookie Monster wants COOKIES!!! (Get your LtpaToken2 Token and put it into a file named ltpaToken.txt) - I promise, its fine"
    exit
}

try {
    $communityValue = Get-Content $communityFile -Encoding UTF8 -ErrorAction Stop
} catch {
    Write-Error "Please create a file called communitys.txt that contains all community names that should be cloned"
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
    # Do something in those cases. $title refers to the full community name.
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
        [string]$LogFilePath = "./log.txt" # Default log path
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$($timestamp): $Message"
    Write-Host $logEntry -ForegroundColor $txtColor

    Invoke-WithRetry -ScriptBlock {
        $logEntry | Out-File -FilePath $LogFilePath -Append -Encoding UTF8 -ErrorAction Stop
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
    Invoke-WebRequest -Uri $fileUrl -WebSession $session -OutFile $localPath

    # Convert the ISO 8601 formatted date strings to DateTime objects
    $lastModifiedDateTime = [datetime]::Parse($lastModifiedDate, [Globalization.CultureInfo]::InvariantCulture)

    # Set the creation and last modified times of the downloaded file
    Invoke-WithRetry -ScriptBlock {
        Set-ItemProperty -Path $localPath -Name LastWriteTime -Value $lastModifiedDateTime -ErrorAction Stop
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
                    New-Item -ItemType Directory -Path $entryPath > $null # Create folder
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

    if (!(Test-Path -Path $title)) {
        New-Item -ItemType Directory -Path $parentPath > $null
    }

    Write-Log "Downloading and unziping all files for Community $parentPath with UUID $uuid (This may take a while)" "Yellow"
    $communityFilePath = Join-Path $parentPath "$uuid-files.zip"
    Invoke-WebRequest -Uri $fileUrl -WebSession $session -OutFile $communityFilePath

    $communityFilePathUnZip = Join-Path $parentPath "$uuid-files"
    # Gonna retry because on remote filesystems (SMB Share) it might fail with higher latancy
    & $sevenZipPath x "$communityFilePath" -o"$communityFilePathUnZip" -aoa -sccUTF-8 2>$errorLog | Out-Null

    # Check for errors from 7-zip (Stuscode)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "An error occurred during extraction of 7-zip. $errorLog."
        exit $LASTEXITCODE
    }

    Remove-Item $communityFilePath # Delete ZIP File from local FS

    # Check if ZIP file generated a output folder, it won´t do that when there where no Files in the community
    if (!(Test-Path $communityFilePathUnZip)) {
        Write-Log "Community $parentPath with UUID $uuid may not contain files, as the ZIP Archive resulted in 0 Files" "Red"
        return
    }

    $rootFolder = $parentPath
    $allFilesFolderName = "$uuid-files" # Only the name of the folder, not the full path

    # Get all directories in the root folder except the "all files" folder
    $directories = Get-ChildItem -Path $rootFolder -Directory | Where-Object Name -ne $allFilesFolderName

    $filesInDirectories = @() # Get Folder List

    # Iterate over each directory and subdirectory to populate list
    foreach ($dir in $directories) {
        $filesInDirectories += Get-ChildItem -Path $dir.FullName -File -Recurse | Where-Object DirectoryName -notlike "*\$allFilesFolderName*" | ForEach-Object { $_.Name }
    }

    # Remove duplicate file names
    $filesInDirectories = $filesInDirectories | Select-Object -Unique

    # Define the full path to the "all files" folder
    $allFilesFolderPath = Join-Path -Path $rootFolder -ChildPath $allFilesFolderName

    # Get all files from the "all files" folder
    $allFiles = Get-ChildItem -Path $allFilesFolderPath -File

    # Iterate over each file in the "all files" folder
    foreach ($file in $allFiles) {
        # If the file name is in the list of files in the directories, delete it
        if ($filesInDirectories -contains $file.Name) {
            Write-Log "Deleting file: $($file.FullName)" "Magenta"
            Remove-Item -Path $file.FullName
        }
}

}

# Collect all communitys for "my" or "owned" with UUIDs and Names
function Process-Communitys {
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

        foreach ($pattern in $specialCasePatterns) {
            if ($title.Contains($pattern)) {
                Special-Case-Function $title
            }
        }
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

        if ("ALL" -in $communityValue -or $title -in $communityValue) {
            Process-Entries -uuid $id -parentPath $title -isCommunity $true
            Process-Files -uuid $id -parentPath $title
        } else {
            Write-Log "Skipping $title with UUID $id because it's not in communitys.txt" "Yellow"
        }
    }
}

# Start Program
Clear-Host
Write-Host ""
Write-Host "########################"
Write-Host "# HCL Community Cloner #"
Write-Host "# By BolverBlitz(Marc) #"
Write-Host "#    Version 3.0.0     #"
Write-Host "########################"
Write-Host ""
Write-Host "Give it a Star: https://github.com/BolverBlitz/HCL-Communities-Cloner"
Write-Host ""
Write-Log "Starting program with a internal delay of $waitInLoop ms"
if ($communityRoute -eq "my") { $communityOf = "Checking all communitys you are a member of." }
if ($communityRoute -eq "owned") { $communityOf = "Checking only communitys you are a owner of." }
Write-Log $communityOf # Log one of the Lines above
if("ALL" -in $communityValue) {
    $promtMessage = "$($communityOf)`nDo you want to proceed cloning all of those communitys?`n"
} else {
    $promtMessage = "$($communityOf)`nDo you want to proceed cloning the following $($communityValue.Count) communitys?`n"
    foreach ($community in $communityValue) {
        $promtMessage = "$($promtMessage)- $community`n"
    }
}
Write-Host ""

Add-Type -AssemblyName System.Windows.Forms
$result = [System.Windows.Forms.MessageBox]::Show("$promtMessage", "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo)
if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
    Process-Communitys
} else {
    Write-Host "Exiting..."
    exit
}
