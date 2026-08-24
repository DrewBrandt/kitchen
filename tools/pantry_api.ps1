param(
  [Parameter(Mandatory)]
  [ValidateSet('GET', 'POST')]
  [string]$Method,

  [Parameter(Mandatory)]
  [ValidateSet('/v1/inventory', '/v1/history', '/v1/history/reconcile', '/v1/plans', '/v1/grocery-items', '/v1/foods', '/v1/products', '/v1/migrations/canonical-products', '/v1/groceries', '/v1/recipes', '/v1/external-foods', '/v1/meals', '/v1/prepare/recipe', '/v1/prepared-batches', '/v1/consume/prepared', '/v1/consume/meal-template', '/v1/meal-templates', '/v1/consume/recipe', '/v1/consume/inventory', '/v1/targets', '/v1/preferences', '/v1/access')]
  [string]$Path,

  [string]$BodyFile,

  [string]$Body,

  [ValidateRange(1, 365)]
  [int]$Days = 30,

  [string]$Query,

  [string]$Brand,

  [string]$BaseUrl = 'https://us-east4-pantry-tracker-4bc45.cloudfunctions.net/pantryApi'
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

$secureToken = ConvertTo-SecureString (Get-Content -LiteralPath $encryptedTokenPath -Raw)
$tokenPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
$token = $null

try {
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($tokenPointer)
  if ($Path -eq '/v1/history') {
    $requestPath = "$Path`?days=$Days"
  }
  elseif ($Method -eq 'GET' -and $Path -eq '/v1/external-foods') {
    $queryParts = @()
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
      $queryParts += "q=$([uri]::EscapeDataString($Query))"
    }
    if (-not [string]::IsNullOrWhiteSpace($Brand)) {
      $queryParts += "brand=$([uri]::EscapeDataString($Brand))"
    }
    $requestPath = if ($queryParts.Count -eq 0) { $Path } else { "$Path`?$($queryParts -join '&')" }
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
