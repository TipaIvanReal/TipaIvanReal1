$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")
$heightPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\HeightMap.cpp"
$height = Get-Content $heightPath -Raw

function Replace-Required([string]$text, [string]$old, [string]$new, [string]$label)
{
    if (-not $text.Contains($old)) {
        throw "Phase 6 patch point not found: $label"
    }
    return $text.Replace($old, $new)
}

$oldInclude = @'
#include <stdlib.h>
'@
$newInclude = @'
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
'@
$height = Replace-Required $height $oldInclude $newInclude "HeightMap includes"

$anchor = @'
static ShaderClass detailOpaqueShader(SC_DETAIL_BLEND);

#define DEFAULT_MAX_FRAME_EXTRABLEND_TILES
'@

$shaderCode = @'
static ShaderClass detailOpaqueShader(SC_DETAIL_BLEND);

// -----------------------------------------------------------------------------
// Revolution Project - programmable terrain material prototype.
// This is installed at the actual HeightMap draw point, so map lighting cannot
// silently bypass it. The legacy terrain atlas is sampled three times. Two
// neighbouring samples form a luminance gradient that behaves like a procedural
// micro-normal and is combined with the original vertex lighting.
// -----------------------------------------------------------------------------
static DWORD g_revolutionTerrainPS = 0;
static IDirect3DDevice8 *g_revolutionTerrainPSDevice = nullptr;
static Bool g_revolutionTerrainLogged = FALSE;
static Bool g_revolutionTerrainAssemblyFailed = FALSE;

static void RevolutionTerrainLog(const char *message)
{
	FILE *log = nullptr;
	if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
	{
		fprintf(log, "RevolutionTerrainShader: %s\n", message);
		fclose(log);
	}
}

static Bool RevolutionEnsureTerrainPixelShader()
{
	IDirect3DDevice8 *dev = DX8Wrapper::_Get_D3D_Device8();
	if (!dev)
		return FALSE;
	if (g_revolutionTerrainAssemblyFailed)
		return FALSE;

	if (g_revolutionTerrainPS && g_revolutionTerrainPSDevice == dev)
	{
		if (SUCCEEDED(dev->SetPixelShader(g_revolutionTerrainPS)))
		{
			dev->SetPixelShader(0);
			return TRUE;
		}
		g_revolutionTerrainPS = 0;
	}

	static const char shaderSource[] =
		"ps.1.1\n"
		"tex t0\n"
		"tex t1\n"
		"tex t2\n"
		"mul r0, v0, t0\n"
		"sub r1, t1, t2\n"
		"mad r0.rgb, r1, c0, r0\n"
		"mul r0.rgb, r0, c1\n";

	LPD3DXBUFFER code = nullptr;
	LPD3DXBUFFER errors = nullptr;
	HRESULT hr = D3DXAssembleShader(shaderSource, (UINT)strlen(shaderSource), 0, nullptr, &code, &errors);

	if (FAILED(hr) || !code)
	{
		if (errors)
		{
			const char *assemblerError = (const char *)errors->GetBufferPointer();
			OutputDebugStringA(assemblerError);
			if (assemblerError)
				RevolutionTerrainLog(assemblerError);
			errors->Release();
		}
		if (code)
			code->Release();
		RevolutionTerrainLog("assembly failed");
		g_revolutionTerrainAssemblyFailed = TRUE;
		return FALSE;
	}

	DWORD handle = 0;
	hr = dev->CreatePixelShader((const DWORD *)code->GetBufferPointer(), &handle);
	code->Release();
	if (errors)
		errors->Release();

	if (FAILED(hr) || !handle)
	{
		RevolutionTerrainLog("CreatePixelShader failed");
		return FALSE;
	}

	g_revolutionTerrainPS = handle;
	g_revolutionTerrainPSDevice = dev;
	return TRUE;
}

