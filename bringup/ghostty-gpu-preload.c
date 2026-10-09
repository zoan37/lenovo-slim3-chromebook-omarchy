// LD_PRELOAD for Ghostty on the patched Zink Mesa (/opt/quigon-gpu/mesa-zink).
// - Ghostty overwrites GDK_DISABLE with "gles-api,vulkan" at startup; append "dmabuf,offload" so GTK 4.22 doesn't try
//   to pass GL textures as DMA-BUFs (Zink can't export memory on the Mali: "couldn't allocate memory",
//   "Failed to download ... dmabuf texture").
// - Strip the private-Mesa variables from programs Ghostty execs (the shell and what runs in it), so they use the
//   normal session setup. The dynamic loader read LD_LIBRARY_PATH at startup, so Ghostty itself keeps the private Mesa.
// Build: gcc -O2 -shared -fPIC -o ghostty-gpu-preload.so ghostty-gpu-preload.c -ldl
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

int setenv(const char *name, const char *value, int overwrite) {
  static int (*real)(const char *, const char *, int);
  if (!real) real = (int (*)(const char *, const char *, int))dlsym(RTLD_NEXT, "setenv");
  if (name && value && !strcmp(name, "GDK_DISABLE")) {
    char buf[512];
    snprintf(buf, sizeof buf, "%s%sdmabuf,offload", value, value[0] ? "," : "");
    return real(name, buf, overwrite);
  }
  return real(name, value, overwrite);
}

static const char *const STRIP[] = {"LD_PRELOAD=", "LD_LIBRARY_PATH=", "__EGL_VENDOR_LIBRARY_FILENAMES=",
                                    "MESA_GL_VERSION_OVERRIDE=", "MESA_GLSL_VERSION_OVERRIDE=",
                                    "QUIGON_ZINK_RO_VERTEX_SSBO=", NULL};

static char **filtered(char *const envp[]) {
  size_t n = 0;
  while (envp && envp[n]) n++;
  char **out = malloc((n + 1) * sizeof *out);
  if (!out) return (char **)envp;
  size_t k = 0;
  for (size_t i = 0; i < n; i++) {
    int drop = 0;
    for (const char *const *s = STRIP; *s; s++)
      if (!strncmp(envp[i], *s, strlen(*s))) { drop = 1; break; }
    if (!drop) out[k++] = envp[i];
  }
  out[k] = NULL;
  return out;
}

int execve(const char *path, char *const argv[], char *const envp[]) {
  static int (*real)(const char *, char *const[], char *const[]);
  if (!real) real = (int (*)(const char *, char *const[], char *const[]))dlsym(RTLD_NEXT, "execve");
  return real(path, argv, filtered(envp));
}

int execvpe(const char *file, char *const argv[], char *const envp[]) {
  static int (*real)(const char *, char *const[], char *const[]);
  if (!real) real = (int (*)(const char *, char *const[], char *const[]))dlsym(RTLD_NEXT, "execvpe");
  return real(file, argv, filtered(envp));
}
