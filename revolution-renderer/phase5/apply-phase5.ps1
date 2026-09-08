$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")

function Replace-Required([string]$text, [string]$old, [string]$new, [string]$label)
{
    if (-not $text.Contains($old)) {
        throw "Phase 5 patch point not found: $label"
    }
    return $text.Replace($old, $new)
}

# ---------------------------------------------------------------------------
# Visible lighting pass.
# Apply the cinematic key/fill ratio at W3DDisplay::setTimeOfDay, which runs
# after map lighting data is available. No direct D3D render-state access here.
# ---------------------------------------------------------------------------
$displayPath = Join-Path $root "GeneralsMD\Code\GameEngineDevice\Source\W3DDevice\GameClient\W3DDisplay.cpp"
$display = Get-Content $displayPath -Raw

$old = @'
void W3DDisplay::setTimeOfDay( TimeOfDay tod )
{
	const GlobalData::TerrainLighting *ol=&TheGlobalData->m_terrainObjectsLighting[tod][0];

	if( m_3DScene )
	{
		m_3DScene->Set_Ambient_Light( Vector3(ol->ambient.red, ol->ambient.green, ol->ambient.blue) );
	}

	for (Int i=0; i<LightEnvironmentClass::MAX_LIGHTS; i++)
	{
		if( m_myLight[i] )
		{
			ol=&TheGlobalData->m_terrainObjectsLighting[tod][i];

			m_myLight[i]->Set_Ambient( Vector3( 0.0f, 0.0f, 0.0f ) );
			m_myLight[i]->Set_Diffuse( Vector3(ol->diffuse.red, ol->diffuse.green, ol->diffuse.blue ) );
			m_myLight[i]->Set_Specular( Vector3(0,0,0) );
			Matrix3D mtx;
			mtx.Set(Vector3(1,0,0), Vector3(0,1,0), Vector3(ol->lightPos.x, ol->lightPos.y, ol->lightPos.z), Vector3(0,0,0));
			m_myLight[i]->Set_Transform(mtx);
		}
	}
	if(TheTerrainRenderObject) {
		TheTerrainRenderObject->setTimeOfDay(tod);
		TheTacticalView->forceRedraw();
	}
}
'@

