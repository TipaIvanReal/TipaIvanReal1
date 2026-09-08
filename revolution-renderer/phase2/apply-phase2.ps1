$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..\..\engine")
$shaderPath = Join-Path $root "Core\GameEngineDevice\Source\W3DDevice\GameClient\W3DShaderManager.cpp"
$shader = Get-Content $shaderPath -Raw

function Replace-Required([string]$text, [string]$old, [string]$new, [string]$label)
{
    if (-not $text.Contains($old)) {
        throw "Phase 2 patch point not found: $label"
    }
    return $text.Replace($old, $new)
}

$oldClass = @'
class ScreenDefaultFilter : public W3DFilterInterface
{
public:
	virtual Int init() override;			///<perform any one time initialization and validation
	virtual Bool preRender(Bool &skipRender, CustomScenePassModes &scenePassMode) override; ///< Set up at start of render.  Only applies to screen filter shaders.
	virtual Bool postRender(FilterModes mode, Coord2D &scrollDelta,Bool &doExtraRender) override; ///< Called after render.  Only applies to screen filter shaders.
	virtual Bool setup(FilterModes mode) override {return true;} ///< Called when the filter is started, one time before the first prerender.
protected:
	virtual Int set(FilterModes mode) override;		///<setup shader for the specified rendering pass.
	virtual void reset() override;		///<do any custom resetting necessary to bring W3D in sync.
};
'@

$newClass = @'
class ScreenDefaultFilter : public W3DFilterInterface
{
public:
	ScreenDefaultFilter() : m_dwGradePixelShader(0), m_dwBloomPixelShader(0) {}
	virtual Int init() override;			///<perform any one time initialization and validation
	virtual Int shutdown() override;
	virtual Bool preRender(Bool &skipRender, CustomScenePassModes &scenePassMode) override; ///< Set up at start of render.  Only applies to screen filter shaders.
	virtual Bool postRender(FilterModes mode, Coord2D &scrollDelta,Bool &doExtraRender) override; ///< Called after render.  Only applies to screen filter shaders.
	virtual Bool setup(FilterModes mode) override {return true;} ///< Called when the filter is started, one time before the first prerender.
protected:
	virtual Int set(FilterModes mode) override;		///<setup shader for the specified rendering pass.
	virtual void reset() override;		///<do any custom resetting necessary to bring W3D in sync.
	DWORD m_dwGradePixelShader;
	DWORD m_dwBloomPixelShader;
};
'@

$shader = Replace-Required $shader $oldClass $newClass "ScreenDefaultFilter class"

$oldInitTail = @'
	W3DFilters[FT_VIEW_DEFAULT]=&screenDefaultFilter;

	return TRUE;
}

Bool ScreenDefaultFilter::preRender(Bool &skipRender, CustomScenePassModes &scenePassMode)
{
	// TheSuperHackers @bugfix Disable Render To Texture redirection for the default filter
	// When MSAA is forced by Nvidia driver profile depth buffer is multisampled internally.
	// Rendering to non-MSAA texture with this depth buffer corrupts depth testing producing black screen
	// The smudge system has its own Copy path that works without Render To Texture.
	return FALSE;
}
'@

$newInitTail = @'
	W3DFilters[FT_VIEW_DEFAULT]=&screenDefaultFilter;

	// Revolution Project: cinematic post processing for the always-on default view.
	// Keep this on Shader Model 1.1 so the legacy WW3D path remains broadly compatible.
	if (W3DShaderManager::getChipset() >= DC_GENERIC_PIXEL_SHADER_1_1)
	{
		ID3DXBuffer *compiledShader = nullptr;
		HRESULT hr;

		const char *gradeShader =
			"ps.1.1\n"
			"tex t0\n"
			"dp3 r1.rgb, t0, c2\n"
			"lrp r0.rgb, c3, t0, r1\n"
			"mad_sat r0.rgb, r0, c0, c1\n"
			"mov r0.a, t0\n";

		hr = D3DXAssembleShader(gradeShader, strlen(gradeShader), 0, nullptr, &compiledShader, nullptr);
		if (SUCCEEDED(hr) && compiledShader)
		{
			hr = DX8Wrapper::_Get_D3D_Device8()->CreatePixelShader(
				(DWORD *)compiledShader->GetBufferPointer(), &m_dwGradePixelShader);
			compiledShader->Release();
			compiledShader = nullptr;
		}

		const char *bloomShader =
			"ps.1.1\n"
			"tex t0\n"
			"mad_sat r0, t0, c0, c1\n"
			"mul r0.rgb, r0, c2\n";

		hr = D3DXAssembleShader(bloomShader, strlen(bloomShader), 0, nullptr, &compiledShader, nullptr);
		if (SUCCEEDED(hr) && compiledShader)
		{
			hr = DX8Wrapper::_Get_D3D_Device8()->CreatePixelShader(
				(DWORD *)compiledShader->GetBufferPointer(), &m_dwBloomPixelShader);
			compiledShader->Release();
			compiledShader = nullptr;
		}
	}

	return TRUE;
}

