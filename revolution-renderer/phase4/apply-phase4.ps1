$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")

function Replace-Required([string]$text, [string]$old, [string]$new, [string]$label)
{
    if (-not $text.Contains($old)) {
        throw "Phase 4 patch point not found: $label"
    }
    return $text.Replace($old, $new)
}

# ---------------------------------------------------------------------------
# Terrain lighting: reduce flat ambient fill and strengthen directional light.
# This makes terrain relief, cliffs and object silhouettes read much more clearly.
# ---------------------------------------------------------------------------
$globalPath = Join-Path $root "GeneralsMD\Code\GameEngine\Source\Common\GlobalData.cpp"
$global = Get-Content $globalPath -Raw

$oldGlobal = @'
	m_timeOfDay = tod;
	for (Int i=0; i<MAX_GLOBAL_LIGHTS; i++)
	{	m_terrainAmbient[i] = m_terrainLighting[ tod ][i].ambient;
		m_terrainDiffuse[i] = m_terrainLighting[ tod ][i].diffuse;
		m_terrainLightPos[i] = m_terrainLighting[ tod ][i].lightPos;
	}

	return TRUE;
'@

$newGlobal = @'
	m_timeOfDay = tod;

	const auto clamp01 = [](Real v) -> Real
	{
		if (v < 0.0f) return 0.0f;
		if (v > 1.0f) return 1.0f;
		return v;
	};

	Real ambientScale = 0.72f;
	Real diffuseScale = 1.28f;
	Real sunR = 1.05f;
	Real sunG = 1.00f;
	Real sunB = 0.94f;

	if (tod == TIME_OF_DAY_MORNING)
	{
		ambientScale = 0.76f;
		diffuseScale = 1.22f;
		sunR = 1.08f; sunG = 1.01f; sunB = 0.91f;
	}
	else if (tod == TIME_OF_DAY_EVENING)
	{
		ambientScale = 0.70f;
		diffuseScale = 1.20f;
		sunR = 1.10f; sunG = 0.98f; sunB = 0.88f;
	}
	else if (tod == TIME_OF_DAY_NIGHT)
	{
		ambientScale = 0.88f;
		diffuseScale = 1.08f;
		sunR = 0.88f; sunG = 0.96f; sunB = 1.12f;
	}

	for (Int i=0; i<MAX_GLOBAL_LIGHTS; i++)
	{
		m_terrainAmbient[i] = m_terrainLighting[ tod ][i].ambient;
		m_terrainDiffuse[i] = m_terrainLighting[ tod ][i].diffuse;
		m_terrainLightPos[i] = m_terrainLighting[ tod ][i].lightPos;

		m_terrainAmbient[i].red   = clamp01(m_terrainAmbient[i].red   * ambientScale);
		m_terrainAmbient[i].green = clamp01(m_terrainAmbient[i].green * ambientScale);
		m_terrainAmbient[i].blue  = clamp01(m_terrainAmbient[i].blue  * ambientScale);

		m_terrainDiffuse[i].red   = clamp01(m_terrainDiffuse[i].red   * diffuseScale * sunR);
		m_terrainDiffuse[i].green = clamp01(m_terrainDiffuse[i].green * diffuseScale * sunG);
		m_terrainDiffuse[i].blue  = clamp01(m_terrainDiffuse[i].blue  * diffuseScale * sunB);
	}

	return TRUE;
'@

$global = Replace-Required $global $oldGlobal $newGlobal "GlobalData terrain lighting"
Set-Content $globalPath $global -Encoding UTF8

# ---------------------------------------------------------------------------
# Object lighting: matching cinematic key/fill ratio and a real specular term.
# ---------------------------------------------------------------------------
$displayPath = Join-Path $root "GeneralsMD\Code\GameEngineDevice\Source\W3DDevice\GameClient\W3DDisplay.cpp"
$display = Get-Content $displayPath -Raw

$oldDisplay = @'
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

