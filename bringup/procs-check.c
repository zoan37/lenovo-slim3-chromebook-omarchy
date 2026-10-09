// Look up every EGL/GL entry point Hyprland 0.56 loads with eglGetProcAddress (it aborts on NULL), through the shim.
#include <EGL/egl.h>
#include <stdio.h>
int main(void) {
  const char *names[] = {"glEGLImageTargetRenderbufferStorageOES", "eglCreateImageKHR", "eglDestroyImageKHR",
    "eglQueryDmaBufFormatsEXT", "eglQueryDmaBufModifiersEXT", "glEGLImageTargetTexture2DOES",
    "eglDebugMessageControlKHR", "eglGetPlatformDisplayEXT", "eglCreateSyncKHR", "eglDestroySyncKHR",
    "eglDupNativeFenceFDANDROID", "eglWaitSyncKHR", "eglQueryDevicesEXT", "eglQueryDeviceStringEXT",
    "eglQueryDisplayAttribEXT"};
  int missing = 0;
  printf("client ext: %s\n", eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS));
  for (unsigned i = 0; i < sizeof names / sizeof *names; i++) {
    void *p = (void *)eglGetProcAddress(names[i]);
    printf("%-40s %s\n", names[i], p ? "ok" : "NULL"); missing += !p;
  }
  return missing;
}
