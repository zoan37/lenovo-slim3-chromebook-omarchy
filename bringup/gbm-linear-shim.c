/*
 * gbm-linear-shim: libgbm.so.1 for Chrome in front of ChromeOS's minigbm (mediatek backend).
 *
 * Chrome's frame pool for hardware video decode allocates NV12 buffers with
 * gbm_bo_create_with_modifiers(), passing the modifiers it accepts for the format. On this
 * desktop that list can come down to DRM_FORMAT_MOD_INVALID ("implicit layout") alone, and
 * minigbm's mediatek backend only accepts lists that contain DRM_FORMAT_MOD_LINEAR, so every
 * allocation fails ("no usable modifier found") and the GPU process dies. On MediaTek the
 * implicit layout of these buffers is linear, so add LINEAR to such lists (YUV formats only).
 *
 * Chrome's gbm_bo_import(GBM_BO_IMPORT_FD_MODIFIER) uses Mesa's constant, which means something
 * else to minigbm; see gbm_bo_import() below.
 *
 * Everything else resolves to minigbm itself: this library has DT_NEEDED on a copy of it
 * renamed to libquigon-minigbm.so (its own soname is libgbm.so.1 too). QUIGON_GBM_TRACE=1 logs
 * every modifier list.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

struct gbm_device;
struct gbm_bo;

#define MOD_LINEAR 0ULL
#define MOD_INVALID 0x00ffffffffffffffULL
#define MAX_MODS 64

static int trace(void)
{
	static int t = -1;
	if (t < 0)
		t = getenv("QUIGON_GBM_TRACE") != NULL;
	return t;
}

/* Video frame formats only: other formats keep minigbm's stock behavior (Chrome probes RGBA with
 * implicit-only lists in a tight loop once those succeed). */
static int is_yuv(uint32_t format)
{
	switch (format) {
	case 0x3231564e: /* NV12 */
	case 0x3132564e: /* NV21 */
	case 0x32315559: /* YU12 */
	case 0x32315659: /* YV12 */
	case 0x30313050: /* P010 */
		return 1;
	}
	return 0;
}

static const uint64_t *fix_modifiers(uint32_t w, uint32_t h, uint32_t format, const uint64_t *mods,
				     unsigned int count, unsigned int *out_count, uint64_t *buf)
{
	int linear = 0, invalid = 0;

	for (unsigned int i = 0; i < count; i++) {
		linear |= mods[i] == MOD_LINEAR;
		invalid |= mods[i] == MOD_INVALID;
	}
	*out_count = count;
	if (!is_yuv(format))
		return mods;
	if (trace()) {
		fprintf(stderr, "[gbm-linear-shim] pid %d create_with_modifiers %ux%u %.4s:", getpid(), w, h, (const char *)&format);
		for (unsigned int i = 0; i < count; i++)
			fprintf(stderr, " 0x%llx", (unsigned long long)mods[i]);
		fprintf(stderr, "%s\n", !linear && (invalid || !count) ? " -> +LINEAR" : "");
	}
	*out_count = count;
	if (linear || (!invalid && count) || count >= MAX_MODS)
		return mods;

	for (unsigned int i = 0; i < count; i++)
		buf[i] = mods[i];
	buf[count] = MOD_LINEAR;
	*out_count = count + 1;
	return buf;
}

struct gbm_bo *gbm_bo_create_with_modifiers(struct gbm_device *gbm, uint32_t width, uint32_t height,
					    uint32_t format, const uint64_t *modifiers,
					    const unsigned int count)
{
	static struct gbm_bo *(*real)(struct gbm_device *, uint32_t, uint32_t, uint32_t,
				      const uint64_t *, unsigned int);
	uint64_t buf[MAX_MODS + 1];
	unsigned int n;
	const uint64_t *mods;

	if (!real)
		real = dlsym(RTLD_NEXT, "gbm_bo_create_with_modifiers");
	mods = fix_modifiers(width, height, format, modifiers, count, &n, buf);
	return real(gbm, width, height, format, mods, n);
}

struct gbm_bo *gbm_bo_create_with_modifiers2(struct gbm_device *gbm, uint32_t width,
					     uint32_t height, uint32_t format,
					     const uint64_t *modifiers, const unsigned int count,
					     uint32_t flags)
{
	static struct gbm_bo *(*real)(struct gbm_device *, uint32_t, uint32_t, uint32_t,
				      const uint64_t *, unsigned int, uint32_t);
	uint64_t buf[MAX_MODS + 1];
	unsigned int n;
	const uint64_t *mods;

	if (!real)
		real = dlsym(RTLD_NEXT, "gbm_bo_create_with_modifiers2");
	mods = fix_modifiers(width, height, format, modifiers, count, &n, buf);
	return real(gbm, width, height, format, mods, n, flags);
}

/* Imports (with the Mesa -> minigbm constant fix below) and a traced gbm_bo_create. */
struct gbm_import_fd_modifier_data {
	uint32_t width, height, format, num_fds;
	int fds[4];
	int strides[4];
	int offsets[4];
	uint64_t modifier;
};

struct gbm_bo *gbm_bo_import(struct gbm_device *gbm, uint32_t type, void *buffer, uint32_t usage)
{
	static struct gbm_bo *(*real)(struct gbm_device *, uint32_t, void *, uint32_t);
	struct gbm_bo *bo;

	if (!real)
		real = dlsym(RTLD_NEXT, "gbm_bo_import");
	/* Desktop Chrome is built against Mesa's gbm.h, where GBM_BO_IMPORT_FD_MODIFIER is 0x5504;
	 * in minigbm's gbm.h it is 0x5505 and 0x5504 is the removed GBM_BO_IMPORT_FD_PLANAR, so
	 * minigbm rejects every modifier import Chrome makes. The struct is the same in both. */
	if (type == 0x5504)
		type = 0x5505;
	bo = real(gbm, type, buffer, usage);
	if (trace()) {
		if (type == 0x5505) { /* GBM_BO_IMPORT_FD_MODIFIER (minigbm numbering) */
			struct gbm_import_fd_modifier_data *d = buffer;
			fprintf(stderr, "[gbm-linear-shim] pid %d import %ux%u %.4s fds %u stride %d/%d "
				"offset %d/%d mod 0x%llx usage 0x%x -> %p\n", getpid(), d->width,
				d->height, (const char *)&d->format, d->num_fds, d->strides[0],
				d->strides[1], d->offsets[0], d->offsets[1],
				(unsigned long long)d->modifier, usage, (void *)bo);
		} else {
			fprintf(stderr, "[gbm-linear-shim] pid %d import type 0x%x usage 0x%x -> %p\n",
				getpid(), type, usage, (void *)bo);
		}
	}
	return bo;
}

struct gbm_bo *gbm_bo_create(struct gbm_device *gbm, uint32_t width, uint32_t height,
			     uint32_t format, uint32_t flags)
{
	static struct gbm_bo *(*real)(struct gbm_device *, uint32_t, uint32_t, uint32_t, uint32_t);
	struct gbm_bo *bo;

	if (!real)
		real = dlsym(RTLD_NEXT, "gbm_bo_create");
	bo = real(gbm, width, height, format, flags);
	if (trace() && is_yuv(format))
		fprintf(stderr, "[gbm-linear-shim] pid %d create %ux%u %.4s flags 0x%x -> %p\n",
			getpid(), width, height, (const char *)&format, flags, (void *)bo);
	return bo;
}
