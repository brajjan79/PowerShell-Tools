[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [ValidateSet('Machine', 'User')]
    [string]$Scope = 'Machine',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$mavenBaseUrl = 'https://downloads.apache.org/maven/maven-3'

function Get-MavenVersions {
    $page = Invoke-WebRequest -Uri "$mavenBaseUrl/" -UseBasicParsing
    $versions = @($page.Links | ForEach-Object {
        if ($_.href -match '^\d+\.\d+\.\d+/$') { $_.href.TrimEnd('/') }
    } | Sort-Object -Property { [version]$_ } -Descending -Unique)
    if ($versions.Count -eq 0) { throw 'Apache returned no available Maven versions.' }
    return $versions
}

function Prompt-MavenVersion {
    param ([string[]]$Versions)
    if ($Versions.Count -eq 0) { throw 'No Maven versions are available.' }
    Write-Host "Available Maven versions: $($Versions -join ', ')"
    $selected = (Read-Host "Enter Maven version to install (default: $($Versions[0]))").Trim()
    if (-not $selected) { $selected = $Versions[0] }
    if ($Versions -notcontains $selected) { throw "Maven version '$selected' is not in the available list." }
    return $selected
}

function Assert-MavenDirectory {
    param ([string]$Path, [string]$Root)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Path]::IsPathRooted($Root)) {
        throw 'Maven deletion requires absolute paths.'
    }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ([IO.Path]::GetDirectoryName($fullPath) -ne $fullRoot -or
        [IO.Path]::GetFileName($fullPath) -notmatch '^apache-maven-\d+\.\d+\.\d+$') {
        throw "Refusing to remove a directory outside the Maven installation root: $Path"
    }
    # Reject junctions/symlinks in the target and all its ancestors.
    $item = Get-Item -LiteralPath $fullPath -Force
    if (-not $item.PSIsContainer) { throw "Not a directory: $fullPath" }
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Refusing to operate through a junction or symbolic link: $($item.FullName)"
        }
        $item = $item.Parent
    }
    $links = @(Get-ChildItem -LiteralPath $fullPath -Recurse -Force |
        Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    if ($links.Count -gt 0) { throw "Refusing to remove Maven directory containing links: $fullPath" }
    return $fullPath
}

