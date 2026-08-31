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

    $updatedFiles = 0
    foreach ($swiftFile in $swiftFiles) {
        $destination = Join-Path $resolvedPreview $swiftFile.Name
        $needsUpdate = -not (Test-Path -LiteralPath $destination)
        if (-not $needsUpdate) {
            $sourceHash = (Get-FileHash -LiteralPath $swiftFile.FullName -Algorithm SHA256).Hash
            $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
            $needsUpdate = $sourceHash -ne $destinationHash
        }
        if ($needsUpdate) {
            Copy-Item -LiteralPath $swiftFile.FullName -Destination $destination -Force
            $updatedFiles++
        }
    }

    $packageDestination = Join-Path $resolvedPreview 'Package.swift'
    $packageNeedsUpdate = -not (Test-Path -LiteralPath $packageDestination)
    if (-not $packageNeedsUpdate) {
        $packageNeedsUpdate = (Get-FileHash -LiteralPath $packageTemplate -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $packageDestination -Algorithm SHA256).Hash
    }
    if ($packageNeedsUpdate) {
        Copy-Item -LiteralPath $packageTemplate -Destination $packageDestination -Force
        $updatedFiles++
    }

    Write-Output "$resolvedPreview ($updatedFiles file(s) updated)"
}
