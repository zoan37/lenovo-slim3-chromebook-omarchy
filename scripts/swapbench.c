// swapbench <MB> <source-file>: fill MB of anonymous memory with the source file's bytes (cycled), say "filled",
// wait for a line on stdin (the harness pushes the memory to swap meanwhile), then time faulting every page back in
// (one read per 4 KiB page, in a shuffled order like real access) and print the total and per-page time.
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(int argc, char **argv) {
	size_t mb = atoi(argv[1]), len = mb << 20, npg = len / 4096;
	int fd = open(argv[2], O_RDONLY); off_t sz = lseek(fd, 0, SEEK_END);
	char *src = mmap(0, sz, PROT_READ, MAP_PRIVATE, fd, 0);
	char *m = mmap(0, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
	madvise(m, len, MADV_NOHUGEPAGE);
	for (size_t o = 0; o < len; o += 4096) memcpy(m + o, src + (o * 7919 % (sz - 4096)) / 64 * 64, 4096);
	printf("filled\n"); fflush(stdout);
	char line[16]; if (!fgets(line, sizeof line, stdin)) return 1;
	size_t *ord = malloc(npg * sizeof *ord);
	for (size_t i = 0; i < npg; i++) ord[i] = i;
	srand(1); for (size_t i = npg - 1; i > 0; i--) { size_t j = rand() % (i + 1), t = ord[i]; ord[i] = ord[j]; ord[j] = t; }
	volatile char sink = 0; double t0 = now();
	for (size_t i = 0; i < npg; i++) sink += m[ord[i] * 4096 + 100];
	double dt = now() - t0;
	printf("%.0f ms for %zu pages, %.1f us/page\n", dt * 1e3, npg, dt * 1e6 / npg); fflush(stdout);
	return 0;
}