$new = @'
void W3DDisplay::setTimeOfDay( TimeOfDay tod )
{
	const GlobalData::TerrainLighting *ol=&TheGlobalData->m_terrainObjectsLighting[tod][0];

	// Revolution Project Phase 5:
	// Much stronger key/fill separation so geometry reads clearly even with
	// the original Generals materials. This deliberately targets a visible
	// change rather than a subtle post-process tweak.
	Real ambientScale = 0.48f;
	Real diffuseScale = 1.55f;
	Vector3 sunTint(1.10f, 1.00f, 0.88f);

	if (tod == TIME_OF_DAY_MORNING)
	{
		ambientScale = 0.54f;
		diffuseScale = 1.45f;
		sunTint.Set(1.12f, 1.01f, 0.86f);
	}
	else if (tod == TIME_OF_DAY_EVENING)
	{
		ambientScale = 0.44f;
		diffuseScale = 1.42f;
		sunTint.Set(1.15f, 0.96f, 0.80f);
	}
	else if (tod == TIME_OF_DAY_NIGHT)
	{
		ambientScale = 0.68f;
		diffuseScale = 1.22f;
		sunTint.Set(0.78f, 0.92f, 1.18f);
	}

	if( m_3DScene )
	{
		Vector3 ambient(
			ol->ambient.red * ambientScale,
			ol->ambient.green * ambientScale,
			ol->ambient.blue * ambientScale);

		static Vector3 maxLight(1.0f, 1.0f, 1.0f);
		ambient.Cap_Absolute_To(maxLight);
		m_3DScene->Set_Ambient_Light(ambient);
	}

	for (Int i=0; i<LightEnvironmentClass::MAX_LIGHTS; i++)
	{
		if( m_myLight[i] )
		{
			ol=&TheGlobalData->m_terrainObjectsLighting[tod][i];

			Vector3 diffuse(
				ol->diffuse.red * diffuseScale * sunTint.X,
				ol->diffuse.green * diffuseScale * sunTint.Y,
				ol->diffuse.blue * diffuseScale * sunTint.Z);

			static Vector3 maxLight(1.0f, 1.0f, 1.0f);
			diffuse.Cap_Absolute_To(maxLight);

			m_myLight[i]->Set_Ambient( Vector3( 0.0f, 0.0f, 0.0f ) );
			m_myLight[i]->Set_Diffuse(diffuse);
			m_myLight[i]->Set_Specular(diffuse * 0.35f);

			Matrix3D mtx;
			mtx.Set(Vector3(1,0,0), Vector3(0,1,0), Vector3(ol->lightPos.x, ol->lightPos.y, ol->lightPos.z), Vector3(0,0,0));
			m_myLight[i]->Set_Transform(mtx);
		}
	}

	// Re-apply the same stronger key/fill ratio to the live terrain arrays here.
	// Map files can load their own lighting after GlobalData initialization, so
	// doing it at display time guarantees that the terrain actually receives it.
	for (Int i=0; i<MAX_GLOBAL_LIGHTS; ++i)
	{
		TheWritableGlobalData->m_terrainAmbient[i] = TheGlobalData->m_terrainLighting[tod][i].ambient;
		TheWritableGlobalData->m_terrainDiffuse[i] = TheGlobalData->m_terrainLighting[tod][i].diffuse;
		TheWritableGlobalData->m_terrainLightPos[i] = TheGlobalData->m_terrainLighting[tod][i].lightPos;

		TheWritableGlobalData->m_terrainAmbient[i].red *= ambientScale;
		TheWritableGlobalData->m_terrainAmbient[i].green *= ambientScale;
		TheWritableGlobalData->m_terrainAmbient[i].blue *= ambientScale;

		TheWritableGlobalData->m_terrainDiffuse[i].red *= diffuseScale * sunTint.X;
		TheWritableGlobalData->m_terrainDiffuse[i].green *= diffuseScale * sunTint.Y;
		TheWritableGlobalData->m_terrainDiffuse[i].blue *= diffuseScale * sunTint.Z;

		if (TheWritableGlobalData->m_terrainAmbient[i].red > 1.0f) TheWritableGlobalData->m_terrainAmbient[i].red = 1.0f;
		if (TheWritableGlobalData->m_terrainAmbient[i].green > 1.0f) TheWritableGlobalData->m_terrainAmbient[i].green = 1.0f;
		if (TheWritableGlobalData->m_terrainAmbient[i].blue > 1.0f) TheWritableGlobalData->m_terrainAmbient[i].blue = 1.0f;
		if (TheWritableGlobalData->m_terrainDiffuse[i].red > 1.0f) TheWritableGlobalData->m_terrainDiffuse[i].red = 1.0f;
		if (TheWritableGlobalData->m_terrainDiffuse[i].green > 1.0f) TheWritableGlobalData->m_terrainDiffuse[i].green = 1.0f;
		if (TheWritableGlobalData->m_terrainDiffuse[i].blue > 1.0f) TheWritableGlobalData->m_terrainDiffuse[i].blue = 1.0f;
	}

	if(TheTerrainRenderObject) {
		TheTerrainRenderObject->setTimeOfDay(tod);
		TheTacticalView->forceRedraw();
	}
}
'@

$display = Replace-Required $display $old $new "W3DDisplay visible lighting pass"
Set-Content $displayPath $display -Encoding UTF8

# Stronger water response for an obvious water-map test.
$waterPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\Water\W3DWater.cpp"
$water = Get-Content $waterPath -Raw
$water = Replace-Required $water "#define REFLECTION_FACTOR 0.32f" "#define REFLECTION_FACTOR 0.55f" "water reflection factor"
$water = Replace-Required $water "#define SEA_BUMP_SCALE		(0.095f)" "#define SEA_BUMP_SCALE		(0.125f)" "water bump scale"
Set-Content $waterPath $water -Encoding UTF8

Write-Host "Revolution renderer Phase 5 visible lighting pass applied."