$newDisplay = @'
void W3DDisplay::setTimeOfDay( TimeOfDay tod )
{
	const GlobalData::TerrainLighting *ol=&TheGlobalData->m_terrainObjectsLighting[tod][0];

	Real ambientScale = 0.72f;
	Real diffuseScale = 1.28f;
	Vector3 sunTint(1.05f, 1.00f, 0.94f);

	if (tod == TIME_OF_DAY_MORNING)
	{
		ambientScale = 0.76f;
		diffuseScale = 1.22f;
		sunTint.Set(1.08f, 1.01f, 0.91f);
	}
	else if (tod == TIME_OF_DAY_EVENING)
	{
		ambientScale = 0.70f;
		diffuseScale = 1.20f;
		sunTint.Set(1.10f, 0.98f, 0.88f);
	}
	else if (tod == TIME_OF_DAY_NIGHT)
	{
		ambientScale = 0.88f;
		diffuseScale = 1.08f;
		sunTint.Set(0.88f, 0.96f, 1.12f);
	}

	if( m_3DScene )
	{
		Vector3 ambient(
			ol->ambient.red * ambientScale,
			ol->ambient.green * ambientScale,
			ol->ambient.blue * ambientScale);
		ambient.Cap_Absolute_To(Vector3(1.0f, 1.0f, 1.0f));
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
			diffuse.Cap_Absolute_To(Vector3(1.0f, 1.0f, 1.0f));

			m_myLight[i]->Set_Ambient( Vector3( 0.0f, 0.0f, 0.0f ) );
			m_myLight[i]->Set_Diffuse(diffuse);
			m_myLight[i]->Set_Specular(diffuse * 0.22f);

			Matrix3D mtx;
			mtx.Set(Vector3(1,0,0), Vector3(0,1,0), Vector3(ol->lightPos.x, ol->lightPos.y, ol->lightPos.z), Vector3(0,0,0));
			m_myLight[i]->Set_Transform(mtx);
		}
	}

	DX8Wrapper::Set_DX8_Render_State(D3DRS_SPECULARENABLE, TRUE);

	if(TheTerrainRenderObject) {
		TheTerrainRenderObject->setTimeOfDay(tod);
		TheTacticalView->forceRedraw();
	}
}
'@

$display = Replace-Required $display $oldDisplay $newDisplay "W3DDisplay object lighting"
Set-Content $displayPath $display -Encoding UTF8

# ---------------------------------------------------------------------------
# Shadows: stronger, cooler contact contrast. Projected decals get linear filtering.
# ---------------------------------------------------------------------------
$shadowPath = Join-Path $root "GeneralsMD\Code\GameEngineDevice\Source\W3DDevice\GameClient\Shadow\W3DShadow.cpp"
$shadow = Get-Content $shadowPath -Raw
$shadow = Replace-Required $shadow "m_shadowColor = 0x7fa0a0a0;" "m_shadowColor = 0xff88929c;" "shadow color"
Set-Content $shadowPath $shadow -Encoding UTF8

$projectedPath = Join-Path $root "GeneralsMD\Code\GameEngineDevice\Source\W3DDevice\GameClient\Shadow\W3DProjectedShadow.cpp"
$projected = Get-Content $projectedPath -Raw
$oldProjected = @'
	DX8Wrapper::Set_Texture(0,texture->getTexture());

//	DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaqueShader);	//good for debugging, draws without alpha
'@
$newProjected = @'
	DX8Wrapper::Set_Texture(0,texture->getTexture());
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_MIPFILTER, D3DTEXF_LINEAR);

//	DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaqueShader);	//good for debugging, draws without alpha
'@
$projected = Replace-Required $projected $oldProjected $newProjected "projected shadow filtering"
Set-Content $projectedPath $projected -Encoding UTF8

# ---------------------------------------------------------------------------
# Water: higher-frequency waves and much stronger physically-readable reflection.
# Phase 1 already increases reflection RT from 256 to 1024.
# ---------------------------------------------------------------------------
$waterPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\Water\W3DWater.cpp"
$water = Get-Content $waterPath -Raw
$water = Replace-Required $water "#define SEA_BUMP_SCALE		(0.06f)" "#define SEA_BUMP_SCALE		(0.095f)" "water bump scale"
$water = Replace-Required $water "#define REFLECTION_FACTOR 0.1f" "#define REFLECTION_FACTOR 0.32f" "water reflection factor"
$water = Replace-Required $water "#define WATER_MESH_OPACITY		0.5f" "#define WATER_MESH_OPACITY		0.64f" "water opacity"
$water = Replace-Required $water "m_meshVertexMaterialClass->Set_Shininess(20.0);" "m_meshVertexMaterialClass->Set_Shininess(48.0);" "water shininess"
$water = Replace-Required $water "m_meshVertexMaterialClass->Set_Specular(0.5,0.5,0.5);" "m_meshVertexMaterialClass->Set_Specular(0.9,0.9,0.9);" "water specular"
Set-Content $waterPath $water -Encoding UTF8

Write-Host "Revolution renderer Phase 4 lighting/shadows/water patch applied."