Int ScreenDefaultFilter::shutdown()
{
	LPDIRECT3DDEVICE8 pDev = DX8Wrapper::_Get_D3D_Device8();
	if (pDev)
	{
		if (m_dwGradePixelShader)
			pDev->DeletePixelShader(m_dwGradePixelShader);
		if (m_dwBloomPixelShader)
			pDev->DeletePixelShader(m_dwBloomPixelShader);
	}
	m_dwGradePixelShader = 0;
	m_dwBloomPixelShader = 0;
	return TRUE;
}

Bool ScreenDefaultFilter::preRender(Bool &skipRender, CustomScenePassModes &scenePassMode)
{
	skipRender = false;

	// startRenderToTexture already permanently disables RTT if a forced-MSAA/depth
	// mismatch makes SetRenderTarget fail.  Only report success when redirection
	// actually happened, so the normal scene path remains a safe fallback.
	if (!W3DShaderManager::canRenderToTexture())
		return FALSE;

	W3DShaderManager::startRenderToTexture();
	return W3DShaderManager::isRenderingToTexture();
}
'@

$shader = Replace-Required $shader $oldInitTail $newInitTail "default filter init/preRender"

$oldPost = @'
Bool ScreenDefaultFilter::postRender(FilterModes mode, Coord2D &scrollDelta,Bool &doExtraRender)
{
	IDirect3DTexture8 * tex =	W3DShaderManager::endRenderToTexture();
	DEBUG_ASSERTCRASH(tex, ("Require rendered texture."));
	if (!tex) return false;
	if (!set(mode)) return false;

	LPDIRECT3DDEVICE8 pDev=DX8Wrapper::_Get_D3D_Device8();

	struct _TRANS_LIT_TEX_VERTEX {
		D3DXVECTOR4 p;
		DWORD color;   // diffuse color
		float	u;
		float	v;
	} v[4];

	Int xpos, ypos, width, height;

	DX8Wrapper::_Get_D3D_Device8()->SetTexture(0,tex);	//previously rendered frame inside this texture
	TheTacticalView->getOrigin(&xpos,&ypos);
	width=TheTacticalView->getWidth();
	height=TheTacticalView->getHeight();

	//bottom right
	v[0].p = D3DXVECTOR4( xpos+width-0.5f, ypos+height-0.5f, 0.0f, 1.0f );
	v[0].u = (Real)(xpos+width)/(Real)TheDisplay->getWidth();	v[0].v = (Real)(ypos+height)/(Real)TheDisplay->getHeight();
	//top right
	v[1].p = D3DXVECTOR4( xpos+width-0.5f, ypos-0.5f, 0.0f, 1.0f );
	v[1].u = (Real)(xpos+width)/(Real)TheDisplay->getWidth();	v[1].v = (Real)(ypos)/(Real)TheDisplay->getHeight();
	//bottom left
	v[2].p = D3DXVECTOR4(  xpos-0.5f, ypos+height-0.5f, 0.0f, 1.0f );
	v[2].u = (Real)(xpos)/(Real)TheDisplay->getWidth();	v[2].v = (Real)(ypos+height)/(Real)TheDisplay->getHeight();
	//top left
	v[3].p = D3DXVECTOR4(  xpos-0.5f,  ypos-0.5f, 0.0f, 1.0f );
	v[3].u = (Real)(xpos)/(Real)TheDisplay->getWidth();	v[3].v = (Real)(ypos)/(Real)TheDisplay->getHeight();
	v[0].color = 0xffffffff;
	v[1].color = 0xffffffff;
	v[2].color = 0xffffffff;
	v[3].color = 0xffffffff;

	//draw polygons like this is very inefficient but for only 2 triangles, it's
	//not worth bothering with index/vertex buffers.
	pDev->SetVertexShader(D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1);

	pDev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(_TRANS_LIT_TEX_VERTEX));

	reset();
	return true;
}
'@

