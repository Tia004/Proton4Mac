/* Independent Win32 + OpenGL smoke probe. No proprietary SDK required.
 * Exit 0 proves window/context creation and an expected pixel, not game support.
 */
typedef void *HANDLE;
typedef unsigned long DWORD;
typedef unsigned int UINT;
typedef unsigned short WORD;
typedef unsigned char BYTE;
typedef unsigned long long WPARAM;
typedef long long LPARAM;
typedef long long LRESULT;
#define API __declspec(dllimport)
#define CALL __stdcall
int _fltused = 0;
void *memset(void *ptr, int value, unsigned long long size) {
    BYTE *bytes = ptr;
    for (unsigned long long i = 0; i < size; ++i) bytes[i] = (BYTE)value;
    return ptr;
}
API HANDLE CALL GetModuleHandleA(const char *);
API void CALL ExitProcess(UINT);
API void CALL Sleep(DWORD);
API LRESULT CALL DefWindowProcA(HANDLE, UINT, WPARAM, LPARAM);
typedef struct {
    UINT style;
    LRESULT (CALL *proc)(HANDLE, UINT, WPARAM, LPARAM);
    int cls_extra, wnd_extra;
    HANDLE instance, icon, cursor, brush;
    const char *menu, *name;
} WNDCLASSA;
API WORD CALL RegisterClassA(const WNDCLASSA *);
API HANDLE CALL CreateWindowExA(DWORD, const char *, const char *, DWORD,
                               int, int, int, int, HANDLE, HANDLE, HANDLE, void *);
API int CALL ShowWindow(HANDLE, int);
API HANDLE CALL GetDC(HANDLE);
API int CALL ReleaseDC(HANDLE, HANDLE);
API int CALL DestroyWindow(HANDLE);
typedef struct {
    WORD size, version;
    DWORD flags;
    BYTE pixel_type, color_bits, red_bits, red_shift, green_bits, green_shift;
    BYTE blue_bits, blue_shift, alpha_bits, alpha_shift, accum_bits;
    BYTE accum_red, accum_green, accum_blue, accum_alpha, depth_bits, stencil_bits;
    BYTE aux_buffers, layer_type, reserved;
    DWORD layer_mask, visible_mask, damage_mask;
} PFD;
API int CALL ChoosePixelFormat(HANDLE, const PFD *);
API int CALL SetPixelFormat(HANDLE, int, const PFD *);
API int CALL SwapBuffers(HANDLE);
API HANDLE CALL wglCreateContext(HANDLE);
API int CALL wglMakeCurrent(HANDLE, HANDLE);
API int CALL wglDeleteContext(HANDLE);
API void CALL glClearColor(float, float, float, float);
API void CALL glClear(UINT);
API void CALL glFinish(void);
API void CALL glReadPixels(int, int, int, int, UINT, UINT, void *);

#ifndef D3D9_PROBE
void mainCRTStartup(void) {
    WNDCLASSA cls = {0};
    cls.proc = DefWindowProcA;
    cls.instance = GetModuleHandleA(0);
    cls.name = "Proton4MacSmoke";
    if (!RegisterClassA(&cls)) ExitProcess(10);
    HANDLE wnd = CreateWindowExA(0, cls.name, "Proton4Mac - OpenGL smoke test",
                                0x00CF0000, 100, 100, 640, 480, 0, 0, cls.instance, 0);
    if (!wnd) ExitProcess(11);
    ShowWindow(wnd, 5);
    HANDLE dc = GetDC(wnd);
    PFD pfd = {0};
    pfd.size = sizeof(pfd); pfd.version = 1;
    pfd.flags = 0x00000004 | 0x00000020 | 0x00000001;
    pfd.color_bits = 24; pfd.depth_bits = 24;
    int format = ChoosePixelFormat(dc, &pfd);
    if (!format || !SetPixelFormat(dc, format, &pfd)) ExitProcess(12);
    HANDLE ctx = wglCreateContext(dc);
    if (!ctx || !wglMakeCurrent(dc, ctx)) ExitProcess(13);
    glClearColor(0.25f, 0.5f, 0.75f, 1.0f);
    glClear(0x00004000); glFinish();
    BYTE pixel[4] = {0};
    glReadPixels(1, 1, 1, 1, 0x1908, 0x1401, pixel);
    int ok = pixel[0] >= 62 && pixel[0] <= 66 &&
             pixel[1] >= 126 && pixel[1] <= 130 &&
             pixel[2] >= 189 && pixel[2] <= 193;
    SwapBuffers(dc);
    Sleep(1000);
    wglMakeCurrent(0, 0); wglDeleteContext(ctx);
    ReleaseDC(wnd, dc); DestroyWindow(wnd);
    ExitProcess(ok ? 0 : 14);
}
#endif
