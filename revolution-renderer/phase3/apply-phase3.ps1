$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")
$viewPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\W3DView.cpp"
$view = Get-Content $viewPath -Raw

$needle = @'
	Bool preRenderResult = false;

	if (m_viewFilterMode &&
			m_viewFilter > FT_NULL_FILTER &&
			m_viewFilter < FT_MAX)
'@

$replacement = @'
	Bool preRenderResult = false;

	// Revolution Project: the retail default filter mode is numerically zero, so the
	// legacy "if (m_viewFilterMode)" gate skips the default full-screen filter entirely.
	// Force the default cinematic pass on while preserving all scripted/special filters.
	const Bool revolutionDefaultFilter =
		(m_viewFilter == FT_VIEW_DEFAULT && m_viewFilterMode == FM_VIEW_DEFAULT);

	if (revolutionDefaultFilter ||
			(m_viewFilterMode &&
			m_viewFilter > FT_NULL_FILTER &&
			m_viewFilter < FT_MAX))
'@

if (-not $view.Contains($needle)) {
    throw "Phase 3 pre-render patch point not found."
}
$view = $view.Replace($needle, $replacement)

$needle2 = @'
	if (m_viewFilterMode &&
			m_viewFilter > FT_NULL_FILTER &&
			m_viewFilter < FT_MAX)
	{
		Coord2D deltaScroll;
'@

$replacement2 = @'
	if (revolutionDefaultFilter ||
			(m_viewFilterMode &&
			m_viewFilter > FT_NULL_FILTER &&
			m_viewFilter < FT_MAX))
	{
		Coord2D deltaScroll;
'@

if (-not $view.Contains($needle2)) {
    throw "Phase 3 post-render patch point not found."
}
$view = $view.Replace($needle2, $replacement2)

Set-Content $viewPath $view -Encoding UTF8
Write-Host "Revolution renderer Phase 3 default cinematic pass activation applied."
