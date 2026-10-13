// tlbbench <MB> <thp 0|1>: random pointer chase over MB of memory (one hop per 4 KiB page, so nearly every access
// misses the TLB); prints ns per hop. With thp=0 the buffer is MADV_NOHUGEPAGE (4 KiB pages: full page walks).
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(int argc, char **argv) {
	size_t len = (size_t)atoi(argv[1]) << 20, n = len / 4096;
	char *m = mmap(0, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	madvise(m, len, atoi(argv[2]) ? MADV_HUGEPAGE : MADV_NOHUGEPAGE);
	size_t *perm = malloc(n * sizeof *perm);
	for (size_t i = 0; i < n; i++) perm[i] = i;
	srand(7); for (size_t i = n - 1; i > 0; i--) { size_t j = rand() % (i + 1), t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
	for (size_t i = 0; i < n; i++)   // a single cycle through all pages, at a varying offset within each page
		*(char **)(m + perm[i] * 4096 + (perm[i] % 60) * 64) = m + perm[(i + 1) % n] * 4096 + (perm[(i + 1) % n] % 60) * 64;
	char *p = m + perm[0] * 4096 + (perm[0] % 60) * 64; size_t hops = 20 * n;
	for (size_t i = 0; i < n; i++) p = *(char **)p;   // warm up
	double t0 = now();
	for (size_t i = 0; i < hops; i++) p = *(char **)p;
	double dt = now() - t0;
	printf("%zu MB thp=%s: %.1f ns/hop%s\n", len >> 20, argv[2], dt * 1e9 / hops, p ? "" : " ");
	return 0;
}
