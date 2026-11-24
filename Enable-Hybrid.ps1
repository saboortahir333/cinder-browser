param(
    [string]$ProjectPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $ProjectPath
Write-Warning 'Hybrid PQC is not applied to WebView2 page traffic. WebView2 manages page connections, and negotiated PQC state is unavailable.'

if ($env:CARGO_HOME) {
    $env:Path = "$env:CARGO_HOME\bin;$env:Path"
}

flutter run -d windows