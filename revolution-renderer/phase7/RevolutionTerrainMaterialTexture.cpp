#include "W3DDevice/GameClient/RevolutionTerrainMaterialTexture.h"

#include <cmath>
#include <cstring>

#include "W3DDevice/GameClient/TileData.h"
#include "W3DDevice/GameClient/WorldHeightMap.h"
#include "WW3D2/dx8wrapper.h"
#include "d3dx8tex.h"

namespace
{
static float ByteToNormal(UnsignedByte value)
{
    return ((float)value / 255.0f) * 2.0f - 1.0f;
}

static UnsignedByte NormalToByte(float value)
{
    value = std::max(-1.0f, std::min(1.0f, value));
    return (UnsignedByte)((value * 0.5f + 0.5f) * 255.0f + 0.5f);
}

static float HeightAt(const UnsignedByte *heightData, Int x, Int y)
{
    if (!heightData)
        return 0.5f;

    x = (x + TILE_PIXEL_EXTENT) % TILE_PIXEL_EXTENT;
    y = (y + TILE_PIXEL_EXTENT) % TILE_PIXEL_EXTENT;
    const UnsignedByte *p = heightData + (y * TILE_PIXEL_EXTENT + x) * TILE_BYTES_PER_PIXEL;
    return (float)p[0] / 255.0f;
}
}

RevolutionTerrainMaterialTextureClass::RevolutionTerrainMaterialTextureClass(Int height) :
    TextureClass(TEXTURE_WIDTH, height, WW3D_FORMAT_A8R8G8B8, MIP_LEVELS_3)
{
}

