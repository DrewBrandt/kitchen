param(
  [Parameter(Mandatory)]
  [ValidateSet('GET', 'POST')]
  [string]$Method,

  [Parameter(Mandatory)]
  [ValidateSet('/v1/inventory', '/v1/history', '/v1/plans', '/v1/grocery-items', '/v1/foods', '/v1/products', '/v1/groceries', '/v1/recipes', '/v1/prepare/recipe', '/v1/prepared-batches', '/v1/consume/prepared', '/v1/consume/inventory', '/v1/consume/product', '/v1/targets', '/v1/preferences', '/v1/routine')]
  [string]$Path,

  [string]$BodyFile,

  [string]$Body,

  [ValidateRange(1, 365)]
  [int]$Days = 30,

  [string]$Query,

  [string]$Id,

  [string]$BaseUrl = 'https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api'
)

$ErrorActionPreference = 'Stop'
$encryptedTokenPath = Join-Path $env:APPDATA 'PantryInventory\api-token.dpapi'

if (-not (Test-Path -LiteralPath $encryptedTokenPath)) {
  throw "No local pantry credential was found. Run tools/setup_api_secret.ps1 first."
}
if ($Method -eq 'POST' -and
    [string]::IsNullOrWhiteSpace($BodyFile) -and
    [string]::IsNullOrWhiteSpace($Body)) {
  throw 'POST requests require -BodyFile or -Body.'
}
if (-not [string]::IsNullOrWhiteSpace($BodyFile) -and
    -not [string]::IsNullOrWhiteSpace($Body)) {
  throw 'Use either -BodyFile or -Body, not both.'
}
if (-not [string]::IsNullOrWhiteSpace($Id) -and $Path -notin @('/v1/foods', '/v1/recipes')) {
  throw '-Id is supported only with /v1/foods or /v1/recipes.'
}
if (-not [string]::IsNullOrWhiteSpace($Id) -and -not [string]::IsNullOrWhiteSpace($Query)) {
  throw 'Use either -Id or -Query, not both.'
}

$secureToken = ConvertTo-SecureString (Get-Content -LiteralPath $encryptedTokenPath -Raw)
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
$token = $null

try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
  if ($Path -eq '/v1/history') {
    $requestPath = "$Path`?days=$Days"
  }
  elseif ($Method -eq 'GET' -and
      $Path -in @('/v1/foods', '/v1/recipes') -and
      -not [string]::IsNullOrWhiteSpace($Id)) {
    $requestPath = "$Path/$([uri]::EscapeDataString($Id))"
  }
  elseif ($Method -eq 'GET' -and $Path -in @('/v1/foods', '/v1/recipes')) {
    $requestPath = if ([string]::IsNullOrWhiteSpace($Query)) {
      $Path
    } else {
      "$Path`?q=$([uri]::EscapeDataString($Query))"
    }
  }
  else {
    $requestPath = $Path
  }
  $request = @{
    Method = $Method
    Uri = "$BaseUrl$requestPath"
    Headers = @{ Authorization = "Bearer $token" }
  }
  if ($Method -eq 'POST') {
    $request.ContentType = 'application/json'
    $request.Body = if ([string]::IsNullOrWhiteSpace($Body)) {
      Get-Content -LiteralPath $BodyFile -Raw
    } else {
      $Body
    }
  }
  Invoke-RestMethod @request
}
finally {
  if ($tokenPointer -ne [IntPtr]::Zero) {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($tokenPointer)
  }
  $token = $null
}
