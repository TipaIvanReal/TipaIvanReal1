#include "W3DDevice/GameClient/RevolutionTerrainImageLoader.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <vector>

#include <objbase.h>
#include <wincodec.h>

#include "Common/FileSystem.h"
#include "Common/file.h"
#include "W3DDevice/GameClient/TileData.h"

namespace
{
struct DecodedImage
{
    Int width = 0;
    Int height = 0;
    std::vector<UnsignedByte> bgra; // bottom-left origin, BGRA8
};

#pragma pack(push, 1)
struct TgaHeader
{
    UnsignedByte idLength;
    UnsignedByte colorMapType;
    UnsignedByte imageType;
    UnsignedShort colorMapStart;
    UnsignedShort colorMapLength;
    UnsignedByte colorMapDepth;
    UnsignedShort xOrigin;
    UnsignedShort yOrigin;
    UnsignedShort width;
    UnsignedShort height;
    UnsignedByte pixelDepth;
    UnsignedByte descriptor;
};
#pragma pack(pop)

static Bool ReadAssetBytes(const char *path, std::vector<UnsignedByte> &bytes)
{
    if (!path || !path[0] || !TheFileSystem)
        return FALSE;

    File *file = TheFileSystem->openFile(path, File::READ | File::BINARY);
    if (!file)
        return FALSE;

    const Int size = file->size();
    if (size <= 0)
    {
        file->close();
        return FALSE;
    }

    bytes.resize((size_t)size);
    const Int read = file->read(bytes.data(), size);
    file->close();
    return read == size;
}

static void TopLeftToBottomLeft(DecodedImage &image)
{
    if (image.width <= 0 || image.height <= 1)
        return;

    const size_t stride = (size_t)image.width * 4;
    std::vector<UnsignedByte> row(stride);
    for (Int y = 0; y < image.height / 2; ++y)
    {
        UnsignedByte *a = image.bgra.data() + (size_t)y * stride;
        UnsignedByte *b = image.bgra.data() + (size_t)(image.height - 1 - y) * stride;
        memcpy(row.data(), a, stride);
        memcpy(a, b, stride);
        memcpy(b, row.data(), stride);
    }
}

static Bool DecodePngWic(const std::vector<UnsignedByte> &bytes, DecodedImage &out)
{
    if (bytes.empty() || bytes.size() > 0xffffffffu)
        return FALSE;

    HRESULT initHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const Bool uninit = SUCCEEDED(initHr);

    IWICImagingFactory *factory = nullptr;
    IWICStream *stream = nullptr;
    IWICBitmapDecoder *decoder = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICFormatConverter *converter = nullptr;

    HRESULT hr = CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_IWICImagingFactory,
        reinterpret_cast<void **>(&factory));

    if (SUCCEEDED(hr))
        hr = factory->CreateStream(&stream);
    if (SUCCEEDED(hr))
        hr = stream->InitializeFromMemory(const_cast<BYTE *>(bytes.data()), (DWORD)bytes.size());
    if (SUCCEEDED(hr))
        hr = factory->CreateDecoderFromStream(stream, nullptr, WICDecodeMetadataCacheOnLoad, &decoder);
    if (SUCCEEDED(hr))
        hr = decoder->GetFrame(0, &frame);

    UINT width = 0;
    UINT height = 0;
    if (SUCCEEDED(hr))
        hr = frame->GetSize(&width, &height);

    if (SUCCEEDED(hr))
        hr = factory->CreateFormatConverter(&converter);
    if (SUCCEEDED(hr))
        hr = converter->Initialize(
            frame,
            GUID_WICPixelFormat32bppBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0,
            WICBitmapPaletteTypeCustom);

    if (SUCCEEDED(hr) && width > 0 && height > 0 && width <= 16384 && height <= 16384)
    {
        const size_t stride = (size_t)width * 4;
        const size_t total = stride * height;
        if (total <= 0xffffffffu)
        {
            out.width = (Int)width;
            out.height = (Int)height;
            out.bgra.resize(total);
            hr = converter->CopyPixels(nullptr, (UINT)stride, (UINT)total, out.bgra.data());
            if (SUCCEEDED(hr))
                TopLeftToBottomLeft(out);
        }
        else
        {
            hr = E_OUTOFMEMORY;
        }
    }
    else if (SUCCEEDED(hr))
    {
        hr = E_INVALIDARG;
    }

