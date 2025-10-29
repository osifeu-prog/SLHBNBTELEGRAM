Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---- Force TLS1.2 for all HTTPS calls (PS5.1/.NET 4.x) ----
try {
  # .NET enum (3072) = Tls12
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {}

# --- Settings ---
$AUTO_PUSH   = $false
$REMOTE_NAME = "origin"

# --- Setup & Paths ---
$ProjectRoot = (Resolve-Path ".").Path
Push-Location $ProjectRoot
$stamp   = (Get-Date).ToString("yyyyMMdd_HHmmss")
$diagDir = Join-Path $ProjectRoot ".diagnostics_$stamp"
New-Item -ItemType Directory -Force -Path $diagDir | Out-Null
$logTxt  = Join-Path $diagDir "diagnostics.txt"
$logJson = Join-Path $diagDir "diagnostics.json"

function WL($m){ Write-Host $m; Add-Content -LiteralPath $logTxt -Value $m }
function WSection($t){ $line=('='*10)+" "+$t+" "+('='*10); WL "`n$line`n" }
function SafeRead($p,$max=4000){ if(Test-Path -LiteralPath $p){ $txt=Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue; if($null -ne $txt -and $txt.Length -gt $max){ return ($txt.Substring(0,$max)+"`n...<truncated>") } return $txt } "<missing>" }
function ParseDotEnv($path){
  $h=@{}
  if(Test-Path -LiteralPath $path){
    Get-Content -LiteralPath $path | % {
      $line = $_
      if($line -match '^\s*#' -or $line.Trim() -eq ""){ return }
      $parts = $line -split "=",2
      if($parts.Count -lt 2){ return }
      $k=$parts[0].Trim(); $v=$parts[1].Trim()
      if($v.StartsWith('"') -and $v.EndsWith('"')){ $v=$v.Substring(1,$v.Length-2) }
      if($v.StartsWith("'") -and $v.EndsWith("'")){ $v=$v.Substring(1,$v.Length-2) }
      $h[$k]=$v
    }
  }
  $h
}

# --- Report obj ---
$report = [ordered]@{ when_utc=(Get-Date).ToUniversalTime().ToString("s")+"Z"; project=$ProjectRoot; files=@{}; env=@{}; checks=[ordered]@{}; probe=@(); summary=@(); recommendations=@() }

# 1) Files snapshot
WSection "Project Files Snapshot"
$wanted = @(".env",".env.example","Procfile","railway.json","requirements.txt","runtime.txt","README.md","app\app_web.py","app\app_webhook.py","app\bot.py","app\abi","scripts")
foreach($w in $wanted){
  $p = Join-Path $ProjectRoot $w
  $exists = Test-Path -LiteralPath $p
  $size = 0
  if($exists -and -not (Get-Item -LiteralPath $p).PSIsContainer){ $size = (Get-Item -LiteralPath $p).Length }
  $sample = if($exists -and (Get-Item -LiteralPath $p).PSIsContainer){"<dir>"} else { SafeRead $p 800 }
  $report.files[$w] = @{exists=$exists;size=$size;sample=$sample}
}
WL ("Files: " + (($report.files.Keys) -join ", "))

# 2) ENV collection
WSection "Environment Collection"
$envNames = @("BOT_TOKEN","SECRET_KEY","WEBHOOK_URL","DATA_DIR","BSC_RPC_URL","CHAIN_ID","SELA_TOKEN_ADDRESS","LOG_LEVEL","DEBUG","ADMIN_USER_ID","USE_PIN_KDF","OPENAI_API_KEY","HUGGINGFACE_TOKEN")
$envMap = @{}
foreach($n in $envNames){ $envMap[$n]=$null }
Get-ChildItem Env: | % { if($envNames -contains $_.Name){ $envMap[$_.Name]=$_.Value } }
$fromEnv = ParseDotEnv (Join-Path $ProjectRoot ".env")
$fromEx  = ParseDotEnv (Join-Path $ProjectRoot ".env.example")
foreach($n in $envNames){
  if(-not $envMap[$n] -and $fromEnv.ContainsKey($n)){ $envMap[$n]=$fromEnv[$n] }
  if(-not $envMap[$n] -and $fromEx.ContainsKey($n)){  $envMap[$n]=$fromEx[$n] }
}
if(-not $envMap["BSC_RPC_URL"]){ $envMap["BSC_RPC_URL"]="https://bsc-dataseed.binance.org" }
if(-not $envMap["CHAIN_ID"]){    $envMap["CHAIN_ID"]="56" }
if(-not $envMap["DATA_DIR"]){    $envMap["DATA_DIR"]=Join-Path $ProjectRoot "data" }
if(-not $envMap["SELA_TOKEN_ADDRESS"]){ $envMap["SELA_TOKEN_ADDRESS"]="0xEf633c34715A5A581741379C9D690628A1C82B74" }
$report.env = $envMap
# print ENV snapshot to console
$envMap.GetEnumerator() | Sort-Object Name | % { "{0}={1}" -f $_.Name, $_.Value } | % { WL $_ }

# 3) HTTP health
WSection "HTTP Health (Railway)"
$health=[ordered]@{}
$baseUrl = $envMap["WEBHOOK_URL"]
if($baseUrl -and $baseUrl -match '^https?://'){
  foreach($path in @("/","/healthz","/webhook")){
    $url = ($baseUrl.TrimEnd("/")) + $path
    try{
      $resp = Invoke-WebRequest -Uri $url -Method GET -TimeoutSec 20 -ErrorAction Stop
      $health[$path]=@{status=$resp.StatusCode;length=$resp.Content.Length}
      WL ("GET "+$url+" => "+$resp.StatusCode)
    }catch{
      $health[$path]=@{error=$_.Exception.Message}
      WL ("GET "+$url+" => ERROR: "+$_.Exception.Message)
    }
  }
}else{
  $health.note="WEBHOOK_URL missing or invalid"
  WL "WEBHOOK_URL missing or invalid"
}
$report.checks.http_health=$health

# 4) Telegram basic checks
WSection "Telegram API"
$tg=[ordered]@{}
$botToken=$envMap["BOT_TOKEN"]
if($botToken -and $botToken -ne "TRUE"){
  try{ $r = Invoke-WebRequest -Uri ("https://api.telegram.org/bot{0}/getMe" -f $botToken) -Method POST -TimeoutSec 20; $tg.getMe_status=$r.StatusCode; WL ("Telegram getMe => "+$r.StatusCode) }catch{ $tg.getMe_error=$_.Exception.Message; WL ("Telegram getMe ERROR: "+$_.Exception.Message) }
  try{ $r2= Invoke-WebRequest -Uri ("https://api.telegram.org/bot{0}/getWebhookInfo" -f $botToken) -Method POST -TimeoutSec 20; $tg.getWebhookInfo_status=$r2.StatusCode; $tg.getWebhookInfo_body=($r2.Content|ConvertFrom-Json); WL ("Telegram getWebhookInfo => "+$r2.StatusCode+" ; url="+($tg.getWebhookInfo_body.result.url)) }catch{ $tg.getWebhookInfo_error=$_.Exception.Message; WL ("Telegram getWebhookInfo ERROR: "+$_.Exception.Message) }
}else{
  $tg.note="BOT_TOKEN missing or placeholder"
  WL "BOT_TOKEN missing or placeholder"
}
$report.checks.telegram=$tg

# 5) JSON-RPC helpers
function Rpc($rpcUrl,$method,$params,$id){
  $body=@{jsonrpc="2.0";method=$method;params=$params;id=$id}|ConvertTo-Json -Depth 6
  try{
    $resp=Invoke-WebRequest -Uri $rpcUrl -Method POST -ContentType "application/json" -Body $body -TimeoutSec 25
    return $resp.Content|ConvertFrom-Json
  }catch{
    return @{ error=$_.Exception.Message }
  }
}
function Calldata_BalanceOf($addr){ $a=$addr; if($a.StartsWith("0x")){$a=$a.Substring(2)}; return "0x70a08231"+("0"*(64-$a.Length))+$a }
function HexToUInt256($hex){ try{ $h=$hex; if($h.StartsWith("0x")){$h=$h.Substring(2)}; $bytes=for($i=0;$i -lt $h.Length;$i+=2){ [Convert]::ToByte($h.Substring($i,2),16) }; $bytes = ,0 + $bytes; $bi = New-Object System.Numerics.BigInteger (,[byte[]]$bytes); return [string]$bi }catch{ return "ERR:"+$_.Exception.Message } }

# 6) Probe both networks
WSection "BSC Probing (Mainnet + Testnet)"
$TokenAddress = $envMap["SELA_TOKEN_ADDRESS"]
$TestAddress  = "0x693db6c817083818696a7228aEbfBd0Cd3371f02"
$targets = @(
  @{ name="MAINNET"; rpc="https://bsc-dataseed.binance.org"; chain=56 },
  @{ name="TESTNET"; rpc="https://data-seed-prebsc-1-s1.binance.org:8545"; chain=97 }
)
$probe = @()
foreach($t in $targets){
  $row = [ordered]@{ network=$t.name; rpc=$t.rpc; chain_expected=$t.chain }
  $r1 = Rpc $t.rpc "eth_chainId" @() 1
  if($r1 -and $r1.result){ $row.chain_id=[Convert]::ToInt32($r1.result,16) } else { $row.chain_id_error=$r1.error }
  $r2 = Rpc $t.rpc "eth_getCode" @($TokenAddress,"latest") 2
  $row.getCode = $r2.result
  $row.has_code = ($r2 -and $r2.result -and $r2.result -ne "0x")
  $erc=[ordered]@{}
  foreach($k in @(@{k="name";s="0x06fdde03"}, @{k="symbol";s="0x95d89b41"}, @{k="decimals";s="0x313ce567"}, @{k="totalSupply";s="0x18160ddd"})){
    $rr = Rpc $t.rpc "eth_call" @(@{to=$TokenAddress;data=$k.s},"latest") ("c_"+$k.k)
    $erc[$k.k]=$rr.result
  }
  $rb = Rpc $t.rpc "eth_call" @(@{to=$TokenAddress;data=(Calldata_BalanceOf $TestAddress)},"latest") "c_balance"
  $erc.balanceOf_raw = $rb.result
  if($rb -and $rb.result){ $erc.balanceOf_decoded=(HexToUInt256 $rb.result) }
  $row.erc20=$erc
  $probe += $row
}
$report.probe = $probe

# print probe table to console
$probe | Select-Object network, chain_id, has_code,
  @{n='name';e={$_.erc20.name}},
  @{n='symbol';e={$_.erc20.symbol}},
  @{n='decimals';e={$_.erc20.decimals}},
  @{n='totalSupply';e={$_.erc20.totalSupply}},
  @{n='balanceOf_raw';e={$_.erc20.balanceOf_raw}},
  @{n='balanceOf_decoded';e={$_.erc20.balanceOf_decoded}} | Format-Table -Auto | Out-String | % { WL $_ }

# 7) DATA_DIR write test
WSection "DATA_DIR Write Test"
$dataDir=$envMap["DATA_DIR"]; $dataTest=[ordered]@{}
if($dataDir){
  try{
    if(-not (Test-Path -LiteralPath $dataDir)){ New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
    $probeFile=Join-Path $dataDir ("write_probe_{0}.txt" -f $stamp)
    "ok "+$stamp | Set-Content -LiteralPath $probeFile -Encoding UTF8
    $txt=Get-Content -LiteralPath $probeFile -Raw
    Remove-Item -LiteralPath $probeFile -Force
    $dataTest=@{writable=$true;sample=$txt}; WL "DATA_DIR writable."
  }catch{ $dataTest=@{writable=$false;error=$_.Exception.Message}; WL ("DATA_DIR not writable: "+$_.Exception.Message) }
}else{ $dataTest=@{note="DATA_DIR missing"}; WL "DATA_DIR missing" }
$report.checks.data_dir=$dataTest

# 8) Conclusions (also print to console)
WSection "Conclusions"
$cidEnvInt = 0
[int]::TryParse($envMap["CHAIN_ID"], [ref]$cidEnvInt) | Out-Null
$main = $probe | Where-Object { $_.network -eq "MAINNET" }
$test = $probe | Where-Object { $_.network -eq "TESTNET" }
$recommend = New-Object System.Collections.Generic.List[string]
$summary   = New-Object System.Collections.Generic.List[string]

if (-not $cidEnvInt -or $cidEnvInt -eq 0) {
  $recommend.Add("Set CHAIN_ID to 56 (mainnet) or 97 (testnet) in Railway (no quotes).")
}
elseif ($main -and -not $main.has_code -and $test -and $test.has_code) {
  $summary.Add("Token found on TESTNET, not on MAINNET.")
  $recommend.Add("Switch to Testnet: BSC_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545 ; CHAIN_ID=97.")
}
elseif ($main -and $main.has_code -and $cidEnvInt -ne 56) {
  $summary.Add("Token present on MAINNET; CHAIN_ID should be 56.")
  $recommend.Add("Set CHAIN_ID=56 and BSC_RPC_URL=https://bsc-dataseed.binance.org.")
}
elseif (-not $main.has_code -and -not $test.has_code) {
  $summary.Add("No bytecode on either network for the provided address.")
  $recommend.Add("Verify SELA_TOKEN_ADDRESS (typo?) or confirm deployment network.")
}
else {
  $summary.Add("Token detected on the configured network.")
}

# Telegram webhook hint
if ($report.checks.telegram -and $report.checks.telegram.getWebhookInfo_body -and $report.checks.telegram.getWebhookInfo_body.result) {
  $tgUrl = $report.checks.telegram.getWebhookInfo_body.result.url
  if ($baseUrl -and $tgUrl -and ($tgUrl -ne $baseUrl)) {
    $recommend.Add("Telegram webhook mismatch: Telegram=$tgUrl vs ENV=$baseUrl. Re-set webhook on startup.")
  }
}

$report.summary = $summary.ToArray()
$report.recommendations = $recommend.ToArray()

WL "=== SUMMARY ==="
if($report.summary.Count -eq 0){ WL "- (no items)" } else { $report.summary | % { WL ("- "+$_) } }
WL "`n=== RECOMMENDATIONS ==="
if($report.recommendations.Count -eq 0){ WL "- (no items)" } else { $report.recommendations | % { WL ("- "+$_) } }

# 9) Persist report
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $logJson -Encoding UTF8
WL ("Saved: " + $logTxt)
WL ("Saved: " + $logJson)

# 10) Git prep
WSection "Git Prep"
$git = (Get-Command git -ErrorAction SilentlyContinue)
if(-not $git){
  WL "git not found in PATH. Skipping git steps."
}else{
  if(-not (Test-Path ".git")){ git init | Out-Null; WL "Initialized empty git repo." }
  if(-not (Test-Path ".gitignore")){
@"
__pycache__/
*.pyc
.venv/
node_modules/
.DS_Store
Thumbs.db
*.log
data/
*.sqlite*
.diagnostics_*/
"@ | Set-Content -LiteralPath ".gitignore" -Encoding ascii
    WL "Created .gitignore"
  }
  git add -A
  git commit -m "SLH: diagnostics + clean structure ($stamp)" 2>$null | Out-Null
  WL "Committed (or nothing to commit)."
  if($AUTO_PUSH){
    git branch -M main 2>$null | Out-Null
    try{ git push -u origin main; WL "Pushed to origin/main." }catch{ WL ("Push failed: "+$_.Exception.Message) }
  } else {
    WL "Auto-push disabled. Set `$AUTO_PUSH=$true` to enable."
  }
}

Write-Host "`n== DONE ==" -ForegroundColor Green
Write-Host ("Reports: "+$diagDir) -ForegroundColor Green
Pop-Location
