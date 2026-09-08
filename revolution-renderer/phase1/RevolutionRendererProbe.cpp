#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d12.h>
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <cstdio>

#include "RevolutionRendererProbe.h"

using Microsoft::WRL::ComPtr;

namespace
{
void LogLine(FILE *f, const char *text)
{
    if (f) {
        std::fprintf(f, "%s\n", text);
        std::fflush(f);
    }
}

void LogAdapter(FILE *f, IDXGIAdapter1 *adapter)
{
    if (!f || !adapter) {
        return;
    }

    DXGI_ADAPTER_DESC1 desc{};
    if (FAILED(adapter->GetDesc1(&desc))) {
        return;
    }

    char name[256]{};
    WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, static_cast<int>(sizeof(name)), nullptr, nullptr);

    std::fprintf(f, "Adapter: %s\n", name);
    std::fprintf(f, "DedicatedVideoMemory: %llu MiB\n",
        static_cast<unsigned long long>(desc.DedicatedVideoMemory / (1024ull * 1024ull)));
    std::fprintf(f, "VendorId: 0x%04X DeviceId: 0x%04X\n", desc.VendorId, desc.DeviceId);
    std::fflush(f);
}
}

void RevolutionRendererProbe_Initialize()
{
    FILE *f = nullptr;
#if defined(_MSC_VER)
    fopen_s(&f, "RevolutionRenderer.log", "w");
#else
    f = std::fopen("RevolutionRenderer.log", "w");
#endif

    LogLine(f, "Revolution Project Modern Renderer - Phase 1");
    LogLine(f, "DX12 capability probe: starting");

    ComPtr<IDXGIFactory6> factory;
    HRESULT hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));
    if (FAILED(hr)) {
        if (f) std::fprintf(f, "CreateDXGIFactory2 failed: 0x%08lX\n", static_cast<unsigned long>(hr));
        if (f) std::fclose(f);
        return;
    }

    ComPtr<IDXGIAdapter1> selected;
    for (UINT index = 0; ; ++index) {
        ComPtr<IDXGIAdapter1> adapter;
        hr = factory->EnumAdapterByGpuPreference(
            index,
            DXGI_GPU_PREFERENCE_HIGH_PERFORMANCE,
            IID_PPV_ARGS(&adapter));

        if (hr == DXGI_ERROR_NOT_FOUND) {
            break;
        }
        if (FAILED(hr)) {
            continue;
        }

        DXGI_ADAPTER_DESC1 desc{};
        if (FAILED(adapter->GetDesc1(&desc)) || (desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
            continue;
        }

        if (SUCCEEDED(D3D12CreateDevice(adapter.Get(), D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), nullptr))) {
            selected = adapter;
            break;
        }
    }

    if (!selected) {
        LogLine(f, "No hardware DX12 adapter found; trying WARP.");
        ComPtr<IDXGIAdapter> warp;
        hr = factory->EnumWarpAdapter(IID_PPV_ARGS(&warp));
        if (SUCCEEDED(hr)) {
            warp.As(&selected);
        }
    }

    if (!selected) {
        LogLine(f, "DX12 unavailable: no compatible adapter.");
        if (f) std::fclose(f);
        return;
    }

    LogAdapter(f, selected.Get());

    ComPtr<ID3D12Device> device;
    hr = D3D12CreateDevice(selected.Get(), D3D_FEATURE_LEVEL_11_0, IID_PPV_ARGS(&device));
    if (FAILED(hr)) {
        if (f) std::fprintf(f, "D3D12CreateDevice failed: 0x%08lX\n", static_cast<unsigned long>(hr));
        if (f) std::fclose(f);
        return;
    }

    D3D12_FEATURE_DATA_D3D12_OPTIONS options{};
    if (SUCCEEDED(device->CheckFeatureSupport(D3D12_FEATURE_D3D12_OPTIONS, &options, sizeof(options)))) {
        if (f) {
            std::fprintf(f, "ResourceBindingTier: %d\n", static_cast<int>(options.ResourceBindingTier));
            std::fprintf(f, "TiledResourcesTier: %d\n", static_cast<int>(options.TiledResourcesTier));
        }
    }

    D3D12_FEATURE_DATA_ROOT_SIGNATURE rootSig{D3D_ROOT_SIGNATURE_VERSION_1_1};
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_ROOT_SIGNATURE, &rootSig, sizeof(rootSig)))) {
        rootSig.HighestVersion = D3D_ROOT_SIGNATURE_VERSION_1_0;
    }

    if (f) {
        std::fprintf(f, "RootSignature: %s\n",
            rootSig.HighestVersion == D3D_ROOT_SIGNATURE_VERSION_1_1 ? "1.1" : "1.0");
    }

    D3D12_FEATURE_DATA_SHADER_MODEL shaderModel{D3D_SHADER_MODEL_6_6};
    if (FAILED(device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL, &shaderModel, sizeof(shaderModel)))) {
        shaderModel.HighestShaderModel = D3D_SHADER_MODEL_6_0;
        device->CheckFeatureSupport(D3D12_FEATURE_SHADER_MODEL, &shaderModel, sizeof(shaderModel));
    }

    if (f) {
        std::fprintf(f, "ShaderModelRaw: 0x%X\n", static_cast<unsigned>(shaderModel.HighestShaderModel));
        LogLine(f, "DX12 device initialized successfully.");
        LogLine(f, "Legacy WW3D rendering remains active in Phase 1.");
        LogLine(f, "Next: move frame presentation, geometry, materials, shadows and post-processing onto DX12.");
        std::fclose(f);
    }
}
