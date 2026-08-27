$ErrorActionPreference = 'Stop'

$nativeSource = Join-Path $PSScriptRoot 'HomeOSNative'
$packageTemplate = Join-Path $PSScriptRoot 'PlaygroundPackage.swift'
$playgroundsRoot = 'C:\Users\bao\iCloudDrive\iCloud~com~apple~Playgrounds'
$previewPackage = Join-Path $playgroundsRoot 'HomeOSNativePreview.swiftpm'

$resolvedRoot = [IO.Path]::GetFullPath($playgroundsRoot).TrimEnd('\')
$resolvedPreview = [IO.Path]::GetFullPath($previewPackage)
$expectedPrefix = $resolvedRoot + '\'
if (-not $resolvedPreview.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    [IO.Path]::GetFileName($resolvedPreview) -ne 'HomeOSNativePreview.swiftpm') {
    throw 'Refusing to replace an unexpected preview path.'
}

if (Test-Path -LiteralPath $resolvedPreview) {
    Remove-Item -LiteralPath $resolvedPreview -Recurse -Force
}
New-Item -ItemType Directory -Path $previewPackage -Force | Out-Null

foreach ($swiftFile in (Get-ChildItem -LiteralPath $nativeSource -Recurse -Filter '*.swift' -File)) {
    $destination = Join-Path $previewPackage $swiftFile.Name
    if (Test-Path -LiteralPath $destination) {
        throw "Duplicate Swift filename in preview package: $($swiftFile.Name)"
    }
    Copy-Item -LiteralPath $swiftFile.FullName -Destination $destination -Force
}

$previewAssets = Join-Path $previewPackage 'Assets.xcassets'
New-Item -ItemType Directory -Path $previewAssets -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $nativeSource 'Resources\Assets.xcassets\Contents.json') `
    -Destination $previewAssets -Force
foreach ($imageSet in (Get-ChildItem -LiteralPath (Join-Path $nativeSource 'Resources\Assets.xcassets') -Directory -Filter '*.imageset')) {
    Copy-Item -LiteralPath $imageSet.FullName -Destination $previewAssets -Recurse -Force
}
Copy-Item -LiteralPath $packageTemplate -Destination (Join-Path $previewPackage 'Package.swift') -Force

Write-Output $previewPackage
