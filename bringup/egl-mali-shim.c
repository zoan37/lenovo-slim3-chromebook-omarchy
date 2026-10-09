// LD_PRELOAD shim that lets Hyprland/Aquamarine run on ChromeOS's libmali (r54p1), which only offers the EGL
// default display: no EXT_platform_device, no KHR_platform_gbm, no device enumeration. libmali does have
// surfaceless contexts and EXT_image_dma_buf_import(_modifiers), which is all a KMS compositor needs.
//
// - client extensions additionally report EGL_EXT_device_{base,enumeration,query}, EGL_EXT_platform_device,
//   EGL_KHR_platform_gbm, EGL_MESA_platform_gbm
// - eglQueryDevicesEXT returns one fake device whose DRM nodes are QUIGON_DRM_PRIMARY / QUIGON_DRM_RENDER
// - eglGetPlatformDisplay(EXT) for any platform returns eglGetDisplay(EGL_DEFAULT_DISPLAY)
// - in its constructor it drops LD_PRELOAD / LD_LIBRARY_PATH from the environment, so programs the compositor
//   starts keep using the system Mesa
//
// Build: gcc -O2 -shared -fPIC -o egl-mali-shim.so egl-mali-shim.c -ldl
// Use:   LD_LIBRARY_PATH=/opt/quigon-gpu/mali/lib LD_PRELOAD=/opt/quigon-gpu/lib/egl-mali-shim.so Hyprland
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef EGL_DRM_RENDER_NODE_FILE_EXT
#define EGL_DRM_RENDER_NODE_FILE_EXT 0x3377
#endif

static const char *EXTRA_CLIENT = " EGL_EXT_device_base EGL_EXT_device_enumeration EGL_EXT_device_query"
                                  " EGL_EXT_platform_device EGL_KHR_platform_gbm EGL_MESA_platform_gbm";
static EGLDeviceEXT FAKE_DEVICE = (EGLDeviceEXT)(void *)0x51a1c0de;
static char client_ext[4096];
static int trace;

#define REAL(name) static __typeof__(name) *real_##name; if (!real_##name) real_##name = (__typeof__(name) *)dlsym(RTLD_NEXT, #name)
#define LOG(...) do { if (trace) fprintf(stderr, "[egl-mali-shim] " __VA_ARGS__); } while (0)

// The launch chain (uwsm's python helper, start-hyprland) inherits the preload too; only the compositor itself
// drops it, so the compositor's own children start clean while the chain still reaches it.
__attribute__((constructor)) static void shim_init(void) {
  trace = getenv("QUIGON_EGL_SHIM_TRACE") != NULL;
  char exe[512] = {0};
  ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
  const char *base = n > 0 ? strrchr(exe, '/') : NULL;
  base = base ? base + 1 : exe;
  const char *want = getenv("QUIGON_EGL_SHIM_EXE");
  if (!strcmp(base, want ? want : "Hyprland")) {
    unsetenv("LD_PRELOAD");
    unsetenv("LD_LIBRARY_PATH");
    LOG("active in %s (pid %d), cleared LD_PRELOAD/LD_LIBRARY_PATH for children\n", base, getpid());
  }
}

static EGLDisplay default_display(void) {
  static __typeof__(eglGetDisplay) *real_get;
  if (!real_get) real_get = (__typeof__(eglGetDisplay) *)dlsym(RTLD_NEXT, "eglGetDisplay");
  return real_get ? real_get(EGL_DEFAULT_DISPLAY) : EGL_NO_DISPLAY;
}

const char *eglQueryString(EGLDisplay dpy, EGLint name) {
  REAL(eglQueryString);
  const char *s = real_eglQueryString(dpy, name);
  if (dpy == EGL_NO_DISPLAY && name == EGL_EXTENSIONS) {
    if (!client_ext[0]) snprintf(client_ext, sizeof client_ext, "%s%s", s ? s : "", EXTRA_CLIENT);
    return client_ext;
  }
  return s;
}

EGLDisplay eglGetPlatformDisplay(EGLenum platform, void *native, const EGLAttrib *attrs) {
  (void)native; (void)attrs;
  LOG("eglGetPlatformDisplay(0x%x) -> default display\n", platform);
  return default_display();
}

EGLDisplay eglGetPlatformDisplayEXT(EGLenum platform, void *native, const EGLint *attrs) {
  (void)native; (void)attrs;
  LOG("eglGetPlatformDisplayEXT(0x%x) -> default display\n", platform);
  return default_display();
}

EGLBoolean eglQueryDevicesEXT(EGLint max, EGLDeviceEXT *devices, EGLint *num) {
  if (!num) return EGL_FALSE;
  if (devices && max > 0) devices[0] = FAKE_DEVICE;
  *num = 1;
  return EGL_TRUE;
}

const char *eglQueryDeviceStringEXT(EGLDeviceEXT dev, EGLint name) {
  if (dev != FAKE_DEVICE) return NULL;
  const char *primary = getenv("QUIGON_DRM_PRIMARY"), *render = getenv("QUIGON_DRM_RENDER");
  switch (name) {
  case EGL_EXTENSIONS: return "EGL_EXT_device_drm EGL_EXT_device_drm_render_node";
  case EGL_DRM_DEVICE_FILE_EXT: return primary ? primary : "/dev/dri/card0";
  case EGL_DRM_RENDER_NODE_FILE_EXT: return render ? render : "/dev/dri/renderD128";
  default: return NULL;
  }
}

EGLBoolean eglQueryDeviceAttribEXT(EGLDeviceEXT dev, EGLint attr, EGLAttrib *value) {
  (void)dev; (void)attr; (void)value;
  return EGL_FALSE;
}

EGLBoolean eglQueryDisplayAttribEXT(EGLDisplay dpy, EGLint attr, EGLAttrib *value) {
  (void)dpy;
  if (attr == EGL_DEVICE_EXT && value) { *value = (EGLAttrib)FAKE_DEVICE; return EGL_TRUE; }
  return EGL_FALSE;
}

// Hyprland loads this unconditionally (and aborts on NULL) but only calls it with debug:gl_debugging.
static EGLint stub_eglDebugMessageControlKHR(void *cb, const EGLAttrib *attrs) { (void)cb; (void)attrs; return EGL_SUCCESS; }

__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name) {
  REAL(eglGetProcAddress);
  static const struct { const char *n; void *f; } ours[] = {
    {"eglGetPlatformDisplay", (void *)eglGetPlatformDisplay},
    {"eglGetPlatformDisplayEXT", (void *)eglGetPlatformDisplayEXT},
    {"eglQueryDevicesEXT", (void *)eglQueryDevicesEXT},
    {"eglQueryDeviceStringEXT", (void *)eglQueryDeviceStringEXT},
    {"eglQueryDeviceAttribEXT", (void *)eglQueryDeviceAttribEXT},
    {"eglQueryDisplayAttribEXT", (void *)eglQueryDisplayAttribEXT},
    {"eglQueryString", (void *)eglQueryString},
  };
  for (size_t i = 0; i < sizeof ours / sizeof ours[0]; i++)
    if (!strcmp(name, ours[i].n)) return (__eglMustCastToProperFunctionPointerType)ours[i].f;
  __eglMustCastToProperFunctionPointerType p = real_eglGetProcAddress(name);
  if (!p && !strcmp(name, "eglDebugMessageControlKHR")) p = (__eglMustCastToProperFunctionPointerType)stub_eglDebugMessageControlKHR;
  if (!p) LOG("eglGetProcAddress(%s) = NULL\n", name);
  return p;
}
