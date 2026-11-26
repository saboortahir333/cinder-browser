param([switch]$Elevated, [string]$Package = 'CinderBrowser.msix')

# Trusts Cinder's self-signed package certificate on THIS PC, then installs the MSIX.
# Keep CinderBrowser.msix and CinderBrowser.cer in the same folder as this script.
$ErrorActionPreference = 'Stop'
$script = $PSCommandPath
$here = Split-Path -Parent $script

function Pause-Exit($msg, $code) {
  Write-Host ''
  Write-Host $msg
  Read-Host 'Press Enter to close' | Out-Null
  exit $code
}

try {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

  if (-not $isAdmin) {
    if ($Elevated) {
      Pause-Exit 'Still not running as administrator, so nothing was changed. Open PowerShell as administrator and run this script from there.' 1
    }
    # One relaunch only (-Elevated stops any restart loop).
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Elevated', '-Package', "`"$Package`"")
    exit
  }

  $cert = Join-Path $here 'CinderBrowser.cer'
  $msix = Join-Path $here $Package
  foreach ($f in @($cert, $msix)) {
    if (-not (Test-Path -LiteralPath $f)) { Pause-Exit "Missing file: $f" 1 }
  }

  Write-Host 'Trusting the Cinder package certificate (Trusted People store only)...'
  Import-Certificate -FilePath $cert -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null

  Write-Host 'Installing Cinder Browser...'
  Add-AppxPackage -Path $msix

  Pause-Exit 'Done: Cinder Browser is installed. Find it in the Start menu.' 0
}
catch {
  Pause-Exit ("Failed: " + $_.Exception.Message) 1
}

