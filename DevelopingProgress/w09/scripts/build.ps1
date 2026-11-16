param([string]$DevEcoHome = $env:DEVECO_HOME, [ValidateSet('debug','release')][string]$BuildMode = 'debug')
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) {
  $installed = Get-ItemProperty -Path 'HKLM:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/*','HKCU:/SOFTWARE/Microsoft/Windows/CurrentVersion/Uninstall/*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq 'DevEco Studio' } | Select-Object -First 1
  if ($installed) { $DevEcoHome = $installed.InstallLocation }
}
if (-not $DevEcoHome -or -not (Test-Path -LiteralPath (Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.js'))) { throw '请通过 -DevEcoHome 指定 DevEco Studio 安装目录。' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:PATH = (Join-Path $DevEcoHome 'jbr/bin') + ';' + (Join-Path $DevEcoHome 'tools/node') + ';' + $env:PATH
$sdkValue = $env:DEVECO_SDK_HOME.Replace('\','/')
Set-Content -LiteralPath (Join-Path $projectRoot 'local.properties') -Value "sdk.dir=$sdkValue" -Encoding ascii
Push-Location $projectRoot
try {
  & (Join-Path $DevEcoHome 'tools/ohpm/bin/ohpm.bat') install --all
  if ($LASTEXITCODE -ne 0) { throw '本地原生模块依赖安装失败' }
  & (Join-Path $DevEcoHome 'tools/node/node.exe') (Join-Path $DevEcoHome 'tools/hvigor/bin/hvigorw.js') --mode module -p product=default -p module=entry@default -p "buildMode=$BuildMode" assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) { throw "构建失败，退出码 $LASTEXITCODE" }
} finally { Pop-Location }
