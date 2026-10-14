$ErrorActionPreference = 'Stop'
$releaseVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw | ConvertFrom-Json).version
$distPath = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $distPath -Force | Out-Null
$archivePath = Join-Path $distPath "sprite-sheet-studio-v$releaseVersion.aseprite-extension"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stream = [IO.File]::Open($archivePath, [IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
  foreach ($bundleFile in @('package.json', 'main.lua', 'core.lua', 'effects.lua', 'panels.lua', 'README.md', 'LICENSE')) {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $PSScriptRoot $bundleFile), $bundleFile, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
}
finally {
  $archive.Dispose()
  $stream.Dispose()
}
Write-Output $archivePath
