<#
.SYNOPSIS
  Builds Cinder, code-signs it, and produces a signed CinderBrowser_Setup.exe
  in the project root.

.DESCRIPTION
  Pick ONE signing method (or none, which produces an UNSIGNED installer that
  Smart App Control will block):

  A) Certificate file (OV/EV code-signing cert exported as .pfx)
       $env:CINDER_PFX_PASSWORD = '...'
       .\tools\build_release.ps1 -Pfx C:\keys\cinder.pfx

  B) Microsoft Trusted Signing ("Artifact Signing")
       az login          # or set AZURE_* service-principal variables
       .\tools\build_release.ps1 -TrustedSigning `
           -TsEndpoint https://eus.codesigning.azure.net `
           -TsAccount  <account name> -TsProfile <certificate profile name>

  The password / credentials are never written to disk by this script.
#>
[CmdletBinding()]
param(
  [string]$Pfx,
  [switch]$TrustedSigning,
  [string]$TsEndpoint,
  [string]$TsAccount,
  [string]$TsProfile,
  [string]$TimestampUrl,
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$release = 'build\windows\x64\runner\Release'
$iscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
if (-not (Test-Path $iscc)) { $iscc = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' }
if (-not (Test-Path $iscc)) { throw 'Inno Setup 6 not found (install from jrsoftware.org).' }

$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\signtool.exe' -ErrorAction SilentlyContinue |
  Sort-Object FullName | Select-Object -Last 1 -ExpandProperty FullName
$signing = $Pfx -or $TrustedSigning
if ($signing -and -not $signtool) { throw 'signtool.exe not found (install the Windows 10/11 SDK).' }

# ---- build the sign command (used for both our files and Inno) ----------------
$signCmd = $null
if ($Pfx) {
  if (-not (Test-Path $Pfx)) { throw "PFX not found: $Pfx" }
  if (-not $env:CINDER_PFX_PASSWORD) { throw 'Set $env:CINDER_PFX_PASSWORD first.' }
  if (-not $TimestampUrl) { $TimestampUrl = 'http://timestamp.digicert.com' }
  # The password is passed via the environment (%VAR% expands in cmd), never
  # written to disk. QQ stands for a double quote (see Quote helpers below).
  $signCmd = "QQ${signtool}QQ sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f QQ$((Resolve-Path $Pfx).Path)QQ /p %CINDER_PFX_PASSWORD%"
}
elseif ($TrustedSigning) {
  if (-not ($TsEndpoint -and $TsAccount -and $TsProfile)) { throw 'Trusted Signing needs -TsEndpoint -TsAccount -TsProfile.' }
  if (-not $TimestampUrl) { $TimestampUrl = 'http://timestamp.acs.microsoft.com' }
  # Fetch Microsoft's signing dlib (NuGet package) into a cache folder.
  $cache = Join-Path $env:LOCALAPPDATA 'Cinder\signing-cache'
  $dlib = Join-Path $cache 'bin\x64\Azure.CodeSigning.Dlib.dll'
  if (-not (Test-Path $dlib)) {
    New-Item -ItemType Directory -Force $cache | Out-Null
    $nupkg = Join-Path $cache 'tsc.zip'
    Invoke-WebRequest 'https://www.nuget.org/api/v2/package/Microsoft.Trusted.Signing.Client' -OutFile $nupkg
    Expand-Archive $nupkg -DestinationPath $cache -Force
    $found = Get-ChildItem $cache -Recurse -Filter Azure.CodeSigning.Dlib.dll | Where-Object FullName -match 'x64' | Select-Object -First 1
    if (-not $found) { throw 'Azure.CodeSigning.Dlib.dll not found in package.' }
    $dlib = $found.FullName
  }
  $meta = Join-Path $cache 'metadata.json'
  @{ Endpoint = $TsEndpoint; CodeSigningAccountName = $TsAccount; CertificateProfileName = $TsProfile } |
    ConvertTo-Json | Set-Content $meta -Encoding utf8
  $signCmd = "QQ${signtool}QQ sign /v /fd SHA256 /tr $TimestampUrl /td SHA256 /dlib QQ${dlib}QQ /dmdf QQ${meta}QQ"
}
else {
  Write-Warning 'No signing method given: the installer will be UNSIGNED and Smart App Control will block it.'
}

function Invoke-Sign([string[]]$Files) {
  if (-not $signCmd) { return }
  foreach ($f in $Files) {
    $s = Get-AuthenticodeSignature $f
    if ($s.Status -eq 'Valid') { continue }  # already signed (e.g. Microsoft/Flutter DLLs)
    $line = ($signCmd -replace 'QQ', '"') + " `"$f`""
    cmd /c "$line" | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $f" }
  }
}

# ---- 1. build ---------------------------------------------------------------
if (-not $SkipBuild) {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

# ---- 2. sign the app's own binaries ----------------------------------------
$own = Get-ChildItem $release -File | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object FullName
Invoke-Sign $own

# ---- 3. installer (Inno signs Setup.exe and the uninstaller itself) ---------
$args = @('installer.iss')
if ($signing) {
  # Inno writes a double quote as $q inside a /S command.
  # Inno starts the command directly (no %VAR% expansion), so route it through
  # a throw-away wrapper batch file that reads the password from the environment.
  $wrapper = Join-Path $env:TEMP ("cinder_sign_{0}.cmd" -f ([guid]::NewGuid().ToString('N')))
  "@echo off`r`n" + ($signCmd -replace 'QQ', '"') + " %1`r`n" | Set-Content $wrapper -Encoding ascii
  $innoCmd = "`$q$wrapper`$q `$f"
  $args = @("/Scinder=$innoCmd", '/DSIGN=1') + $args
}
try { & $iscc @args } finally { if ($wrapper) { Remove-Item $wrapper -ErrorAction SilentlyContinue } }
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }

# ---- 4. report --------------------------------------------------------------
foreach ($f in @('CinderBrowser_Setup.exe', "$release\saboor_browser.exe")) {
  $s = Get-AuthenticodeSignature $f
  '{0,-60} {1}  {2}' -f $f, $s.Status, ($s.SignerCertificate.Subject -split ',')[0]
}
if (-not $signing) { Write-Warning 'UNSIGNED build.' }
