param([string]$DevEcoHome = $env:DEVECO_HOME)
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) {
  $installed = Get-ItemProperty -Path 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/*','HKCU:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'DevEco Studio' } | Select-Object -First 1
  if ($installed) { $DevEcoHome = $installed.InstallLocation }
}
if (-not $DevEcoHome) { throw '请提供 -DevEcoHome 参数。' }
$env:DEVECO_HOME = $DevEcoHome
$nodePath = Join-Path $DevEcoHome 'tools/node/node.exe'
& $nodePath (Join-Path $PSScriptRoot '../tests/domain.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '字段提取测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/repository.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '数据库事务测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/image-hash.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '图片哈希分块读取测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/text-entry.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '中文预编辑输入测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/recognition.test.cjs')
if ($LASTEXITCODE -ne 0) { throw 'OCR能力检查测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/association.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '第八周关联排序测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/appearance.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '外观持久化测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/motion.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '手势边界与材质能力回落测试失败' }
& $nodePath (Join-Path $PSScriptRoot '../tests/navigation.test.cjs')
if ($LASTEXITCODE -ne 0) { throw '来源事项连续导航测试失败' }
