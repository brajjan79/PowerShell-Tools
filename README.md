# PowerShell Tools

## install-maven.ps1

Install Java first and ensure JAVA_HOME or PATH points to a working Java installation.

For a system installation in Program Files, run PowerShell as administrator:

```powershell
.\install-maven.ps1
```

For an installation under the current user's LocalAppData\Programs, without administrator privileges:

```powershell
.\install-maven.ps1 -Scope User
```

Preview the installation without changing files or environment variables:

```powershell
.\install-maven.ps1 -WhatIf
.\install-maven.ps1 -Scope User -WhatIf
```

The preview checks Java and fetches the available versions, then displays the selected version, download and installation paths, resulting PATH values, and old directories scheduled for removal. It does not download the archive, extract files, run the new Maven installation, or delete anything. A system preview does not require administrator privileges. Use `-Confirm` to confirm the complete installation and cleanup operation before any changes begin.

Choose an available Maven 3 version, or press Enter for the newest version. Versions are sorted numerically. The script creates the download directory, downloads the ZIP and Apache's published SHA-512 checksum, and verifies the archive before extraction.

The new installation is verified with `mvn --version` before older Maven directories in the selected installation root are removed. If the destination already exists or the selected version is detected through PATH or MAVEN_HOME (process, user, or machine), including installations in other directories, the script exits normally with instructions to use `-Force`. This check also runs with `-WhatIf`. Deletion is limited to versioned Maven directories directly under that root; symbolic links and junctions are rejected.

MAVEN_HOME and PATH are updated for the selected scope and the current PowerShell process. Old Maven PATH entries belonging to the selected installation root are removed, and duplicate entries are avoided. Other already-open terminals must be restarted to pick up the persisted environment variables. When launched as a separate process, session changes apply only to that process.

Errors stop the script with exit code 1; success is reported only after Java and the installed Maven version have been checked. Failed downloads or extraction may leave files for inspection; older installations are retained until the new version has been verified.

To proceed when the selected version is already installed:

```powershell
.\install-maven.ps1 -Force -WhatIf
.\install-maven.ps1 -Force
```

`-Force` installs into the selected scope's normal destination; it does not overwrite an installation detected in a different directory. If the destination already exists, its safety checks still apply. The script verifies a separate staging copy before overwriting files and verifies the destination again afterward. The staging copy is retained under Downloads for inspection. Force does not bypass checksum, Java, Maven, administrator, or deletion checks.