$newPost = @'
Bool ScreenDefaultFilter::postRender(FilterModes mode, Coord2D &scrollDelta,Bool &doExtraRender)
{
	IDirect3DTexture8 * tex = W3DShaderManager::endRenderToTexture();
	DEBUG_ASSERTCRASH(tex, ("Require rendered texture."));
	if (!tex) return false;
	if (!set(mode)) return false;

	LPDIRECT3DDEVICE8 pDev = DX8Wrapper::_Get_D3D_Device8();

	struct _TRANS_LIT_TEX_VERTEX {
		D3DXVECTOR4 p;
		DWORD color;
		float u;
		float v;
	} v[4];

	Int xpos, ypos, width, height;
	TheTacticalView->getOrigin(&xpos,&ypos);
	width = TheTacticalView->getWidth();
	height = TheTacticalView->getHeight();

	const Real invW = 1.0f / (Real)TheDisplay->getWidth();
	const Real invH = 1.0f / (Real)TheDisplay->getHeight();

	auto buildQuad = [&](Real offsetX, Real offsetY)
	{
		const Real du = offsetX * invW;
		const Real dv = offsetY * invH;

		v[0].p = D3DXVECTOR4(xpos+width-0.5f, ypos+height-0.5f, 0.0f, 1.0f);
		v[0].u = (Real)(xpos+width) * invW + du; v[0].v = (Real)(ypos+height) * invH + dv;
		v[1].p = D3DXVECTOR4(xpos+width-0.5f, ypos-0.5f, 0.0f, 1.0f);
		v[1].u = (Real)(xpos+width) * invW + du; v[1].v = (Real)ypos * invH + dv;
		v[2].p = D3DXVECTOR4(xpos-0.5f, ypos+height-0.5f, 0.0f, 1.0f);
		v[2].u = (Real)xpos * invW + du; v[2].v = (Real)(ypos+height) * invH + dv;
		v[3].p = D3DXVECTOR4(xpos-0.5f, ypos-0.5f, 0.0f, 1.0f);
		v[3].u = (Real)xpos * invW + du; v[3].v = (Real)ypos * invH + dv;

		v[0].color = v[1].color = v[2].color = v[3].color = 0xffffffff;
	};

	pDev->SetTexture(0, tex);
	pDev->SetVertexShader(D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1);

	// Filmic grade: slightly more local contrast/saturation with a restrained warm bias.
	if (m_dwGradePixelShader)
	{
		const D3DXVECTOR4 contrastWarm(1.085f, 1.065f, 1.035f, 1.0f);
		const D3DXVECTOR4 lift(-0.030f, -0.026f, -0.018f, 0.0f);
		const D3DXVECTOR4 luma(0.299f, 0.587f, 0.114f, 0.0f);
		const D3DXVECTOR4 saturation(1.10f, 1.10f, 1.10f, 1.10f);

		pDev->SetPixelShader(m_dwGradePixelShader);
		pDev->SetPixelShaderConstant(0, &contrastWarm, 1);
		pDev->SetPixelShaderConstant(1, &lift, 1);
		pDev->SetPixelShaderConstant(2, &luma, 1);
		pDev->SetPixelShaderConstant(3, &saturation, 1);
	}

	buildQuad(0.0f, 0.0f);
	pDev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(_TRANS_LIT_TEX_VERTEX));

	// Lightweight highlight bloom.  It only adds pixels above roughly 75% luminance,
	// sampled around the source image, which keeps UI/text much cleaner than a full blur.
	if (m_dwBloomPixelShader)
	{
		const D3DXVECTOR4 thresholdScale(4.0f, 4.0f, 4.0f, 1.0f);
		const D3DXVECTOR4 thresholdBias(-3.0f, -3.0f, -3.0f, 0.0f);
		const D3DXVECTOR4 bloomStrength(0.055f, 0.055f, 0.055f, 1.0f);

		DX8Wrapper::Set_DX8_Render_State(D3DRS_SRCBLEND, D3DBLEND_ONE);
		DX8Wrapper::Set_DX8_Render_State(D3DRS_DESTBLEND, D3DBLEND_ONE);
		DX8Wrapper::Set_DX8_Render_State(D3DRS_ALPHABLENDENABLE, TRUE);
		DX8Wrapper::Apply_Render_State_Changes();

		pDev->SetPixelShader(m_dwBloomPixelShader);
		pDev->SetPixelShaderConstant(0, &thresholdScale, 1);
		pDev->SetPixelShaderConstant(1, &thresholdBias, 1);
		pDev->SetPixelShaderConstant(2, &bloomStrength, 1);

		const Real offsets[8][2] = {
			{-2.0f, 0.0f}, {2.0f, 0.0f}, {0.0f, -2.0f}, {0.0f, 2.0f},
			{-1.4f, -1.4f}, {1.4f, -1.4f}, {-1.4f, 1.4f}, {1.4f, 1.4f}
		};

		for (Int i = 0; i < 8; ++i)
		{
			buildQuad(offsets[i][0], offsets[i][1]);
			pDev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, v, sizeof(_TRANS_LIT_TEX_VERTEX));
		}
	}

	reset();
	return true;
}
'@

