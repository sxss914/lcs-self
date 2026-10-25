<#
  journal.ps1 —— 往 JOURNAL.jsonl 追加一条：我做了什么、怎么验的、还剩什么。

  STATE.md 存"当前是什么样"，JOURNAL 存"怎么变成这样的"。
  两者缺一，下一个会话只能从零开始猜。

  用法：
    pwsh -File journal.ps1 -What "改了 X" -How "跑了 Y 验证" [-Left "Z"]
    pwsh -File journal.ps1 -Tail 5
#>
param(
  [string]$What,
  [string]$How,
  [string]$Left = '',
  [int]$Tail = 0
)

$file = Join-Path $PSScriptRoot 'JOURNAL.jsonl'

if ($Tail -gt 0) {
  if (-not (Test-Path $file)) { Write-Host 'JOURNAL.jsonl 还不存在'; return }
  Get-Content $file -Encoding utf8 -Tail $Tail | ForEach-Object {
    try { $o = $_ | ConvertFrom-Json } catch { Write-Host $_; return }
    Write-Host ("[{0}] {1}" -f $o.at, $o.what) -ForegroundColor Cyan
    if ($o.how)  { Write-Host ("          how: {0}" -f $o.how) -ForegroundColor DarkGray }
    if ($o.left) { Write-Host ("         left: {0}" -f $o.left) -ForegroundColor Yellow }
  }
  return
}

if (-not $What) { Write-Host '需要 -What（做了什么）'; exit 2 }

$entry = [ordered]@{
  at   = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
  what = $What
  how  = $How
  left = $Left
}
$json = $entry | ConvertTo-Json -Compress -Depth 3
Add-Content -Path $file -Value $json -Encoding utf8
Write-Host ("已追加 → {0}" -f $file) -ForegroundColor Green
Write-Host $json -ForegroundColor DarkGray
