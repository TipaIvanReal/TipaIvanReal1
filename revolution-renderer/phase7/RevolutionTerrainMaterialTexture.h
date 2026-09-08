#pragma once

#include "WW3D2/texture.h"

class WorldHeightMap;

class RevolutionTerrainMaterialTextureClass : public TextureClass
{
    W3DMPO_CODE(RevolutionTerrainMaterialTextureClass)

public:
    explicit RevolutionTerrainMaterialTextureClass(Int height);
    Int update(WorldHeightMap *heightMap);
};
