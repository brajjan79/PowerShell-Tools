# Define variables
$mavenBaseUrl = "https://downloads.apache.org/maven/maven-3/"
$downloadPath = "$env:USERPROFILE\Downloads"
$installPath = "C:\Program Files"

# Function to get the latest Maven versions
function Get-MavenVersions {
    Write-Host "Fetching Maven versions..."
    $htmlContent = Invoke-WebRequest -Uri $mavenBaseUrl
    $versions = ($htmlContent.Links | Where-Object { $_.href -match '^[\d]+\.[\d]+\.[\d]+/$' }).href -replace '/$'
    $versions = $versions | Sort-Object -Descending
    return $versions
}

# Function to prompt user for Maven version
function Prompt-MavenVersion {
    param (
        [string[]]$versions
    )
    $latestVersion = $versions[0]
    Write-Host "Available Maven versions: $(($versions -join ', '))"
    $selectedVersion = Read-Host "Enter Maven version to install (default: $latestVersion)" 
    if (-not $selectedVersion) {
        $selectedVersion = $latestVersion
    }
    return $selectedVersion
}

# Function to remove old Maven installations
function Remove-OldMaven {
    param (
        [string]$installPath
    )
    Write-Host "Removing old Maven installations..."
    Get-ChildItem -Path $installPath -Filter "apache-maven-*" | Remove-Item -Recurse -Force
    Write-Host "Old Maven installations removed."
}

# Function to download and install Maven
function Install-Maven {
    param (
        [string]$version,
        [string]$downloadPath,
        [string]$installPath
    )
    $mavenUrl = "$mavenBaseUrl/$version/binaries/apache-maven-$version-bin.zip"
    $mavenZipPath = "$downloadPath\apache-maven-$version-bin.zip"
    $mavenExtractPath = "$installPath\apache-maven-$version"

    Write-Host "Downloading Maven $version..."
    Invoke-WebRequest -Uri $mavenUrl -OutFile $mavenZipPath
    Write-Host "Downloaded Maven to $mavenZipPath"

    Write-Host "Extracting Maven..."
    Expand-Archive -Path $mavenZipPath -DestinationPath $installPath
    Write-Host "Extracted Maven to $mavenExtractPath"

    return $mavenExtractPath
}

# Function to set environment variables
function Set-EnvironmentVariables {
    param (
        [string]$mavenExtractPath
    )
    Write-Host "Setting environment variables..."

    # Set MAVEN_HOME
    [System.Environment]::SetEnvironmentVariable('MAVEN_HOME', $mavenExtractPath, [System.EnvironmentVariableTarget]::Machine)
    Write-Host "Set MAVEN_HOME to $mavenExtractPath"

    # Add Maven bin directory to PATH
    $mavenBinPath = "$mavenExtractPath\bin"
    $currentPath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine)
    if ($currentPath -notcontains $mavenBinPath) {
        [System.Environment]::SetEnvironmentVariable('Path', "$currentPath;$mavenBinPath", [System.EnvironmentVariableTarget]::Machine)
        Write-Host "Added $mavenBinPath to PATH"
    } else {
        Write-Host "$mavenBinPath is already in PATH"
    }
}

# Main script execution
$mavenVersions = Get-MavenVersions
$mavenVersion = Prompt-MavenVersion -versions $mavenVersions
Remove-OldMaven -installPath $installPath
$mavenExtractPath = Install-Maven -version $mavenVersion -downloadPath $downloadPath -installPath $installPath
Set-EnvironmentVariables -mavenExtractPath $mavenExtractPath

Write-Host "Maven installation and setup completed successfully."
