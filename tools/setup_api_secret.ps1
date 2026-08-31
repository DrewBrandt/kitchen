param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$tokenBytes = [byte[]]::new(48)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($tokenBytes)
$token = [Convert]::ToBase64String($tokenBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')

$credentialDirectory = Join-Path $env:APPDATA 'PantryInventory'
$encryptedTokenPath = Join-Path $credentialDirectory 'api-token.dpapi'
$temporaryTokenPath = Join-Path $env:TEMP ("pantry-api-token-{0}.env" -f [Guid]::NewGuid())

New-Item -ItemType Directory -Force -Path $credentialDirectory | Out-Null

try {
  Set-Content -LiteralPath $temporaryTokenPath -Value "PANTRY_API_TOKEN=$token" -NoNewline

  Push-Location $ProjectRoot
  try {
    & npx supabase secrets set `
      --project-ref xaetuqdtnolzspfvqvja `
      --env-file $temporaryTokenPath `
      --agent no
    if ($LASTEXITCODE -ne 0) {
      throw "Supabase CLI failed with exit code $LASTEXITCODE."
    }
  }
  finally {
    Pop-Location
  }

  # Only replace the local credential after Supabase accepted the same value.
  $secureToken = ConvertTo-SecureString $token -AsPlainText -Force
  $encryptedToken = ConvertFrom-SecureString $secureToken
  Set-Content -LiteralPath $encryptedTokenPath -Value $encryptedToken -NoNewline
}
finally {
  if (Test-Path -LiteralPath $temporaryTokenPath) {
    Remove-Item -LiteralPath $temporaryTokenPath -Force
  }
  $token = $null
  [Array]::Clear($tokenBytes, 0, $tokenBytes.Length)
}

Write-Host "Supabase Edge Function secret updated. The Windows-encrypted local token is at $encryptedTokenPath"
