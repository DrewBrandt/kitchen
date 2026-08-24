param(
  [Parameter(Mandatory)]
  [ValidateSet('GET', 'POST')]
  [string]$Method,

  [Parameter(Mandatory)]
  [ValidateSet('/v1/inventory', '/v1/foods', '/v1/groceries', '/v1/recipes', '/v1/meals', '/v1/targets', '/v1/access')]
  [string]$Path,

  [string]$BodyFile,

  [string]$BaseUrl = 'https://us-east4-pantry-tracker-4bc45.cloudfunctions.net/pantryApi'
)

$ErrorActionPreference = 'Stop'
$encryptedTokenPath = Join-Path $env:APPDATA 'PantryInventory\api-token.dpapi'

if (-not (Test-Path -LiteralPath $encryptedTokenPath)) {
  throw "No local pantry credential was found. Run tools/setup_api_secret.ps1 first."
}
if ($Method -eq 'POST' -and [string]::IsNullOrWhiteSpace($BodyFile)) {
  throw 'POST requests require -BodyFile.'
}

$secureToken = ConvertTo-SecureString (Get-Content -LiteralPath $encryptedTokenPath -Raw)
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
$token = $null

try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
  $request = @{
    Method = $Method
    Uri = "$BaseUrl$Path"
    Headers = @{ Authorization = "Bearer $token" }
  }
  if ($Method -eq 'POST') {
    $request.ContentType = 'application/json'
    $request.Body = Get-Content -LiteralPath $BodyFile -Raw
  }
  Invoke-RestMethod @request
}
finally {
  if ($tokenPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
  }
  $token = $null
}