$shader = Replace-Required $shader $oldPost $newPost "default filter postRender"

$oldSet = @'
Int ScreenDefaultFilter::set(FilterModes mode)
{
	VertexMaterialClass *vmat=VertexMaterialClass::Get_Preset(VertexMaterialClass::PRELIT_DIFFUSE);
	DX8Wrapper::Set_Material(vmat);
	REF_PTR_RELEASE(vmat);	//no need to keep a reference since it's a preset.
	DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaqueShader);
	DX8Wrapper::Set_Texture(0,nullptr);
	DX8Wrapper::Apply_Render_State_Changes();	//force update of view and projection matrices

	DX8Wrapper::Set_DX8_Render_State(D3DRS_ZFUNC,D3DCMP_ALWAYS);
	DX8Wrapper::Set_DX8_Render_State(D3DRS_ZWRITEENABLE,FALSE);
	DX8Wrapper::Apply_Render_State_Changes();	//force update of view and projection matrices

	return true;
}

void ScreenDefaultFilter::reset()
{
	DX8Wrapper::_Get_D3D_Device8()->SetTexture(0,nullptr);	//previously rendered frame inside this texture
	DX8Wrapper::Invalidate_Cached_Render_States();
}
'@

$newSet = @'
Int ScreenDefaultFilter::set(FilterModes mode)
{
	VertexMaterialClass *vmat=VertexMaterialClass::Get_Preset(VertexMaterialClass::PRELIT_DIFFUSE);
	DX8Wrapper::Set_Material(vmat);
	REF_PTR_RELEASE(vmat);
	DX8Wrapper::Set_Shader(ShaderClass::_PresetOpaqueShader);
	DX8Wrapper::Set_Texture(0,nullptr);
	DX8Wrapper::Apply_Render_State_Changes();

	DX8Wrapper::Set_DX8_Render_State(D3DRS_ZFUNC,D3DCMP_ALWAYS);
	DX8Wrapper::Set_DX8_Render_State(D3DRS_ZWRITEENABLE,FALSE);
	DX8Wrapper::Set_DX8_Render_State(D3DRS_ALPHABLENDENABLE,FALSE);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_MINFILTER, D3DTEXF_LINEAR);
	DX8Wrapper::Set_DX8_Texture_Stage_State(0, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
	DX8Wrapper::Apply_Render_State_Changes();

	return true;
}

void ScreenDefaultFilter::reset()
{
	LPDIRECT3DDEVICE8 pDev = DX8Wrapper::_Get_D3D_Device8();
	pDev->SetPixelShader(0);
	pDev->SetTexture(0,nullptr);
	DX8Wrapper::Invalidate_Cached_Render_States();
}
'@

$shader = Replace-Required $shader $oldSet $newSet "default filter set/reset"

Set-Content $shaderPath $shader -Encoding UTF8
Write-Host "Revolution renderer Phase 2 cinematic post-processing patch applied."