    if (converter) converter->Release();
    if (frame) frame->Release();
    if (decoder) decoder->Release();
    if (stream) stream->Release();
    if (factory) factory->Release();
    if (uninit) CoUninitialize();

    return SUCCEEDED(hr);
}

static Bool DecodeTga(const std::vector<UnsignedByte> &bytes, DecodedImage &out)
{
    if (bytes.size() < sizeof(TgaHeader))
        return FALSE;

    const TgaHeader *hdr = reinterpret_cast<const TgaHeader *>(bytes.data());
    if (hdr->colorMapType != 0 || (hdr->imageType != 2 && hdr->imageType != 10))
        return FALSE;
    if (hdr->pixelDepth != 24 && hdr->pixelDepth != 32)
        return FALSE;
    if (hdr->width == 0 || hdr->height == 0 || hdr->width > 16384 || hdr->height > 16384)
        return FALSE;

    const Int width = hdr->width;
    const Int height = hdr->height;
    const Int bpp = hdr->pixelDepth / 8;
    size_t pos = sizeof(TgaHeader) + hdr->idLength;
    if (pos > bytes.size())
        return FALSE;

    std::vector<UnsignedByte> visual((size_t)width * height * 4);
    size_t pixel = 0;
    const size_t pixelCount = (size_t)width * height;

    auto writePixel = [&](const UnsignedByte *src) {
        const Int fileX = (Int)(pixel % width);
        const Int fileY = (Int)(pixel / width);
        const Bool rightToLeft = (hdr->descriptor & 0x10) != 0;
        const Bool topToBottom = (hdr->descriptor & 0x20) != 0;
        const Int x = rightToLeft ? (width - 1 - fileX) : fileX;
        const Int yTop = topToBottom ? fileY : (height - 1 - fileY);
        UnsignedByte *dst = visual.data() + ((size_t)yTop * width + x) * 4;
        dst[0] = src[0];
        dst[1] = src[1];
        dst[2] = src[2];
        dst[3] = bpp == 4 ? src[3] : 255;
        ++pixel;
    };

    if (hdr->imageType == 2)
    {
        while (pixel < pixelCount)
        {
            if (pos + bpp > bytes.size())
                return FALSE;
            writePixel(bytes.data() + pos);
            pos += bpp;
        }
    }
    else
    {
        while (pixel < pixelCount)
        {
            if (pos >= bytes.size())
                return FALSE;

            const UnsignedByte packet = bytes[pos++];
            const Int count = (packet & 0x7f) + 1;
            if (packet & 0x80)
            {
                if (pos + bpp > bytes.size())
                    return FALSE;
                const UnsignedByte *src = bytes.data() + pos;
                pos += bpp;
                for (Int i = 0; i < count && pixel < pixelCount; ++i)
                    writePixel(src);
            }
            else
            {
                for (Int i = 0; i < count && pixel < pixelCount; ++i)
                {
                    if (pos + bpp > bytes.size())
                        return FALSE;
                    writePixel(bytes.data() + pos);
                    pos += bpp;
                }
            }
        }
    }

    out.width = width;
    out.height = height;
    out.bgra.swap(visual);
    TopLeftToBottomLeft(out);
    return TRUE;
}

