param([string]$DevEcoHome=$env:DEVECO_HOME)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$page=Join-Path $root 'entry/src/main/ets/pages/Index.ets'
$app=Join-Path $root 'AppScope/app.json5'
$raw=Join-Path $root 'entry/src/main/resources/rawfile/device-fixtures'
$pageBytes=[IO.File]::ReadAllBytes($page);$appBytes=[IO.File]::ReadAllBytes($app)
try {
  if(Test-Path -LiteralPath $raw){throw 'device-fixtures already exists; refusing to overwrite'}
  New-Item -ItemType Directory -Path $raw | Out-Null
  Copy-Item -Path (Join-Path $root 'tests/fixtures/*') -Destination $raw
  $probe=[IO.File]::ReadAllText((Join-Path $root 'tests/device/Probe.ets')).Replace('../../entry/src/main/ets/','../')
  [IO.File]::WriteAllText($page,$probe,[Text.UTF8Encoding]::new($false))
  $config=[IO.File]::ReadAllText($app)|ConvertFrom-Json;$config.app.bundleName='com.jietuchengshi.w09probe'
  [IO.File]::WriteAllText($app,($config|ConvertTo-Json -Depth 15),[Text.UTF8Encoding]::new($false))
  & (Join-Path $PSScriptRoot 'build.ps1') -DevEcoHome $DevEcoHome
  $artifacts=Join-Path $root 'artifacts';if(-not(Test-Path -LiteralPath $artifacts)){New-Item -ItemType Directory -Path $artifacts|Out-Null}
  Copy-Item -LiteralPath (Join-Path $root 'entry/build/default/outputs/default/entry-default-unsigned.hap') -Destination (Join-Path $artifacts 'w09-probe.hap') -Force
} finally {
  [IO.File]::WriteAllBytes($page,$pageBytes);[IO.File]::WriteAllBytes($app,$appBytes)
  # Only remove known files in this project's exact temporary fixture directory.
  if(Test-Path -LiteralPath $raw){Get-ChildItem -LiteralPath $raw -File|Remove-Item;Remove-Item -LiteralPath $raw}
}
