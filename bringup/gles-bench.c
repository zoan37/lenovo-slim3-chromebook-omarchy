// Same offscreen GLES 3 workload on libmali (native) or Mesa (Zink), to measure Zink's overhead.
// Native: LD_LIBRARY_PATH=/opt/quigon-gpu/mali/lib ./gles-bench          (EGL default display)
// Zink:   MESA_LOADER_DRIVER_OVERRIDE=zink BENCH_SURFACELESS=1 ./gles-bench
// Build:  gcc -O2 -o gles-bench gles-bench.c -lEGL -lGLESv2
#define EGL_EGLEXT_PROTOTYPES 1
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define W 1920
#define H 1200
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e3 + t.tv_nsec / 1e6; }

static GLuint prog(const char *vs, const char *fs) {
  GLuint p = glCreateProgram();
  const char *src[2] = {vs, fs}; GLenum ty[2] = {GL_VERTEX_SHADER, GL_FRAGMENT_SHADER};
  for (int i = 0; i < 2; i++) {
    GLuint s = glCreateShader(ty[i]); glShaderSource(s, 1, &src[i], NULL); glCompileShader(s);
    GLint ok; glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) { char log[1024]; glGetShaderInfoLog(s, sizeof log, NULL, log); fprintf(stderr, "shader: %s\n", log); exit(1); }
    glAttachShader(p, s);
  }
  glLinkProgram(p); return p;
}

static const char *VS = "#version 300 es\nlayout(location=0) in vec2 p; uniform vec4 r; out vec2 uv;\n"
  "void main(){ uv=p; gl_Position=vec4(r.xy + p*r.zw, 0.0, 1.0); }";
static const char *FS_FLAT = "#version 300 es\nprecision mediump float; uniform vec4 c; out vec4 o; void main(){ o=c; }";
static const char *FS_HEAVY = "#version 300 es\nprecision highp float; in vec2 uv; uniform float t; out vec4 o;\n"
  "void main(){ vec3 a=vec3(uv,t); for(int i=0;i<48;i++){ a=sin(a*1.7+a.yzx*0.9)+cos(a.zxy*1.3); } o=vec4(a*0.5+0.5,1.0); }";
static const char *FS_TEX = "#version 300 es\nprecision mediump float; in vec2 uv; uniform sampler2D s; out vec4 o; void main(){ o=texture(s,uv); }";

int main(void) {
  EGLDisplay d = getenv("BENCH_SURFACELESS") ? eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL)
                                             : eglGetDisplay(EGL_DEFAULT_DISPLAY);
  eglInitialize(d, NULL, NULL); eglBindAPI(EGL_OPENGL_ES_API);
  EGLint ca[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_NONE};
  EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
  if (c == EGL_NO_CONTEXT || !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c)) { fprintf(stderr, "context failed\n"); return 1; }
  printf("renderer: %s\n", glGetString(GL_RENDERER));

  GLuint rt, fb; glGenTextures(1, &rt); glBindTexture(GL_TEXTURE_2D, rt);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
  glGenFramebuffers(1, &fb); glBindFramebuffer(GL_FRAMEBUFFER, fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, rt, 0);
  glViewport(0, 0, W, H);
  float quad[] = {0, 0, 1, 0, 0, 1, 1, 1}; GLuint vb; glGenBuffers(1, &vb); glBindBuffer(GL_ARRAY_BUFFER, vb);
  glBufferData(GL_ARRAY_BUFFER, sizeof quad, quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, 0);

  GLuint pf = prog(VS, FS_FLAT), ph = prog(VS, FS_HEAVY), pt = prog(VS, FS_TEX);
  const int F = 60; double t0, ms;

  // 1. 5,000 draw calls per frame, each with its own uniforms (CPU/driver overhead).
  glUseProgram(pf); GLint ur = glGetUniformLocation(pf, "r"), uc = glGetUniformLocation(pf, "c");
  for (int warm = 0; warm < 2; warm++) {
    t0 = now();
    for (int f = 0; f < F; f++) {
      glClear(GL_COLOR_BUFFER_BIT);
      for (int i = 0; i < 5000; i++) {
        glUniform4f(ur, -1.0f + (i % 100) * 0.02f, -1.0f + (i / 100) * 0.04f, 0.018f, 0.036f);
        glUniform4f(uc, (i % 7) / 7.0f, (i % 11) / 11.0f, (i % 13) / 13.0f, 1);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      }
      glFinish();
    }
    ms = (now() - t0) / F;
  }
  printf("draw calls  (5000/frame):        %7.2f ms/frame\n", ms);

  // 2. Heavy fragment shader over the whole 1920x1200 target, 3 passes (GPU-bound).
  glUseProgram(ph); GLint urh = glGetUniformLocation(ph, "r"), ut = glGetUniformLocation(ph, "t");
  glUniform4f(urh, -1, -1, 2, 2);
  for (int warm = 0; warm < 2; warm++) {
    t0 = now();
    for (int f = 0; f < F; f++) { for (int k = 0; k < 3; k++) { glUniform1f(ut, f + k * 0.1f); glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); } glFinish(); }
    ms = (now() - t0) / F;
  }
  printf("heavy shader (3 full passes):    %7.2f ms/frame\n", ms);

  // 3. Upload a full 1920x1200 RGBA texture and draw it (terminal/compositor-like).
  unsigned char *pix = malloc(W * H * 4); memset(pix, 0x80, W * H * 4);
  GLuint tx; glGenTextures(1, &tx); glBindTexture(GL_TEXTURE_2D, tx); glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, W, H);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glUseProgram(pt); glUniform4f(glGetUniformLocation(pt, "r"), -1, -1, 2, 2);
  for (int warm = 0; warm < 2; warm++) {
    t0 = now();
    for (int f = 0; f < F; f++) { pix[f] ^= 0xff; glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, pix); glDrawArrays(GL_TRIANGLE_STRIP, 0, 4); glFinish(); }
    ms = (now() - t0) / F;
  }
  printf("texture upload+draw (1920x1200): %7.2f ms/frame\n", ms);
  return 0;
}
