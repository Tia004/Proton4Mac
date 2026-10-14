/* Minimal D3D9 ABI probe: create, clear, read back, and present a frame.
 * Interface order checked against Wine's include/d3d9.h.
 * No shaders, textures, game loop, or performance benchmark.
 */
#define D3D9_PROBE
#include "win32_opengl.c"
typedef long HRESULT;
typedef struct { void **vtable; } COM;
typedef struct {
    UINT width, height, format, count, multisample, quality, swap_effect;
    HANDLE window;
    int windowed, auto_depth;
    UINT depth_format;
    DWORD flags;
    UINT refresh, interval;
} PRESENT_PARAMETERS;
typedef struct { int pitch; void *bits; } LOCKED_RECT;
API COM *CALL Direct3DCreate9(UINT);

void mainCRTStartup(void) {
    WNDCLASSA cls = {0};
    cls.proc = DefWindowProcA; cls.instance = GetModuleHandleA(0);
    cls.name = "Proton4MacD3D9Smoke";
    if (!RegisterClassA(&cls)) ExitProcess(20);
    HANDLE wnd = CreateWindowExA(0, cls.name, "Proton4Mac - Direct3D 9 smoke test",
                                0x00CF0000, 100, 100, 640, 480, 0, 0, cls.instance, 0);
    if (!wnd) ExitProcess(21);
    ShowWindow(wnd, 5);
    COM *d3d = Direct3DCreate9(32), *device = 0, *surface = 0;
    if (!d3d) ExitProcess(22);
    PRESENT_PARAMETERS p = {0};
    p.width = 640; p.height = 480; p.format = 21; p.count = 1;
    p.swap_effect = 1; p.window = wnd; p.windowed = 1; p.flags = 1;
    p.interval = 0x80000000;
    HRESULT (CALL *create)(COM *, UINT, UINT, HANDLE, DWORD, PRESENT_PARAMETERS *, COM **) = (void *)d3d->vtable[16];
    if (create(d3d, 0, 1, wnd, 0x20, &p, &device) < 0) ExitProcess(23);
    HRESULT (CALL *clear)(COM *, DWORD, const void *, DWORD, DWORD, float, DWORD) = (void *)device->vtable[43];
    if (clear(device, 0, 0, 1, 0xff4080c0, 1.0f, 0) < 0) ExitProcess(24);
    HRESULT (CALL *backbuffer)(COM *, UINT, UINT, UINT, COM **) = (void *)device->vtable[18];
    if (backbuffer(device, 0, 0, 0, &surface) < 0) ExitProcess(25);
    LOCKED_RECT rect = {0};
    HRESULT (CALL *lock)(COM *, LOCKED_RECT *, const void *, DWORD) = (void *)surface->vtable[13];
    if (lock(surface, &rect, 0, 0x10) < 0) ExitProcess(26);
    DWORD color = *(DWORD *)rect.bits;
    HRESULT (CALL *unlock)(COM *) = (void *)surface->vtable[14];
    unlock(surface);
    if ((color & 0x00ffffff) != 0x004080c0) ExitProcess(27);
    HRESULT (CALL *present)(COM *, const void *, const void *, HANDLE, const void *) = (void *)device->vtable[17];
    if (present(device, 0, 0, 0, 0) < 0) ExitProcess(28);
    Sleep(1000);
    DWORD (CALL *release)(COM *) = (void *)surface->vtable[2]; release(surface);
    release = (void *)device->vtable[2]; release(device);
    release = (void *)d3d->vtable[2]; release(d3d);
    DestroyWindow(wnd);
    ExitProcess(0);
}
