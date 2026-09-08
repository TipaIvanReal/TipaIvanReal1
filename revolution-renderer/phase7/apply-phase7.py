from pathlib import Path
import re
import shutil

root = (Path(__file__).resolve().parents[2] / "engine").resolve()

def replace_required(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise RuntimeError(f"Phase 7 patch point not found: {label}")
    return text.replace(old, new)

# Install helper files.
include_dir = root / "Core/GameEngineDevice/Include/W3DDevice/GameClient"
source_dir = root / "Core/GameEngineDevice/Source/W3DDevice/GameClient"
phase_dir = Path(__file__).resolve().parent

shutil.copy2(phase_dir / "RevolutionTerrainImageLoader.h", include_dir / "RevolutionTerrainImageLoader.h")
shutil.copy2(phase_dir / "RevolutionTerrainMaterialTexture.h", include_dir / "RevolutionTerrainMaterialTexture.h")
shutil.copy2(phase_dir / "RevolutionTerrainImageLoader.cpp", source_dir / "RevolutionTerrainImageLoader.cpp")
shutil.copy2(phase_dir / "RevolutionTerrainMaterialTexture.cpp", source_dir / "RevolutionTerrainMaterialTexture.cpp")

# CMake sources + WIC.
cmake_path = root / "Core/GameEngineDevice/CMakeLists.txt"
cmake = cmake_path.read_text(encoding="utf-8")

cmake = replace_required(
    cmake,
    "    Include/W3DDevice/GameClient/TerrainTex.h\n    Include/W3DDevice/GameClient/TileData.h",
    "    Include/W3DDevice/GameClient/TerrainTex.h\n"
    "    Include/W3DDevice/GameClient/RevolutionTerrainImageLoader.h\n"
    "    Include/W3DDevice/GameClient/RevolutionTerrainMaterialTexture.h\n"
    "    Include/W3DDevice/GameClient/TileData.h",
    "terrain helper headers",
)
cmake = replace_required(
    cmake,
    "    Source/W3DDevice/GameClient/TerrainTex.cpp\n    Source/W3DDevice/GameClient/TileData.cpp",
    "    Source/W3DDevice/GameClient/TerrainTex.cpp\n"
    "    Source/W3DDevice/GameClient/RevolutionTerrainImageLoader.cpp\n"
    "    Source/W3DDevice/GameClient/RevolutionTerrainMaterialTexture.cpp\n"
    "    Source/W3DDevice/GameClient/TileData.cpp",
    "terrain helper sources",
)
cmake = replace_required(
    cmake,
    "    corei_main\n    stb\n)",
    "    corei_main\n    stb\n    ole32\n    windowscodecs\n)",
    "WIC libraries",
)
cmake_path.write_text(cmake, encoding="utf-8")

# WorldHeightMap class additions.
world_h_path = root / "Core/GameEngineDevice/Include/W3DDevice/GameClient/WorldHeightMap.h"
world_h = world_h_path.read_text(encoding="utf-8")

world_h = replace_required(
    world_h,
    "class TerrainTextureClass;\nclass AlphaTerrainTextureClass;",
    "class TerrainTextureClass;\nclass RevolutionTerrainMaterialTextureClass;\nclass AlphaTerrainTextureClass;",
    "material forward declaration",
)
world_h = replace_required(
    world_h,
    "\tfriend class TerrainTextureClass;\n\tfriend class AlphaTerrainTextureClass;",
    "\tfriend class TerrainTextureClass;\n\tfriend class RevolutionTerrainMaterialTextureClass;\n\tfriend class AlphaTerrainTextureClass;",
    "material friend",
)
world_h = replace_required(
    world_h,
    "\tTileData\t\t\t*m_sourceTiles[NUM_SOURCE_TILES];\t///< Tiles for m_textureClasses\n"
    "\tTileData\t\t\t*m_edgeTiles[NUM_SOURCE_TILES];\t///< Tiles for m_textureClasses",
    "\tTileData\t\t\t*m_sourceTiles[NUM_SOURCE_TILES];\t///< Diffuse tiles\n"
    "\tTileData\t\t\t*m_normalTiles[NUM_SOURCE_TILES];\t///< Optional *_N normal tiles\n"
    "\tTileData\t\t\t*m_heightTiles[NUM_SOURCE_TILES];\t///< Optional *_H height tiles\n"
    "\tTileData\t\t\t*m_roughnessTiles[NUM_SOURCE_TILES];\t///< Optional *_R roughness tiles\n"
    "\tTileData\t\t\t*m_edgeTiles[NUM_SOURCE_TILES];\t///< Tiles for m_textureClasses",
    "material tile arrays",
)
world_h = replace_required(
    world_h,
    "\tTerrainTextureClass *m_terrainTex;\n\tInt\tm_terrainTexHeight;",
    "\tTerrainTextureClass *m_terrainTex;\n"
    "\tRevolutionTerrainMaterialTextureClass *m_terrainMaterialTex;\n"
    "\tInt\tm_terrainTexHeight;",
    "material atlas member",
)
world_h = replace_required(
    world_h,
    "\tTextureClass *getTerrainTexture();  //< generates if needed and returns the terrain texture\n"
    "\tTextureClass *getAlphaTerrainTexture();",
    "\tTextureClass *getTerrainTexture();  //< generates if needed and returns the terrain texture\n"
    "\tTextureClass *getTerrainMaterialTexture(); //< packed terrain normal material atlas\n"
    "\tTextureClass *getAlphaTerrainTexture();",
    "material atlas getter",
)
world_h_path.write_text(world_h, encoding="utf-8")

# WorldHeightMap source.
world_cpp_path = root / "Core/GameEngineDevice/Source/W3DDevice/GameClient/WorldHeightMap.cpp"
world = world_cpp_path.read_text(encoding="utf-8")

world = replace_required(
    world,
    '#include "W3DDevice/GameClient/TerrainTex.h"',
    '#include "W3DDevice/GameClient/TerrainTex.h"\n'
    '#include "W3DDevice/GameClient/RevolutionTerrainImageLoader.h"\n'
    '#include "W3DDevice/GameClient/RevolutionTerrainMaterialTexture.h"',
    "terrain helper includes",
)

world = replace_required(
    world,
    "\tfor (i=0; i<NUM_SOURCE_TILES; i++) {\n"
    "\t\tREF_PTR_RELEASE(m_sourceTiles[i]);\n"
    "\t\tREF_PTR_RELEASE(m_edgeTiles[i]);\n"
    "\t}",
    "\tfor (i=0; i<NUM_SOURCE_TILES; i++) {\n"
    "\t\tREF_PTR_RELEASE(m_sourceTiles[i]);\n"
    "\t\tREF_PTR_RELEASE(m_normalTiles[i]);\n"
    "\t\tREF_PTR_RELEASE(m_heightTiles[i]);\n"
    "\t\tREF_PTR_RELEASE(m_roughnessTiles[i]);\n"
    "\t\tREF_PTR_RELEASE(m_edgeTiles[i]);\n"
    "\t}",
    "release material tiles",
)
world = replace_required(
    world,
    "\tREF_PTR_RELEASE(m_terrainTex);\n\tREF_PTR_RELEASE(m_alphaTerrainTex);",
    "\tREF_PTR_RELEASE(m_terrainTex);\n"
    "\tREF_PTR_RELEASE(m_terrainMaterialTex);\n"
    "\tREF_PTR_RELEASE(m_alphaTerrainTex);",
    "release material atlas",
)
world = world.replace(
    "m_terrainTex(nullptr), m_alphaTerrainTex(nullptr), m_numBitmapTiles(0), m_numBlendedTiles(1)",
    "m_terrainTex(nullptr), m_terrainMaterialTex(nullptr), m_alphaTerrainTex(nullptr), m_numBitmapTiles(0), m_numBlendedTiles(1)",
)
world = world.replace(
    "\t\tm_sourceTiles[i] = nullptr;\n\t\tm_edgeTiles[i] = nullptr;",
    "\t\tm_sourceTiles[i] = nullptr;\n"
    "\t\tm_normalTiles[i] = nullptr;\n"
    "\t\tm_heightTiles[i] = nullptr;\n"
    "\t\tm_roughnessTiles[i] = nullptr;\n"
    "\t\tm_edgeTiles[i] = nullptr;",
)
world = world.replace(
    "\t\tm_sourceTiles[i]=nullptr;\n\t\tm_edgeTiles[i]=nullptr;",
    "\t\tm_sourceTiles[i]=nullptr;\n"
    "\t\tm_normalTiles[i]=nullptr;\n"
    "\t\tm_heightTiles[i]=nullptr;\n"
    "\t\tm_roughnessTiles[i]=nullptr;\n"
    "\t\tm_edgeTiles[i]=nullptr;",
)

new_read = r'''void WorldHeightMap::readTexClass(TXTextureClass *texClass, TileData **tileData)
{
	if (!texClass || !tileData)
		return;

	TerrainType *terrain = TheTerrainTypes->findTerrain(texClass->name);
	char texturePath[_MAX_PATH] = { 0 };

	if (terrain == nullptr)
	{
#ifdef LOAD_TEST_ASSETS
		snprintf(texturePath, ARRAY_SIZE(texturePath), "%s", texClass->name.str());
#else
		return;
#endif
	}
	else
	{
		snprintf(texturePath, ARRAY_SIZE(texturePath), "%s%s", TERRAIN_TGA_DIR_PATH, terrain->getTexture().str());
	}

	const Int logicalRows = texClass->width;
	RevolutionTerrainImageInfo info;

	if (!RevolutionLoadTerrainSheet(texturePath, tileData, texClass->firstTile, logicalRows, REV_TERRAIN_DIFFUSE, &info))
	{
		FILE *log = nullptr;
		if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
		{
			fprintf(log, "RevolutionTerrainAssets: FAILED diffuse %s logical=%dx%d\n", texturePath, logicalRows, logicalRows);
			fclose(log);
		}
		return;
	}

	{
		FILE *log = nullptr;
		if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
		{
			fprintf(log, "RevolutionTerrainAssets: diffuse %s source=%dx%d logical=%dx%d\n",
				texturePath, info.width, info.height, logicalRows, logicalRows);
			fclose(log);
		}
	}

	if (tileData != m_sourceTiles)
		return;

	char resolved[_MAX_PATH] = { 0 };

	if (RevolutionLoadTerrainCompanion(texturePath, "_N", m_normalTiles, texClass->firstTile, logicalRows,
		REV_TERRAIN_NORMAL, &info, resolved, ARRAY_SIZE(resolved)))
	{
		FILE *log = nullptr;
		if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
		{
			fprintf(log, "RevolutionTerrainAssets: normal %s source=%dx%d\n", resolved, info.width, info.height);
			fclose(log);
		}
	}

	if (RevolutionLoadTerrainCompanion(texturePath, "_H", m_heightTiles, texClass->firstTile, logicalRows,
		REV_TERRAIN_HEIGHT, &info, resolved, ARRAY_SIZE(resolved)))
	{
		FILE *log = nullptr;
		if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
		{
			fprintf(log, "RevolutionTerrainAssets: height %s source=%dx%d\n", resolved, info.width, info.height);
			fclose(log);
		}
	}

	if (RevolutionLoadTerrainCompanion(texturePath, "_R", m_roughnessTiles, texClass->firstTile, logicalRows,
		REV_TERRAIN_ROUGHNESS, &info, resolved, ARRAY_SIZE(resolved)))
	{
		FILE *log = nullptr;
		if (fopen_s(&log, "RevolutionRenderer.log", "a") == 0 && log)
		{
			fprintf(log, "RevolutionTerrainAssets: roughness %s source=%dx%d\n", resolved, info.width, info.height);
			fclose(log);
		}
	}
}

'''

pattern = re.compile(
    r"void WorldHeightMap::readTexClass\(TXTextureClass \*texClass, TileData \*\*tileData\)\s*\{.*?(?=/\*\*\s*\* WorldHeightMap::ParseBlendTileData)",
    re.S,
)
if not pattern.search(world):
    raise RuntimeError("Phase 7 patch point not found: readTexClass")
world = pattern.sub(new_read, world, count=1)

world = replace_required(
    world,
    "\t\tm_terrainTexHeight = m_terrainTex->update(this);\n\t\tchar buf[64];",
    "\t\tm_terrainTexHeight = m_terrainTex->update(this);\n"
    "\t\tREF_PTR_RELEASE(m_terrainMaterialTex);\n"
    "\t\tchar buf[64];",
    "invalidate material atlas",
)

material_getter = r'''TextureClass *WorldHeightMap::getTerrainMaterialTexture()
{
	if (m_terrainTex == nullptr)
		getTerrainTexture();

	if (m_terrainMaterialTex == nullptr && m_terrainTexHeight > 0)
	{
		m_terrainMaterialTex = MSGNEW("WorldHeightMap_getTerrainMaterialTexture") RevolutionTerrainMaterialTextureClass(m_terrainTexHeight);
		m_terrainMaterialTex->update(this);
	}
	return m_terrainMaterialTex;
}

'''
world = replace_required(
    world,
    "TextureClass *WorldHeightMap::getAlphaTerrainTexture()\n",
    material_getter + "TextureClass *WorldHeightMap::getAlphaTerrainTexture()\n",
    "material getter implementation",
)

world_cpp_path.write_text(world, encoding="utf-8")

# Upgrade the Phase 6.4 shader to use material maps.
height_path = root / "Core/GameEngineDevice/Source/W3DDevice/GameClient/HeightMap.cpp"
height = height_path.read_text(encoding="utf-8")

old_shader = '''\tstatic const char shaderSource[] =
\t\t"ps.1.1\\n"
\t\t"tex t0\\n"
\t\t"tex t1\\n"
\t\t"sub r1, c0, v0.a\\n"
\t\t"mul r0, t0, r1\\n"
\t\t"mad r0, t1, v0.a, r0\\n"
\t\t"mul r0.rgb, r0, v0\\n"
\t\t"mad_sat r0.rgb, r0, c1, c2\\n";
'''
new_shader = '''\tstatic const char shaderSource[] =
\t\t"ps.1.1\\n"
\t\t"tex t0\\n"
\t\t"tex t1\\n"
\t\t"tex t2\\n"
\t\t"tex t3\\n"
\t\t"sub r1, c0, v0.a\\n"
\t\t"mul r0, t0, r1\\n"
\t\t"mad r0, t1, v0.a, r0\\n"
\t\t"mul r0.rgb, r0, v0\\n"
\t\t"lrp r1, v0.a, t3, t2\\n"
\t\t"dp3 r1.rgb, r1_bx2, c1\\n"
\t\t"mad_sat r1.rgb, r1, c2, c3\\n"
\t\t"mul r0.rgb, r0, r1\\n";
'''
height = replace_required(height, old_shader, new_shader, "material pixel shader")

new_material_fn = r'''static Bool RevolutionSetTerrainMaterial(TextureClass *baseTexture, TextureClass *materialTexture)
{
	if (!baseTexture || !baseTexture->Peek_D3D_Texture() || !materialTexture || !materialTexture->Peek_D3D_Texture())
		return FALSE;
	if (!RevolutionEnsureTerrainPixelShader())
		return FALSE;

	IDirect3DDevice8 *dev = DX8Wrapper::_Get_D3D_Device8();
	if (!dev)
		return FALSE;

	D3DSURFACE_DESC desc;
	if (FAILED(baseTexture->Peek_D3D_Texture()->GetLevelDesc(0, &desc)) || desc.Width == 0 || desc.Height == 0)
		return FALSE;

	DX8Wrapper::Set_Texture(0, baseTexture);
	DX8Wrapper::Set_Texture(1, baseTexture);
	DX8Wrapper::Set_Texture(2, materialTexture);
	DX8Wrapper::Set_Texture(3, materialTexture);
	DX8Wrapper::Apply_Render_State_Changes();

	dev->SetTextureStageState(0, D3DTSS_TEXCOORDINDEX, 0);
	dev->SetTextureStageState(1, D3DTSS_TEXCOORDINDEX, 1);
	dev->SetTextureStageState(2, D3DTSS_TEXCOORDINDEX, 0);
	dev->SetTextureStageState(3, D3DTSS_TEXCOORDINDEX, 1);

	for (DWORD stage = 0; stage < 4; ++stage)
	{
		dev->SetTextureStageState(stage, D3DTSS_TEXTURETRANSFORMFLAGS, D3DTTFF_DISABLE);
		dev->SetTextureStageState(stage, D3DTSS_ADDRESSU, D3DTADDRESS_CLAMP);
		dev->SetTextureStageState(stage, D3DTSS_ADDRESSV, D3DTADDRESS_CLAMP);
		dev->SetTextureStageState(stage, D3DTSS_MINFILTER, D3DTEXF_ANISOTROPIC);
		dev->SetTextureStageState(stage, D3DTSS_MAGFILTER, D3DTEXF_LINEAR);
		dev->SetTextureStageState(stage, D3DTSS_MIPFILTER, D3DTEXF_LINEAR);
		dev->SetTextureStageState(stage, D3DTSS_MAXANISOTROPY, 16);
	}

	dev->SetPixelShaderConstant(0, D3DXVECTOR4(1.0f, 1.0f, 1.0f, 1.0f), 1);
	dev->SetPixelShaderConstant(1, D3DXVECTOR4(0.28f, -0.34f, 0.90f, 0.0f), 1);
	dev->SetPixelShaderConstant(2, D3DXVECTOR4(0.68f, 0.68f, 0.68f, 0.68f), 1);
	dev->SetPixelShaderConstant(3, D3DXVECTOR4(0.40f, 0.40f, 0.40f, 0.40f), 1);

	if (FAILED(dev->SetPixelShader(g_revolutionTerrainPS)))
	{
		g_revolutionTerrainPS = 0;
		RevolutionTerrainLog("SetPixelShader failed");
		return FALSE;
	}

	if (!g_revolutionTerrainLogged)
	{
		char message[160];
		sprintf_s(message, "ACTIVE Phase7 terrain material _N/_H/_R atlas=%ux%u", (unsigned)desc.Width, (unsigned)desc.Height);
		RevolutionTerrainLog(message);
		g_revolutionTerrainLogged = TRUE;
	}
	return TRUE;
}

'''
fn_pattern = re.compile(
    r"static Bool RevolutionSetTerrainMaterial\(TextureClass \*baseTexture\)\s*\{.*?(?=\s*static void RevolutionResetTerrainMaterial\(\))",
    re.S,
)
if not fn_pattern.search(height):
    raise RuntimeError("Phase 7 patch point not found: RevolutionSetTerrainMaterial")
height = fn_pattern.sub(new_material_fn, height, count=1)

height = replace_required(
    height,
    "if (!RevolutionSetTerrainMaterial(m_stageZeroTexture))",
    "if (!RevolutionSetTerrainMaterial(m_stageZeroTexture, m_map ? m_map->getTerrainMaterialTexture() : nullptr))",
    "material atlas bind",
)

height_path.write_text(height, encoding="utf-8")
print("Phase 7 applied: 2048 PNG/TGA terrain + automatic _N/_H/_R maps.")