static Bool RevolutionSetTerrainMaterial(TextureClass *baseTexture)
{
	if (!baseTexture || !baseTexture->Peek_D3D_Texture())
		return FALSE;
	if (!RevolutionEnsureTerrainPixelShader())
		return FALSE;

	IDirect3DDevice8 *dev = DX8Wrapper::_Get_D3D_Device8();
	if (!dev)
		return FALSE;

	D3DSURFACE_DESC desc;
	if (FAILED(baseTexture->Peek_D3D_Texture()->GetLevelDesc(0, &desc)) || desc.Width == 0 || desc.Height == 0)
		return FALSE;

	const float du = 3.0f / (float)desc.Width;
	const float dv = 3.0f / (float)desc.Height;

	D3DXMATRIX plusOffset;
	D3DXMATRIX minusOffset;
	D3DXMatrixIdentity(&plusOffset);
	D3DXMatrixIdentity(&minusOffset);
	plusOffset._31 = du;
	plusOffset._32 = -dv;
	minusOffset._31 = -du;
	minusOffset._32 = dv;

	DX8Wrapper::Set_Texture(0, baseTexture);
	DX8Wrapper::Set_Texture(1, baseTexture);
	DX8Wrapper::Set_Texture(2, baseTexture);
	DX8Wrapper::Set_Texture(3, nullptr);
	DX8Wrapper::Apply_Render_State_Changes();

	dev->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, 0);
	dev->SetTextureStageState(1, D3DTSS_TEXCOORDINDEX, 0);
	dev->SetTextureStageState(2, D3DTSS_TEXCOORDINDEX, 0);

	dev->SetTextureStageState(0, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
	dev->SetTextureStageState(1, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT2);
	dev->SetTextureStageState(2, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_COUNT2);
	dev->SetTransform(D3DTS_TEXTURE1, &plusOffset);
	dev->SetTransform(D3DTS_TEXTURE2, &minusOffset);

	for (DWORD stage = 0; stage < 3; ++stage)
	{
		dev->SetTextureStageState(stage, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
		dev->SetTextureStageState(stage, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);
		dev->SetTextureStageState(stage, D3DTSS_MINFILTER, D3DTEXF_ANISOTROPIC);
		dev->SetTextureStageState(stage, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
		dev->SetTextureStageState(stage, D3DTSS_MIPFILTER, D3DTEXF_LINEAR);
		dev->SetTextureStageState(stage, D3DTSS_MAXANISOTROPY, 16);
	}

	// c0 strongly converts the two shifted samples into visible micro-relief.
	// c1 gives a slightly warm material response so activation is obvious.
	dev->SetPixelShaderConstant(0, D3DXVECTOR4(3.25f, 3.25f, 3.25f, 0.0f), 1);
	dev->SetPixelShaderConstant(1, D3DXVECTOR4(1.18f, 1.06f, 0.92f, 1.0f), 1);

	if (FAILED(dev->SetPixelShader(g_revolutionTerrainPS)))
	{
		g_revolutionTerrainPS = 0;
		RevolutionTerrainLog("SetPixelShader failed");
		return FALSE;
	}

	if (!g_revolutionTerrainLogged)
	{
		char message[128];
		sprintf_s(message, "ACTIVE Phase6.3 atlas=%ux%u", (unsigned)desc.Width, (unsigned)desc.Height);
		RevolutionTerrainLog(message);
		g_revolutionTerrainLogged = TRUE;
	}
	return TRUE;
}

static void RevolutionResetTerrainMaterial()
{
	IDirect3DDevice8 *dev = DX8Wrapper::_Get_D3D_Device8();
	if (!dev)
		return;

	dev->SetPixelShader(0);
	dev->SetTextureStageState(1, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
	dev->SetTextureStageState(2, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
	dev->SetTexture(1, nullptr);
	dev->SetTexture(2, nullptr);
	DX8Wrapper::Invalidate_Cached_Render_States();
}

#define DEFAULT_MAX_FRAME_EXTRABLEND_TILES
'@

$height = Replace-Required $height $anchor $shaderCode "terrain shader helpers"

$oldSelect = @'
 		//Find number of passes required to render current shader
 		devicePasses=W3DShaderManager::getShaderPasses(st);

 		if (m_disableTextures)
 			devicePasses=1;	//force to 1 lighting-only pass

 		//Specify all textures that this shader may need.
'@

$newSelect = @'
 		revolutionTerrainMaterial =
 			!ShaderClass::Is_Backface_Culling_Inverted() &&
 			!m_disableTextures &&
 			RevolutionEnsureTerrainPixelShader();

 		devicePasses = revolutionTerrainMaterial ? 1 : W3DShaderManager::getShaderPasses(st);

 		if (m_disableTextures)
 			devicePasses=1;	//force to 1 lighting-only pass

 		//Specify all textures that this shader may need.
'@

$height = Replace-Required $height "`tBool doMultiPassWireFrame=FALSE;" "`tBool doMultiPassWireFrame=FALSE;`r`n`tBool revolutionTerrainMaterial=FALSE;" "terrain material scope"

$height = Replace-Required $height $oldSelect $newSelect "terrain pass selection"

$oldPass = @'
 			if (m_disableTextures ) {
 				DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaque2DShader);
 				DX8Wrapper::Set_Texture(0,nullptr);
   			} else {
 				W3DShaderManager::setShader(st, pass);
			}
'@

$newPass = @'
 			if (m_disableTextures ) {
 				DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaque2DShader);
 				DX8Wrapper::Set_Texture(0,nullptr);
   			} else if (revolutionTerrainMaterial) {
				DX8Wrapper::Set_Shader(m_shaderClass);
				DX8Wrapper::Apply_Render_State_Changes();
				if (!RevolutionSetTerrainMaterial(m_stageZeroTexture))
				{
					revolutionTerrainMaterial = FALSE;
					W3DShaderManager::setShader(W3DShaderManager::ST_TERRAIN_BASE, 0);
				}
   			} else {
 				W3DShaderManager::setShader(st, pass);
			}
'@

$height = Replace-Required $height $oldPass $newPass "terrain material install"

$oldReset = @'
		if (pass)	//shader was applied at least once?
 			W3DShaderManager::resetShader(st);

		//Draw feathered shorelines
'@

$newReset = @'
		if (revolutionTerrainMaterial)
		{
			RevolutionResetTerrainMaterial();
		}
		else if (pass)	//shader was applied at least once?
		{
 			W3DShaderManager::resetShader(st);
		}

		//Draw feathered shorelines
'@

$height = Replace-Required $height $oldReset $newReset "terrain material reset"

Set-Content $heightPath $height -Encoding UTF8
Write-Host "Revolution renderer Phase 6.3 minimal programmable terrain material applied."
