/* D3D11 HLSL draw, staging readback and swap-chain presentation. BSD-3-Clause.
 * Uses Wine's open headers; does not certify a game's rendering workload. */
#define COBJMACROS
#define INITGUID
#define _ACRTIMP
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
int _fltused;
void *memset(void *ptr, int value, SIZE_T size) {
    unsigned char *p = ptr; while (size--) *p++ = value; return ptr;
}
void *memcpy(void *dst, const void *src, SIZE_T size) {
    unsigned char *out = dst; const unsigned char *in = src;
    while (size--) *out++ = *in++; return dst;
}
void mainCRTStartup(void) {
    WNDCLASSA cls = {0};
    cls.lpfnWndProc = DefWindowProcA; cls.hInstance = GetModuleHandleA(NULL);
    cls.lpszClassName = "Proton4MacD3D11";
    if (!RegisterClassA(&cls)) ExitProcess(10);
    HWND window = CreateWindowExA(0, cls.lpszClassName, "Proton4Mac - Direct3D 11", WS_OVERLAPPEDWINDOW,
        100,100,640,480,NULL,NULL,cls.hInstance,NULL);
    if (!window) ExitProcess(11);
    ShowWindow(window, SW_SHOW);
    DXGI_SWAP_CHAIN_DESC desc = {0};
    desc.BufferDesc.Width = 640; desc.BufferDesc.Height = 480;
    desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1; desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    desc.BufferCount = 2; desc.OutputWindow = window; desc.Windowed = TRUE;
    desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    IDXGISwapChain *swap = NULL; ID3D11Device *device = NULL; ID3D11DeviceContext *ctx = NULL;
    D3D_FEATURE_LEVEL level, requested = D3D_FEATURE_LEVEL_11_0;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,&requested,1,
        D3D11_SDK_VERSION,&desc,&swap,&device,&level,&ctx);
    if (FAILED(hr)) ExitProcess(20);
    if (level != requested) ExitProcess(21);
    ID3D11Texture2D *back = NULL, *staging = NULL; ID3D11RenderTargetView *rt = NULL;
    if (FAILED(IDXGISwapChain_GetBuffer(swap,0,&IID_ID3D11Texture2D,(void **)&back))) ExitProcess(22);
    if (FAILED(ID3D11Device_CreateRenderTargetView(device,(ID3D11Resource *)back,NULL,&rt))) ExitProcess(23);
    D3D11_TEXTURE2D_DESC texture;
    ID3D11Texture2D_GetDesc(back,&texture);
    texture.Usage = D3D11_USAGE_STAGING; texture.BindFlags = 0;
    texture.CPUAccessFlags = D3D11_CPU_ACCESS_READ; texture.MiscFlags = 0;
    if (FAILED(ID3D11Device_CreateTexture2D(device,&texture,NULL,&staging))) ExitProcess(24);
    const float color[4] = {0,0,0,1};
    ID3D11DeviceContext_ClearRenderTargetView(ctx,rt,color);
    const char vs_source[] = "float4 main(uint id:SV_VertexID):SV_Position { float2 uv=float2((id<<1)&2,id&2); return float4(uv*2-1,0,1); }";
    const char ps_source[] = "float4 main():SV_Target { return float4(0.25,0.5,0.75,1); }";
    ID3DBlob *vs_code = NULL, *ps_code = NULL;
    ID3D11VertexShader *vs = NULL; ID3D11PixelShader *ps = NULL;
    if (FAILED(D3DCompile(vs_source,sizeof(vs_source)-1,NULL,NULL,NULL,"main","vs_5_0",0,0,&vs_code,NULL))) ExitProcess(28);
    if (FAILED(D3DCompile(ps_source,sizeof(ps_source)-1,NULL,NULL,NULL,"main","ps_5_0",0,0,&ps_code,NULL))) ExitProcess(29);
    if (FAILED(ID3D11Device_CreateVertexShader(device,ID3D10Blob_GetBufferPointer(vs_code),ID3D10Blob_GetBufferSize(vs_code),NULL,&vs))) ExitProcess(30);
    if (FAILED(ID3D11Device_CreatePixelShader(device,ID3D10Blob_GetBufferPointer(ps_code),ID3D10Blob_GetBufferSize(ps_code),NULL,&ps))) ExitProcess(31);
    D3D11_VIEWPORT viewport = {0,0,640,480,0,1};
    ID3D11DeviceContext_OMSetRenderTargets(ctx,1,&rt,NULL);
    ID3D11DeviceContext_RSSetViewports(ctx,1,&viewport);
    ID3D11DeviceContext_IASetPrimitiveTopology(ctx,D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    D3D11_RASTERIZER_DESC raster_desc = {0}; ID3D11RasterizerState *raster = NULL;
    raster_desc.FillMode = D3D11_FILL_SOLID; raster_desc.CullMode = D3D11_CULL_NONE; raster_desc.DepthClipEnable = TRUE;
    if (FAILED(ID3D11Device_CreateRasterizerState(device,&raster_desc,&raster))) ExitProcess(32);
    ID3D11DeviceContext_RSSetState(ctx,raster);
    ID3D11DeviceContext_VSSetShader(ctx,vs,NULL,0); ID3D11DeviceContext_PSSetShader(ctx,ps,NULL,0);
    ID3D11DeviceContext_Draw(ctx,3,0);
    ID3D11DeviceContext_CopyResource(ctx,(ID3D11Resource *)staging,(ID3D11Resource *)back);
    D3D11_MAPPED_SUBRESOURCE mapped;
    if (FAILED(ID3D11DeviceContext_Map(ctx,(ID3D11Resource *)staging,0,D3D11_MAP_READ,0,&mapped))) ExitProcess(25);
    const unsigned char *pixel = (unsigned char *)mapped.pData + 240*mapped.RowPitch + 320*4;
    char evidence[] = "D3D11_PIXEL=00000000\n";
    const char hex[] = "0123456789abcdef"; DWORD written;
    for (UINT i=0;i<4;i++) { evidence[12+2*i]=hex[pixel[i]>>4]; evidence[13+2*i]=hex[pixel[i]&15]; }
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE),evidence,sizeof(evidence)-1,&written,NULL);
    BOOL ok = pixel[0]>=62 && pixel[0]<=66 && pixel[1]>=126 && pixel[1]<=130 && pixel[2]>=189 && pixel[2]<=193;
    ID3D11DeviceContext_Unmap(ctx,(ID3D11Resource *)staging,0);
    if (FAILED(IDXGISwapChain_Present(swap,1,0))) ExitProcess(26);
    Sleep(1000);
    ID3D11VertexShader_Release(vs); ID3D11PixelShader_Release(ps);
    ID3D11RasterizerState_Release(raster);
    ID3D10Blob_Release(vs_code); ID3D10Blob_Release(ps_code);
    ID3D11RenderTargetView_Release(rt); ID3D11Texture2D_Release(staging); ID3D11Texture2D_Release(back);
    ID3D11DeviceContext_Release(ctx); ID3D11Device_Release(device); IDXGISwapChain_Release(swap);
    DestroyWindow(window); ExitProcess(ok ? 0 : 27);
}
