# Downloads Microsoft's redistributables bundled into the installer and refuses
# anything that is not validly signed by Microsoft.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
New-Item -ItemType Directory -Force installer_deps | Out-Null
$items = @{
  'vc_redist.x64.exe'              = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
  'MicrosoftEdgeWebview2Setup.exe' = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703'
}
foreach ($name in $items.Keys) {
  $path = Join-Path installer_deps $name
  Invoke-WebRequest $items[$name] -OutFile $path -MaximumRedirection 5
  $sig = Get-AuthenticodeSignature $path
  if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
    Remove-Item $path -Force
    throw "$name is not validly signed by Microsoft ($($sig.Status))."
  }
  '{0}: OK ({1})' -f $name, (Get-Item $path).VersionInfo.FileVersion
}