static Bool DecodeImage(const std::vector<UnsignedByte> &bytes, DecodedImage &out)
{
    static const UnsignedByte pngSig[8] = { 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
    if (bytes.size() >= 8 && memcmp(bytes.data(), pngSig, 8) == 0)
        return DecodePngWic(bytes, out);
    return DecodeTga(bytes, out);
}

static UnsignedByte ClampByte(Int value)
{
    return (UnsignedByte)std::max(0, std::min(255, value));
}

static void StoreNormalPixel(UnsignedByte *dst, float nx, float ny, float nz)
{
    const float len = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (len > 0.00001f)
    {
        nx /= len;
        ny /= len;
        nz /= len;
    }
    else
    {
        nx = 0.0f;
        ny = 0.0f;
        nz = 1.0f;
    }

    dst[2] = ClampByte((Int)((nx * 0.5f + 0.5f) * 255.0f + 0.5f));
    dst[1] = ClampByte((Int)((ny * 0.5f + 0.5f) * 255.0f + 0.5f));
    dst[0] = ClampByte((Int)((nz * 0.5f + 0.5f) * 255.0f + 0.5f));
    dst[3] = 255;
}

static Bool ResampleToLegacyTiles(
    const DecodedImage &image,
    TileData **tiles,
    Int firstTile,
    Int logicalRows,
    RevolutionTerrainMapKind kind)
{
    if (image.width <= 0 || image.height <= 0 || !tiles || logicalRows <= 0 || logicalRows > 10)
        return FALSE;

    const Int tileCount = logicalRows * logicalRows;
    if (firstTile < 0 || firstTile + tileCount > NUM_SOURCE_TILES)
        return FALSE;

    const Int srcTileW = image.width / logicalRows;
    const Int srcTileH = image.height / logicalRows;
    if (srcTileW <= 0 || srcTileH <= 0)
        return FALSE;

    for (Int tileY = 0; tileY < logicalRows; ++tileY)
    {
        for (Int tileX = 0; tileX < logicalRows; ++tileX)
        {
            const Int tileIndex = firstTile + tileX + tileY * logicalRows;
            if (!tiles[tileIndex])
                tiles[tileIndex] = MSGNEW("RevolutionTerrainImageLoader") TileData;

            UnsignedByte *dstTile = tiles[tileIndex]->getDataPtr();

            for (Int y = 0; y < TILE_PIXEL_EXTENT; ++y)
            {
                Int sy0 = tileY * srcTileH + (y * srcTileH) / TILE_PIXEL_EXTENT;
                Int sy1 = tileY * srcTileH + ((y + 1) * srcTileH) / TILE_PIXEL_EXTENT;
                sy1 = std::max(sy1, sy0 + 1);
                sy1 = std::min(sy1, (tileY + 1) * srcTileH);

                for (Int x = 0; x < TILE_PIXEL_EXTENT; ++x)
                {
                    Int sx0 = tileX * srcTileW + (x * srcTileW) / TILE_PIXEL_EXTENT;
                    Int sx1 = tileX * srcTileW + ((x + 1) * srcTileW) / TILE_PIXEL_EXTENT;
                    sx1 = std::max(sx1, sx0 + 1);
                    sx1 = std::min(sx1, (tileX + 1) * srcTileW);

                    UnsignedByte *dst = dstTile + ((y * TILE_PIXEL_EXTENT + x) * 4);

                    if (kind == REV_TERRAIN_NORMAL)
                    {
                        float nx = 0.0f;
                        float ny = 0.0f;
                        float nz = 0.0f;
                        Int samples = 0;
                        for (Int sy = sy0; sy < sy1; ++sy)
                        {
                            for (Int sx = sx0; sx < sx1; ++sx)
                            {
                                const UnsignedByte *src = image.bgra.data() + ((size_t)sy * image.width + sx) * 4;
                                nx += ((float)src[2] / 255.0f) * 2.0f - 1.0f;
                                ny += ((float)src[1] / 255.0f) * 2.0f - 1.0f;
                                nz += ((float)src[0] / 255.0f) * 2.0f - 1.0f;
                                ++samples;
                            }
                        }
                        if (samples > 0)
                        {
                            nx /= samples;
                            ny /= samples;
                            nz /= samples;
                        }
                        StoreNormalPixel(dst, nx, ny, nz);
                    }
                    else
                    {
                        UnsignedInt sumB = 0;
                        UnsignedInt sumG = 0;
                        UnsignedInt sumR = 0;
                        UnsignedInt sumA = 0;
                        UnsignedInt samples = 0;
                        for (Int sy = sy0; sy < sy1; ++sy)
                        {
                            for (Int sx = sx0; sx < sx1; ++sx)
                            {
                                const UnsignedByte *src = image.bgra.data() + ((size_t)sy * image.width + sx) * 4;
                                sumB += src[0];
                                sumG += src[1];
                                sumR += src[2];
                                sumA += src[3];
                                ++samples;
                            }
                        }

                        if (!samples)
                            samples = 1;

                        if (kind == REV_TERRAIN_HEIGHT || kind == REV_TERRAIN_ROUGHNESS)
                        {
                            const UnsignedByte b = (UnsignedByte)(sumB / samples);
                            const UnsignedByte g = (UnsignedByte)(sumG / samples);
                            const UnsignedByte r = (UnsignedByte)(sumR / samples);
                            const UnsignedByte gray = (UnsignedByte)(((Int)r * 77 + (Int)g * 150 + (Int)b * 29) >> 8);
                            dst[0] = gray;
                            dst[1] = gray;
                            dst[2] = gray;
                            dst[3] = 255;
                        }
                        else
                        {
                            dst[0] = (UnsignedByte)(sumB / samples);
                            dst[1] = (UnsignedByte)(sumG / samples);
                            dst[2] = (UnsignedByte)(sumR / samples);
                            dst[3] = (UnsignedByte)(sumA / samples);
                        }
                    }
                }
            }

            tiles[tileIndex]->updateMips();
        }
    }

    return TRUE;
}

static void MakeCompanionCandidate(
    const char *basePath,
    const char *suffix,
    const char *extension,
    char *out,
    size_t outSize)
{
    if (!basePath || !suffix || !extension || !out || !outSize)
        return;

    const char *slashA = strrchr(basePath, '/');
    const char *slashB = strrchr(basePath, '\\');
    const char *slash = slashA > slashB ? slashA : slashB;
    const char *dot = strrchr(basePath, '.');
    if (dot && slash && dot < slash)
        dot = nullptr;

    const Int stemLen = dot ? (Int)(dot - basePath) : (Int)strlen(basePath);
    snprintf(out, outSize, "%.*s%s%s", stemLen, basePath, suffix, extension);
}
}

