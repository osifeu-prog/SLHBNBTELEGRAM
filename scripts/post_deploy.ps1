# Post-deploy fix & sanity for Railway
Write-Host "== SLH post-deploy ==" -ForegroundColor Green
$envs = @(
  "BOT_TOKEN","SECRET_KEY","WEBHOOK_URL","DATA_DIR",
  "BSC_RPC_URL","CHAIN_ID","SELA_TOKEN_ADDRESS","LOG_LEVEL"
)
foreach($e in $envs){ if([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($e))){ Write-Host "WARN missing $e" -ForegroundColor Yellow } }
Write-Host "Try set webhook..." -ForegroundColor Cyan
try {
  Invoke-WebRequest -Uri "$($env:WEBHOOK_URL)/set_webhook" -UseBasicParsing
} catch { Write-Host "set_webhook failed: $_" -ForegroundColor Yellow }
Write-Host "Health:" -ForegroundColor Cyan
try {
  Invoke-WebRequest -Uri "$($env:WEBHOOK_URL)/health" -UseBasicParsing
} catch { Write-Host "health failed: $_" -ForegroundColor Yellow }