function Get-UpdatedPath {
    param ([string]$CurrentPath, [string]$InstallRoot, [string]$MavenBin)
    $entries = @($CurrentPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $result = @()
    foreach ($entry in $entries) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim('"')).TrimEnd('\')
        $oldMaven = $expanded -match ('^' + [regex]::Escape($InstallRoot.TrimEnd('\')) + '\\apache-maven-\d+\.\d+\.\d+\\bin$')
        if ($oldMaven -or $entry -match '^%MAVEN_HOME%[\\/]bin[\\/]?$') { continue }
        if ($result -notcontains $entry) { $result += $entry }
    }
    if ($result -notcontains $MavenBin) { $result += $MavenBin }
    return $result -join ';'
}

function Get-ExistingMavenVersion {
    param ([string]$Version)
    $commands = @(Get-Command mvn.cmd -CommandType Application -All -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Source })
    foreach ($environmentTarget in @('Process', 'User', 'Machine')) {
        $existingHome = [Environment]::GetEnvironmentVariable('MAVEN_HOME', $environmentTarget)
        if ($existingHome) {
            $candidate = Join-Path $existingHome 'bin\mvn.cmd'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { $commands += $candidate }
        }
    }
    foreach ($command in @($commands | Select-Object -Unique)) {
        # An unusable older installation must not prevent a fresh installation.
        try {
            $output = @(& $command --version 2>&1)
            $exitCode = $LASTEXITCODE
        }
        catch {
            Write-Warning "Could not inspect existing Maven at ${command}: $($_.Exception.Message)"
            continue
        }
        if ($exitCode -eq 0 -and ($output -join "`n") -match ('(?m)^Apache Maven ' + [regex]::Escape($Version) + '(\s|$)')) {
            return $command
        }
    }
}

function Test-Maven {
    param ([string]$Command, [string]$Version)
    $output = @(& $Command --version 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch ('Apache Maven ' + [regex]::Escape($Version) + '(\s|$)')) {
        throw "Maven verification failed: $($output -join "`n")"
    }
    $output | ForEach-Object { Write-Host $_ }
}

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if ($Scope -eq 'Machine' -and -not $WhatIfPreference -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Machine installation requires an administrator. Run elevated or use -Scope User.'
    }
    $installRoot = if ($Scope -eq 'Machine') { $env:ProgramFiles } else { Join-Path $env:LOCALAPPDATA 'Programs' }
    $installRoot = [IO.Path]::GetFullPath($installRoot)
    $downloadPath = Join-Path $env:USERPROFILE 'Downloads'
    $target = [EnvironmentVariableTarget]::$Scope

    $javaCommand = if ($env:JAVA_HOME) {
        Join-Path $env:JAVA_HOME 'bin\java.exe'
    } else {
        (Get-Command java.exe -ErrorAction Stop).Source
    }
    if (-not (Test-Path -LiteralPath $javaCommand -PathType Leaf)) { throw 'Java was not found. Check JAVA_HOME or PATH.' }
    & $javaCommand -version
    if ($LASTEXITCODE -ne 0) { throw 'Java verification failed.' }

    $versions = @(Get-MavenVersions)
    $version = Prompt-MavenVersion -Versions $versions
    $destination = Join-Path $installRoot "apache-maven-$version"
    $existingInstallation = if (Test-Path -LiteralPath $destination) {
        $destination
    } else {
        Get-ExistingMavenVersion -Version $version
    }
    if ($existingInstallation -and -not $Force) {
        Write-Host "Maven $version is already installed: $existingInstallation"
        Write-Host 'No installation changes were made. Run again with -Force to reinstall (add -WhatIf to preview).'
        return
    }
    if (Test-Path -LiteralPath $destination) {
        [void](Assert-MavenDirectory -Path $destination -Root $installRoot)
    }
    $mavenBin = Join-Path $destination 'bin'
    $savedPath = [Environment]::GetEnvironmentVariable('Path', $target)
    $newPath = Get-UpdatedPath -CurrentPath $savedPath -InstallRoot $installRoot -MavenBin $mavenBin
    $sessionPath = Get-UpdatedPath -CurrentPath $env:Path -InstallRoot $installRoot -MavenBin $mavenBin
    $oldDirectories = @()
    if (Test-Path -LiteralPath $installRoot -PathType Container) {
        $oldDirectories = @(Get-ChildItem -LiteralPath $installRoot -Directory -Filter 'apache-maven-*' |
            Where-Object { $_.FullName -ne $destination -and $_.Name -match '^apache-maven-\d+\.\d+\.\d+$' })
    }
    $safePaths = @($oldDirectories | ForEach-Object { Assert-MavenDirectory -Path $_.FullName -Root $installRoot })
    if ($WhatIfPreference) {
        Write-Host "Selected Maven version: $version"
        Write-Host "Download directory: $downloadPath"
        Write-Host "$Scope MAVEN_HOME: $destination"
        Write-Host "$Scope PATH: $newPath"
        Write-Host "Session PATH: $sessionPath"
        Write-Host "Old installations to remove after verification: $($safePaths -join ', ')"
    }
    # Treat installation and cleanup as one operation: a declined confirmation
    # must never allow cleanup to run without a verified new installation.
    $action = "Download Maven $version to $downloadPath, verify SHA-512, install and verify Maven (overwrite existing files if -Force), update $Scope and session environment variables, then remove verified old Maven directories"
    if (-not $PSCmdlet.ShouldProcess($destination, $action)) {
        Write-Host 'No installation changes were made.'
        return
    }
    New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    $zip = Join-Path $downloadPath "apache-maven-$version-bin.zip"
    $url = "$mavenBaseUrl/$version/binaries/apache-maven-$version-bin.zip"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    $checksum = (Invoke-WebRequest -Uri "$url.sha512" -UseBasicParsing).Content
    if ($checksum -notmatch '(?i)^\s*([a-f0-9]{128})(?:\s|$)') { throw 'Invalid Apache SHA-512 checksum.' }
    $expected = $Matches[1]
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA512).Hash -ne $expected) { throw 'ZIP SHA-512 checksum does not match Apache. Installation aborted.' }
    if ($Force -and (Test-Path -LiteralPath $destination)) {
        # Verify a separate copy before overwriting an existing installation.
        $stagingRoot = Join-Path $downloadPath ('maven-staging-' + [guid]::NewGuid().ToString('N'))
        Expand-Archive -LiteralPath $zip -DestinationPath $stagingRoot
        Test-Maven -Command (Join-Path $stagingRoot "apache-maven-$version\bin\mvn.cmd") -Version $version
        [void](Assert-MavenDirectory -Path $destination -Root $installRoot)
        Expand-Archive -LiteralPath $zip -DestinationPath $installRoot -Force
        Write-Host "Verified staging copy retained at $stagingRoot"
    } else {
        Expand-Archive -LiteralPath $zip -DestinationPath $installRoot
    }
    Test-Maven -Command (Join-Path $destination 'bin\mvn.cmd') -Version $version

    [Environment]::SetEnvironmentVariable('MAVEN_HOME', $destination, $target)
    [Environment]::SetEnvironmentVariable('Path', $newPath, $target)
    $env:MAVEN_HOME = $destination
    $env:Path = $sessionPath
    Test-Maven -Command 'mvn.cmd' -Version $version

    # Revalidate every candidate immediately before starting recursive deletion.
    $safePaths = @($oldDirectories | ForEach-Object { Assert-MavenDirectory -Path $_.FullName -Root $installRoot })
    foreach ($safePath in $safePaths) { Remove-Item -LiteralPath $safePath -Recurse -Force }
    Write-Host "Maven $version installation and setup completed successfully."
}
catch {
    Write-Error "Maven installation failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
