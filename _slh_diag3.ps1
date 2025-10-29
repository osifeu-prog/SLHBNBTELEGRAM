Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072 } catch {}

$ProjectRoot = (Resolve-Path ".").Path
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$diag  = Join-Path $ProjectRoot ".diagnostics_$stamp"
New-Item -ItemType Directory -Force -Path $diag | Out-Null
$txt = Join-Path $diag "diagnostics.txt"
$json= Join-Path $diag "diagnostics.json"
function WL($m){ Write-Host $m; Add-Content -LiteralPath $txt -Value $m }
function W($t){ $l=('='*10)+" "+$t+" "+('='*10); WL "`n$l`n" }
function ParseEnv($p){ $h=@{}; if(Test-Path $p){ Get-Content $p |%{
  if($_ -match '^\s*#' -or $_.Trim() -eq ''){return}
  $k,$v = $_ -split '=',2; $k=$k.Trim(); $v=$v.Trim().Trim('"').Trim("'"); $h[$k]=$v } }
  return $h
}
# ENV
W "ENV"
$names=@("BOT_TOKEN","WEBHOOK_URL","BSC_RPC_URL","CHAIN_ID","SELA_TOKEN_ADDRESS","DATA_DIR","LOG_LEVEL","DEBUG")
$env=@{}; foreach($n in $names){ $env[$n]=$null }; Get-ChildItem Env:|%{ if($names -contains $_.Name){ $env[$_.Name]=$_.Value } }
$fromEnv=ParseEnv ".env"; $fromEx=ParseEnv ".env.example"
foreach($n in $names){ if(-not $env[$n] -and $fromEnv.ContainsKey($n)){$env[$n]=$fromEnv[$n]}; if(-not $env[$n] -and $fromEx.ContainsKey($n)){$env[$n]=$fromEx[$n]} }
if(-not $env["BSC_RPC_URL"]){ $env["BSC_RPC_URL"]="https://bsc-dataseed.binance.org" }
if(-not $env["CHAIN_ID"]){    $env["CHAIN_ID"]="56" }
if(-not $env["DATA_DIR"]){    $env["DATA_DIR"]=Join-Path $ProjectRoot "data" }
$env.GetEnumerator()|sort Name|%{ WL ("{0}={1}" -f $_.Name,$_.Value) }

# Health
W "Health"
if($env["WEBHOOK_URL"]){
  foreach($p in @("/","/healthz","/webhook")){
    $u=($env["WEBHOOK_URL"].TrimEnd("/"))+$p
    try{ $r=Invoke-WebRequest -Uri $u -TimeoutSec 15; WL "GET $u => $($r.StatusCode)" }catch{ WL "GET $u => ERROR: $($_.Exception.Message)" }
  }
}

# BSC probe (???)
W "BSC Probe"
function Rpc($url,$m,$pa,$id){
  $b=@{jsonrpc="2.0";method=$m;params=$pa;id=$id}|ConvertTo-Json
  try{ (Invoke-WebRequest -Uri $url -Method POST -ContentType "application/json" -Body $b -TimeoutSec 20).Content | ConvertFrom-Json }catch{ @{ error=$_.Exception.Message } }
}
function BalOf($a){ $x=$a.TrimStart('0x'); "0x70a08231"+("0"*(64-$x.Length))+$x }
function HexU($h){ try{ $s=$h.TrimStart('0x'); $bytes=for($i=0;$i -lt $s.Length;$i+=2){ [Convert]::ToByte($s.Substring($i,2),16) }; $bytes = ,0 + $bytes; ([System.Numerics.BigInteger]([byte[]]$bytes)).ToString() }catch{"ERR"} }

$token=$env["SELA_TOKEN_ADDRESS"]; $addr="0x693db6c817083818696a7228aEbfBd0Cd3371f02"
$nets=@(
  @{n="MAINNET"; rpc="https://bsc-dataseed.binance.org"; cid=56},
  @{n="TESTNET"; rpc="https://data-seed-prebsc-1-s1.binance.org:8545"; cid=97}
)
$probe=@()
foreach($t in $nets){
  $row=[ordered]@{network=$t.n}
  $cid=Rpc $t.rpc "eth_chainId" @() 1
  $row.chain_id= if($cid.result){ [Convert]::ToInt32($cid.result,16) } else { $null }
  $code=Rpc $t.rpc "eth_getCode" @($token,"latest") 2
  $row.has_code = ($code.result -and $code.result -ne "0x")
  $bal =Rpc $t.rpc "eth_call" @(@{to=$token;data=(BalOf $addr)},"latest") 3
  $row.balanceOf_raw=$bal.result
  $row.balanceOf_decoded= if($bal.result){ HexU $bal.result } else { $null }
  $probe += [pscustomobject]$row
}
$probe | Format-Table -Auto | Out-String | WL

# Conclusions
W "Conclusions"
$sum=@(); $rec=@()
if($probe){
  $m=$probe | ?{$_.network -eq "MAINNET"}
  $t=$probe | ?{$_.network -eq "TESTNET"}
  if($m -and -not $m.has_code -and $t -and $t.has_code){ $sum += "Token found on TESTNET, not on MAINNET."; $rec += "Set BSC_RPC_URL=testnet + CHAIN_ID=97 (both API & Bot)."}
  elseif($m -and $m.has_code -and $env["CHAIN_ID"] -ne "56"){ $sum += "Token present on MAINNET; CHAIN_ID should be 56."; $rec += "Set BSC_RPC_URL=mainnet + CHAIN_ID=56."}
  elseif(-not $m.has_code -and -not $t.has_code){ $sum += "No bytecode on either network for this address."; $rec += "Verify SELA_TOKEN_ADDRESS."}
  else{ $sum += "Token detected on configured network."; }
}
if($env["WEBHOOK_URL"]){ $rec += "GET /webhook => 405 ?? ???? (????? ???? POST ?????? ????)." }
"=== SUMMARY ===" | WL; if($sum.Count){ $sum|%{ WL "- $_"} } else { WL "- (no items)" }
"`n=== RECOMMENDATIONS ===" | WL; if($rec.Count){ $rec|%{ WL "- $_"} } else { WL "- (no items)" }
@{env=$env; probe=$probe; sum=$sum; rec=$rec} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $json -Encoding UTF8
WL ("Saved: "+$txt); WL ("Saved: "+$json)
Write-Host "`n== DONE ==" -Foreground Green
