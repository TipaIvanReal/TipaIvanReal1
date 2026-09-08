#pragma once

#include <stddef.h>

#include "Lib/BaseType.h"

class TileData;

enum RevolutionTerrainMapKind
{
    REV_TERRAIN_DIFFUSE = 0,
    REV_TERRAIN_NORMAL,
    REV_TERRAIN_HEIGHT,
    REV_TERRAIN_ROUGHNESS,
};

struct RevolutionTerrainImageInfo
{
    Int width;
    Int height;
    RevolutionTerrainImageInfo() : width(0), height(0) {}
};

Bool RevolutionLoadTerrainSheet(
    const char *path,
    TileData **tiles,
    Int firstTile,
    Int logicalRows,
    RevolutionTerrainMapKind kind,
    RevolutionTerrainImageInfo *info);

Bool RevolutionLoadTerrainCompanion(
    const char *basePath,
    const char *suffix,
    TileData **tiles,
    Int firstTile,
    Int logicalRows,
    RevolutionTerrainMapKind kind,
    RevolutionTerrainImageInfo *info,
    char *resolvedPath,
    size_t resolvedPathSize);
