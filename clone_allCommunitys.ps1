# Author: BolverBlitz (Marc)
# This is free to use and modify. (MIT)

# How to get your token:
# Open community
# Press F12 (Don´t do that when a scamer asks you this, but i´m a nice guy - So Don´t worry about it"
# Go to "Network" tab
# Press F5
# Click on the very first thing from the list
# Click on cookies in the section that just opend by your click (Sometimes you have to douple click)
# Look for "LtpaToken2" and richtklick the value in the cell behind and click copy
# Make a file where this scrit is thats named ltpaToken.txt and palce your token there

param (
    [string]$communityRoute = "my",
    [int]$waitInLoop = 0
)

# Base URL of the API
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
$cookie.Domain = ".int.n-ergie" # Update this to the domain of your API
$session.Cookies.Add($cookie)

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
        [string]$LogFilePath = "./log.txt" # Default log path
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$($timestamp): $Message"
    Write-Host $logEntry

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
        Write-Log "Making a Community Request for $parentPath"
        $url = "$baseUri/communitycollection/$uuid/feed?pageSize=500&acls=true&collectionAcls=true&category=collection&type=all&sK=updated&sO=desc"
    } else {
        $url = "$baseUri/collection/$uuid/feed?page=1&pageSize=500&sK=modified&sO=dsc&sC=all&acls=true&collectionAcls=true&includePolicy=true&category=all&includeAncestors=true"
    }

    try {
        $ErrorActionPreference = 'Stop'
        Write-Host $url
        $response = Invoke-WebRequest -Uri $url -WebSession $session
        $xml = [xml]$response.Content
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
        $ErrorActionPreference = 'SilentlyContinue'

        # Handle HTTP Status Code
        switch ($statusCode) {
            'Unauthorized' { Write-Host "Error (401): Cookie Monster dosn´t like old cookies :(" }
            'InternalServerError' { Write-Host "Error (500): The server encountered an internal error." }
            Default { Write-Host "Error: An unexpected error occurred. Status code: $statusCode" }
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

                Write-Log "Downloading file: $title to $entryPath modifyed at $lastModifiedDate"
                Download-File -fileUrl $downloadLink -localPath $entryPath -lastModifiedDate $lastModifiedDate
            }
            "collection" {
                $newUuidRaw = $entry.SelectSingleNode("atom:id", $ns).'#text'
                $newUuid = $newUuidRaw -split ":" | Select-Object -Last 1
                if (-Not (Test-Path $entryPath)) {
                    # Get modify date of the folder
                    $lastModifiedDate = $entry.SelectSingleNode("td:modified", $ns).'#text'
                    $lastModifiedDateTime = [datetime]::Parse($lastModifiedDate, [Globalization.CultureInfo]::InvariantCulture)
                    New-Item -ItemType Directory -Path $entryPath > $null # Creat folder
                    Set-ItemProperty -Path $entryPath -Name LastWriteTime -Value $lastModifiedDateTime # Set last modify date for the folder
                }
                Write-Log "Processing folder: $title with UUID $newUuid at $entryPath"
                Process-Entries -uuid $newUuid -parentPath $entryPath
            }
            default {
                Write-Log "Unknown category $category for $title"
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
                Write-Log "Applying modify date to folder: $title with UUID $newUuid at $entryPath"
            }
            default {
                Write-Log "Unknown category $category for $title"
            }
        }
    }
}

function Process-Communitys {
    $url = "$baseServer/communities/service/atom/forms/catalog/$($communityRoute)?results=500&start=0&sortKey=update_date&sortOrder=desc&facet=%7B%22id%22%3A%22tag%22%2C%22count%22%3A%2030%7D&format=XML&dojo.preventCache=$preventCache"

    try {
        $ErrorActionPreference = 'Stop'
        Write-Host $url
        $response = Invoke-WebRequest -Uri $url -WebSession $session
        $xml = [xml]$response.Content
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        $statusCode = $response.StatusCode
        $ErrorActionPreference = 'SilentlyContinue'

        # Handle HTTP Status Code
        switch ($statusCode) {
            'Unauthorized' { Write-Host "Error (401): Cookie Monster dosn´t like old cookies :(" }
            'InternalServerError' { Write-Host "Error (500): The server encountered an internal error." }
            Default { Write-Host "Error: An unexpected error occurred. Status code: $statusCode" }
        }
    }

    # Set Atom namespace
    $ns = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace("td", "urn:ibm.com/td")
    $ns.AddNamespace("atom", "http://www.w3.org/2005/Atom")

    # Loop over all items within a uuid
    foreach ($entry in $xml.SelectNodes("//atom:feed/atom:entry", $ns)) {
        $id = $entry.SelectSingleNode("atom:id", $ns).'#text'
        $titleNode = $entry.SelectSingleNode("atom:title", $ns)
        $title = $null
        if ($titleNode) {
            $title = $titleNode.get_InnerXml()
            $title = $title -replace '<atom:title>|</atom:title>', ''
        }
        $title = [regex]::Replace($title, '<!\[CDATA\[(.*?)\]\]>', '$1') # Clean up the title

        if ("ALL" -in $communityValue -or $title -in $communityValue) {
            Process-Entries -uuid $id -parentPath $title -isCommunity $true
        } else {
            Write-Log "Skipping $title with UUID $id because it's not in communitys.txt"
        }
    }
}

# Start Program
Write-Host ""
Write-Host "########################"
Write-Host "# HCL Community Cloner #"
Write-Host "# By BolverBlitz(Marc) #"
Write-Host "#    Version 2.0.0     #"
Write-Host "########################"
Write-Host ""
Write-Host "Starting program with a internal delay of $waitInLoop ms"
if ($communityRoute -eq "my") { $communityOf = "Checking all communitys you are a member of." }
if ($communityRoute -eq "owned") { $communityOf = "Checking only communitys you are a owner of." }
Write-Log $communityOf
$promtMessage = "$($communityOf)`nDo you want to proceed cloning the following $($communityValue.Count) communitys?`n"
foreach ($community in $communityValue) {
    $promtMessage = "$($promtMessage)- $community`n"
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