Int RevolutionTerrainMaterialTextureClass::update(WorldHeightMap *heightMap)
{
    if (!heightMap || !Peek_D3D_Texture())
        return 0;

    IDirect3DSurface8 *surface = nullptr;
    D3DSURFACE_DESC desc;
    D3DLOCKED_RECT locked;

    DX8_ErrorCode(Peek_D3D_Texture()->GetSurfaceLevel(0, &surface));
    DX8_ErrorCode(surface->GetDesc(&desc));
    if (desc.Width < TEXTURE_WIDTH)
    {
        surface->Release();
        return 0;
    }

    DX8_ErrorCode(surface->LockRect(&locked, nullptr, 0));

    // Neutral material across the entire atlas.
    for (UnsignedInt y = 0; y < desc.Height; ++y)
    {
        UnsignedByte *row = (UnsignedByte *)locked.pBits + (size_t)y * locked.Pitch;
        for (UnsignedInt x = 0; x < desc.Width; ++x)
        {
            UnsignedByte *p = row + x * 4;
            p[0] = 255; // B: normal Z
            p[1] = 128; // G: normal Y
            p[2] = 128; // R: normal X
            p[3] = 220; // A: roughness
        }
    }

    for (Int tileIndex = 0; tileIndex < heightMap->m_numBitmapTiles; ++tileIndex)
    {
        TileData *baseTile = heightMap->m_sourceTiles[tileIndex];
        if (!baseTile)
            continue;

        const ICoord2D position = baseTile->m_tileLocationInTexture;
        if (position.x <= 0 || position.y < 0)
            continue;

        TileData *normalTile = heightMap->m_normalTiles[tileIndex];
        TileData *heightTile = heightMap->m_heightTiles[tileIndex];
        TileData *roughTile = heightMap->m_roughnessTiles[tileIndex];

        UnsignedByte *normalData = normalTile ? normalTile->getRGBDataForWidth(TILE_PIXEL_EXTENT) : nullptr;
        UnsignedByte *heightData = heightTile ? heightTile->getRGBDataForWidth(TILE_PIXEL_EXTENT) : nullptr;
        UnsignedByte *roughData = roughTile ? roughTile->getRGBDataForWidth(TILE_PIXEL_EXTENT) : nullptr;

        for (Int surfaceY = 0; surfaceY < TILE_PIXEL_EXTENT; ++surfaceY)
        {
            // TileData row zero is the lower row; D3D texture row zero is the upper row.
            const Int sourceY = TILE_PIXEL_EXTENT - 1 - surfaceY;
            UnsignedByte *dst = (UnsignedByte *)locked.pBits +
                (size_t)(position.y + surfaceY) * locked.Pitch +
                (size_t)position.x * 4;

            for (Int x = 0; x < TILE_PIXEL_EXTENT; ++x)
            {
                float nx = 0.0f;
                float ny = 0.0f;
                float nz = 1.0f;

                if (normalData)
                {
                    const UnsignedByte *n = normalData + (sourceY * TILE_PIXEL_EXTENT + x) * TILE_BYTES_PER_PIXEL;
                    nx = ByteToNormal(n[2]);
                    ny = ByteToNormal(n[1]);
                    nz = ByteToNormal(n[0]);
                }

                if (heightData)
                {
                    const float hL = HeightAt(heightData, x - 1, sourceY);
                    const float hR = HeightAt(heightData, x + 1, sourceY);
                    const float hD = HeightAt(heightData, x, sourceY - 1);
                    const float hU = HeightAt(heightData, x, sourceY + 1);

                    // Height map contributes additional micro-slope to the normal map.
                    const float heightStrength = 1.8f;
                    nx -= (hR - hL) * heightStrength;
                    ny -= (hU - hD) * heightStrength;
                }

                const float length = std::sqrt(nx * nx + ny * ny + nz * nz);
                if (length > 0.00001f)
                {
                    nx /= length;
                    ny /= length;
                    nz /= length;
                }
                else
                {
                    nx = 0.0f;
                    ny = 0.0f;
                    nz = 1.0f;
                }

                UnsignedByte roughness = 220;
                if (roughData)
                {
                    const UnsignedByte *r = roughData + (sourceY * TILE_PIXEL_EXTENT + x) * TILE_BYTES_PER_PIXEL;
                    roughness = r[0];
                }

                dst[0] = NormalToByte(nz);
                dst[1] = NormalToByte(ny);
                dst[2] = NormalToByte(nx);
                dst[3] = roughness;
                dst += 4;
            }
        }
    }

    // Match the diffuse atlas wrap border so both atlases can use identical UVs.
    for (Int textureClass = 0; textureClass < heightMap->m_numTextureClasses; ++textureClass)
    {
        Int width = heightMap->m_textureClasses[textureClass].width;
        const ICoord2D origin = heightMap->m_textureClasses[textureClass].positionInTexture;
        if (origin.x <= 0)
            continue;

        width *= TILE_PIXEL_EXTENT;

        for (Int y = 0; y < width; ++y)
        {
            UnsignedByte *row = (UnsignedByte *)locked.pBits +
                (size_t)(origin.y + y) * locked.Pitch +
                (size_t)origin.x * 4;

            memcpy(row - 4 * 4, row + (width - 4) * 4, 4 * 4);
            memcpy(row + width * 4, row, 4 * 4);
        }

        for (Int border = 0; border < 4; ++border)
        {
            UnsignedByte *topTarget = (UnsignedByte *)locked.pBits +
                (size_t)(origin.y - border - 1) * locked.Pitch +
                (size_t)(origin.x - 4) * 4;
            UnsignedByte *topSource = topTarget + (size_t)width * locked.Pitch;
            memcpy(topTarget, topSource, (size_t)(width + 8) * 4);

            UnsignedByte *bottomSource = (UnsignedByte *)locked.pBits +
                (size_t)(origin.y + border) * locked.Pitch +
                (size_t)(origin.x - 4) * 4;
            UnsignedByte *bottomTarget = bottomSource + (size_t)width * locked.Pitch;
            memcpy(bottomTarget, bottomSource, (size_t)(width + 8) * 4);
        }
    }

    surface->UnlockRect();
    surface->Release();

    DX8_ErrorCode(D3DXFilterTexture(Peek_D3D_Texture(), nullptr, 0, D3DX_FILTER_BOX));
    if (WW3D::Get_Texture_Reduction())
        Peek_D3D_Texture()->SetLOD(WW3D::Get_Texture_Reduction());

    return (Int)desc.Height;
}
