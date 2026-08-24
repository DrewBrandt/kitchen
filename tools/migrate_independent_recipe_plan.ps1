param(
  [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$migrationPath = Join-Path $PSScriptRoot 'independent_recipe_plan_migration.json'
$migration = Get-Content -LiteralPath $migrationPath -Raw | ConvertFrom-Json

if (-not $Apply) {
  [pscustomobject]@{
    mode = 'dry-run'
    recipesToUpsert = $migration.recipes.Count
    planEntries = $migration.plan.entries.Count
    weekStart = $migration.plan.weekStart
  }
  return
}

foreach ($recipe in $migration.recipes) {
  & (Join-Path $PSScriptRoot 'pantry_api.ps1') `
    -Method POST `
    -Path /v1/recipes `
    -Body ($recipe | ConvertTo-Json -Depth 20 -Compress) | Out-Null
}

& (Join-Path $PSScriptRoot 'pantry_api.ps1') `
  -Method POST `
  -Path /v1/plans `
  -Body ($migration.plan | ConvertTo-Json -Depth 20 -Compress)
