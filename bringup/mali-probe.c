// Probe ChromeOS's libmali on Arch: EGL default display (libmali has no GBM/Wayland platform), surfaceless
// GLES context, FBO clear + readback, then render into a mediatek-drm dumb buffer imported as a DMA-BUF
// EGLImage and check the pixels through the CPU mapping (the path a compositor would use for scanout).
// Build: gcc -O2 -o mali-probe mali-probe.c -ldl -I/usr/include/libdrm
// Run:   LD_LIBRARY_PATH=/opt/quigon-gpu/mali/lib ./mali-probe [frames]
#define EGL_EGLEXT_PROTOTYPES 1
#define GL_GLEXT_PROTOTYPES 1
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <drm/drm.h>
#include <drm/drm_fourcc.h>
#include <drm/drm_mode.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double now_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }
#define CHECK(c, m) do { if (!(c)) { fprintf(stderr, "FAIL: %s (egl 0x%x gl 0x%x)\n", m, eglGetError(), glGetError()); return 1; } } while (0)

int main(int argc, char **argv) {
  int frames = argc > 1 ? atoi(argv[1]) : 100;
  const char *ce = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  printf("client extensions: %s\n", ce ? ce : "(none)");
  EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  CHECK(dpy != EGL_NO_DISPLAY, "eglGetDisplay");
  EGLint maj, min;
  CHECK(eglInitialize(dpy, &maj, &min), "eglInitialize");
  printf("EGL %d.%d vendor=%s version=%s\nclient APIs: %s\ndisplay extensions: %s\n", maj, min,
         eglQueryString(dpy, EGL_VENDOR), eglQueryString(dpy, EGL_VERSION),
         eglQueryString(dpy, EGL_CLIENT_APIS), eglQueryString(dpy, EGL_EXTENSIONS));
  CHECK(eglBindAPI(EGL_OPENGL_ES_API), "eglBindAPI");
  EGLint cattr[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE};
  EGLContext ctx = eglCreateContext(dpy, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, cattr);
  if (ctx == EGL_NO_CONTEXT) {
    EGLint ca[] = {EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE}, n; EGLConfig cfg;
    eglChooseConfig(dpy, ca, &cfg, 1, &n);
    ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, cattr);
  }
  CHECK(ctx != EGL_NO_CONTEXT, "eglCreateContext");
  CHECK(eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx), "eglMakeCurrent surfaceless");
  printf("GL_VENDOR=%s\nGL_RENDERER=%s\nGL_VERSION=%s\nGLSL=%s\n", glGetString(GL_VENDOR), glGetString(GL_RENDERER),
         glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION));
  printf("GL extensions: %s\n", glGetString(GL_EXTENSIONS));

  // 1. Plain FBO clear + readback.
  GLuint tex, fbo; glGenTextures(1, &tex); glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 256, 256, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
  glGenFramebuffers(1, &fbo); glBindFramebuffer(GL_FRAMEBUFFER, fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
  CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "fbo complete");
  glClearColor(0.0f, 1.0f, 0.0f, 1.0f); glClear(GL_COLOR_BUFFER_BIT);
  uint8_t px[4] = {0}; glReadPixels(10, 10, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
  printf("fbo clear readback: %u %u %u %u -> %s\n", px[0], px[1], px[2], px[3], px[1] == 255 && px[0] == 0 ? "PASS" : "FAIL");

  // 2. mediatek-drm dumb buffer -> DMA-BUF -> EGLImage -> render target.
  int drm = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
  CHECK(drm >= 0, "open card0");
  struct drm_mode_create_dumb cd = {.width = 1920, .height = 1200, .bpp = 32};
  CHECK(ioctl(drm, DRM_IOCTL_MODE_CREATE_DUMB, &cd) == 0, "CREATE_DUMB");
  struct drm_prime_handle ph = {.handle = cd.handle, .flags = DRM_CLOEXEC | DRM_RDWR};
  CHECK(ioctl(drm, DRM_IOCTL_PRIME_HANDLE_TO_FD, &ph) == 0, "PRIME_HANDLE_TO_FD");
  EGLint iattr[] = {EGL_WIDTH, 1920, EGL_HEIGHT, 1200, EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_XRGB8888,
                    EGL_DMA_BUF_PLANE0_FD_EXT, ph.fd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
                    EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)cd.pitch, EGL_NONE};
  EGLImageKHR img = eglCreateImageKHR(dpy, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, iattr);
  CHECK(img != EGL_NO_IMAGE_KHR, "eglCreateImageKHR dmabuf");
  GLuint rb, fbo2; glGenRenderbuffers(1, &rb); glBindRenderbuffer(GL_RENDERBUFFER, rb);
  glEGLImageTargetRenderbufferStorageOES(GL_RENDERBUFFER, img);
  glGenFramebuffers(1, &fbo2); glBindFramebuffer(GL_FRAMEBUFFER, fbo2);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, rb);
  CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "dmabuf fbo complete");
  struct drm_mode_map_dumb md = {.handle = cd.handle};
  CHECK(ioctl(drm, DRM_IOCTL_MODE_MAP_DUMB, &md) == 0, "MAP_DUMB");
  uint32_t *map = mmap(NULL, cd.size, PROT_READ, MAP_SHARED, drm, md.offset);
  CHECK(map != MAP_FAILED, "mmap dumb");
  int bad = 0; double t0 = now_ms();
  for (int f = 0; f < frames; f++) {
    float r = (f % 3 == 0), g = (f % 3 == 1), b = (f % 3 == 2);
    glViewport(0, 0, 1920, 1200); glClearColor(r, g, b, 1.0f); glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    uint32_t want = (r ? 0xff0000 : 0) | (g ? 0x00ff00 : 0) | (b ? 0x0000ff : 0);
    uint32_t got = map[(600 * cd.pitch / 4) + 960] & 0xffffff;
    if (got != want) { if (bad < 5) fprintf(stderr, "frame %d: got %06x want %06x\n", f, got, want); bad++; }
  }
  double dt = now_ms() - t0;
  printf("dmabuf render: %d frames, %d bad, %.2f ms/frame -> %s\n", frames, bad, dt / frames, bad ? "FAIL" : "PASS");
  return bad ? 1 : 0;
}