Bool RevolutionLoadTerrainSheet(
    const char *path,
    TileData **tiles,
    Int firstTile,
    Int logicalRows,
    RevolutionTerrainMapKind kind,
    RevolutionTerrainImageInfo *info)
{
    std::vector<UnsignedByte> bytes;
    DecodedImage image;

    if (!ReadAssetBytes(path, bytes) || !DecodeImage(bytes, image))
        return FALSE;

    if (!ResampleToLegacyTiles(image, tiles, firstTile, logicalRows, kind))
        return FALSE;

    if (info)
    {
        info->width = image.width;
        info->height = image.height;
    }
    return TRUE;
}

Bool RevolutionLoadTerrainCompanion(
    const char *basePath,
    const char *suffix,
    TileData **tiles,
    Int firstTile,
    Int logicalRows,
    RevolutionTerrainMapKind kind,
    RevolutionTerrainImageInfo *info,
    char *resolvedPath,
    size_t resolvedPathSize)
{
    if (!basePath || !suffix)
        return FALSE;

    const char *dot = strrchr(basePath, '.');
    const char *slashA = strrchr(basePath, '/');
    const char *slashB = strrchr(basePath, '\\');
    const char *slash = slashA > slashB ? slashA : slashB;
    if (dot && slash && dot < slash)
        dot = nullptr;

    const char *sameExt = dot ? dot : "";
    const char *extensions[3] = { sameExt, ".png", ".tga" };

    char candidate[1024];
    for (Int i = 0; i < 3; ++i)
    {
        if (!extensions[i][0])
            continue;

        Bool duplicate = FALSE;
        for (Int j = 0; j < i; ++j)
        {
            if (_stricmp(extensions[i], extensions[j]) == 0)
            {
                duplicate = TRUE;
                break;
            }
        }
        if (duplicate)
            continue;

        MakeCompanionCandidate(basePath, suffix, extensions[i], candidate, sizeof(candidate));
        if (RevolutionLoadTerrainSheet(candidate, tiles, firstTile, logicalRows, kind, info))
        {
            if (resolvedPath && resolvedPathSize)
            {
                strncpy_s(resolvedPath, resolvedPathSize, candidate, _TRUNCATE);
            }
            return TRUE;
        }
    }

    return FALSE;
}
