param(
    [string]$ProjectPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $ProjectPath
Write-Warning 'The browser does not expose a TLS mode switch. WebView2 manages page connections, and negotiated TLS details are unavailable.'

if ($env:CARGO_HOME) {
    $env:Path = "$env:CARGO_HOME\bin;$env:Path"
}

flutter run -d windows