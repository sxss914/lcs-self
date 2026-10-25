<#
  selfcheck.ps1 —— 环境事实自检器（lcs-self 骨架）

  存在的理由：文档里的结论会过期，而 agent 没有内视。
  这个脚本是那面镜子：把 STATE.md 里写的每条事实，逐条对着磁盘验一遍。

  用法：
    pwsh -File selfcheck.ps1            # 逐项 PASS/FAIL
    pwsh -File selfcheck.ps1 -Recall    # 先回放 STATE.md，再复核
    pwsh -File selfcheck.ps1 -Quiet     # 只打 FAIL 与汇总
  退出码：0 = 全 PASS；1 = 有 FAIL。

  加一条检查：复制下面任一 Check 行，改 id / 描述 / 条件 / 证据。
#>
param([switch]$Recall, [switch]$Quiet)

$ErrorActionPreference = 'Continue'
$here  = $PSScriptRoot
$state = Join-Path $here 'STATE.md'

$checks = New-Object System.Collections.ArrayList
function Check([string]$id, [string]$desc, [bool]$ok, [string]$detail) {
  [void]$checks.Add([pscustomobject]@{ Id = $id; Desc = $desc; Ok = $ok; Detail = $detail })
}

if ($Recall -and (Test-Path $state)) {
  Write-Host '=== STATE.md（前 26 行） ===' -ForegroundColor Cyan
  Get-Content $state -TotalCount 26 -Encoding utf8 | ForEach-Object { Write-Host "  $_" }
  Write-Host ''
}

# ── 示例检查（换成你自己的）─────────────────────────────────────────────
# E1：某个关键文件存在
Check 'E1' '工作目录可写' (Test-Path $here) "根目录 = $here"

# E2：某个命令可用
$gitOk = $false
try { $gitOk = [bool](& git --version 2>$null) } catch {}
Check 'E2' 'git 可用' $gitOk 'git --version 有输出'

# E3：某个配置项的值符合预期（示例：把 env 名换掉即可）
$probe = [Environment]::GetEnvironmentVariable('SELF_PROBE', 'User')
Check 'E3' '示例环境变量' ($true) "SELF_PROBE = [$probe]（占位项，改成你的真实判据）"
# ────────────────────────────────────────────────────────────────────────

$fail = @($checks | Where-Object { -not $_.Ok })

if (-not $Quiet) {
  foreach ($c in $checks) {
    $tag   = if ($c.Ok) { '[PASS]' } else { '[FAIL]' }
    $color = if ($c.Ok) { 'DarkGray' } else { 'Red' }
    Write-Host ("{0} {1} {2,-24} {3}" -f $tag, $c.Id, $c.Desc, $c.Detail) -ForegroundColor $color
  }
} elseif ($fail.Count) {
  foreach ($c in $fail) { Write-Host ("[FAIL] {0} {1} {2}" -f $c.Id, $c.Desc, $c.Detail) -ForegroundColor Red }
}

$stamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssK')
$line  = "{0}  {1}/{2} PASS  fail=[{3}]" -f $stamp, ($checks.Count - $fail.Count), $checks.Count, (($fail | ForEach-Object Id) -join ',')
Write-Host ''
Write-Host ("{0} 项：{1} PASS / {2} FAIL  {3}" -f $checks.Count, ($checks.Count - $fail.Count), $fail.Count,
  $(if ($fail.Count) { '← 与 STATE.md 不一致，先修再信文档' } else { '← 环境与 STATE.md 一致' })) `
  -ForegroundColor $(if ($fail.Count) { 'Red' } else { 'Green' })
try { Add-Content -Path (Join-Path $here 'verify.log') -Value $line -Encoding utf8 } catch {}

if ($fail.Count) { exit 1 } else { exit 0 }
