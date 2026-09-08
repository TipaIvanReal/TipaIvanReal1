$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")
$src  = Resolve-Path (Join-Path $PSScriptRoot ".")

$mainDir = Join-Path $root "GeneralsMD\Code\Main"
Copy-Item (Join-Path $src "RevolutionRendererProbe.h") (Join-Path $mainDir "RevolutionRendererProbe.h") -Force
Copy-Item (Join-Path $src "RevolutionRendererProbe.cpp") (Join-Path $mainDir "RevolutionRendererProbe.cpp") -Force

$cmakePath = Join-Path $mainDir "CMakeLists.txt"
$cmake = Get-Content $cmakePath -Raw

if ($cmake -notmatch "\bd3d12\b") {
    $cmake = $cmake -replace "(target_link_libraries\(z_generals PRIVATE\s*\r?\n)", "`$1    d3d12`r`n    dxgi`r`n"
}

if ($cmake -notmatch "RevolutionRendererProbe\.cpp") {
    $cmake = $cmake -replace "(target_sources\(z_generals PRIVATE\s*\r?\n\s*WinMain\.cpp\s*\r?\n\s*WinMain\.h)", "`$1`r`n    RevolutionRendererProbe.cpp`r`n    RevolutionRendererProbe.h"
}

Set-Content $cmakePath $cmake -Encoding UTF8

$winMainPath = Join-Path $mainDir "WinMain.cpp"
$winMain = Get-Content $winMainPath -Raw

if ($winMain -notmatch '#include "RevolutionRendererProbe.h"') {
    $winMain = $winMain -replace '(#include "resource\.h")', "`$1`r`n#include `"RevolutionRendererProbe.h`""
}

if ($winMain -notmatch "RevolutionRendererProbe_Initialize\(\)") {
    $needle = "::SetCurrentDirectory(buffer);"
    $replacement = "::SetCurrentDirectory(buffer);`r`n`r`n        // Revolution Project: initialize the in-engine Direct3D 12 capability layer.`r`n        // This is intentionally non-invasive while the legacy draw calls are migrated.`r`n        RevolutionRendererProbe_Initialize();"
    $winMain = $winMain.Replace($needle, $replacement)
}

Set-Content $winMainPath $winMain -Encoding UTF8

# Phase 1 visible quality upgrades on the existing WW3D path.
# Keep projected-shadow texture sizes unchanged: that system caches one texture per
# unique model, so brute-force 2K shadows would waste large amounts of VRAM.
$waterPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\Water\W3DWater.cpp"
$water = Get-Content $waterPath -Raw
$water = $water -replace '#define SEA_REFLECTION_SIZE 256', '#define SEA_REFLECTION_SIZE 1024'
Set-Content $waterPath $water -Encoding UTF8

# Modern GPUs can handle 16x anisotropic filtering essentially for free in this game.
# Make it the renderer default; user/game settings can still override it later.
$ww3dPath = Join-Path $root "Core\Libraries\Source\WWVegas\WW3D2\ww3d.cpp"
$ww3d = Get-Content $ww3dPath -Raw
$ww3d = $ww3d -replace 'WW3D::TextureFilter = TextureFilterClass::TextureFilterMode::TEXTURE_FILTER_BILINEAR;', 'WW3D::TextureFilter = TextureFilterClass::TextureFilterMode::TEXTURE_FILTER_ANISOTROPIC;'
$ww3d = $ww3d -replace 'WW3D::AnisotropyLevel = TextureFilterClass::AnisotropicFilterMode::TEXTURE_FILTER_ANISOTROPIC_2X;', 'WW3D::AnisotropyLevel = TextureFilterClass::AnisotropicFilterMode::TEXTURE_FILTER_ANISOTROPIC_16X;'
Set-Content $ww3dPath $ww3d -Encoding UTF8

Write-Host "Revolution renderer Phase 1 patch applied."
