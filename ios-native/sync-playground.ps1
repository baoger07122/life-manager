$ErrorActionPreference = 'Stop'

$nativeSource = Join-Path $PSScriptRoot 'HomeOSNative'
$packageTemplate = Join-Path $PSScriptRoot 'PlaygroundPackage.swift'
$previewRoots = @(
    'C:\Users\bao\iCloudDrive\iCloud~com~apple~Playgrounds',
    'C:\Users\bao\iCloudDrive\临时文件夹'
)

$swiftFiles = @(Get-ChildItem -LiteralPath $nativeSource -Recurse -Filter '*.swift' -File)
$duplicateNames = $swiftFiles | Group-Object Name | Where-Object Count -gt 1
if ($duplicateNames) {
    throw "Duplicate Swift filename in preview package: $($duplicateNames.Name -join ', ')"
}

foreach ($previewRoot in $previewRoots) {
    $previewPackage = Join-Path $previewRoot 'HomeOSNativePreview.swiftpm'
    $resolvedRoot = [IO.Path]::GetFullPath($previewRoot).TrimEnd('\')
    $resolvedPreview = [IO.Path]::GetFullPath($previewPackage)
    $expectedPreview = $resolvedRoot + '\HomeOSNativePreview.swiftpm'

    if (-not $resolvedPreview.Equals($expectedPreview, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing to update an unexpected preview path.'
    }

    # Keep the .swiftpm directory itself stable. Replacing the whole directory
    # makes iCloud create a new document identity and Swift Playgrounds may keep
    # opening a cached or conflicted older copy.
    New-Item -ItemType Directory -Path $resolvedPreview -Force | Out-Null

    foreach ($swiftFile in $swiftFiles) {
        $destination = Join-Path $resolvedPreview $swiftFile.Name
        Copy-Item -LiteralPath $swiftFile.FullName -Destination $destination -Force
    }

    Copy-Item -LiteralPath $packageTemplate -Destination (Join-Path $resolvedPreview 'Package.swift') -Force

    Write-Output $resolvedPreview
}
