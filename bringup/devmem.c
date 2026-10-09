/* devmem <addr> [value]: 32-bit MMIO read (or write) through mmap of /dev/mem (busybox's applet isn't in the
 * test initramfs; plain read() on /dev/mem can't reach device memory on arm64). Static build:
 *   gcc -O2 -static -o devmem devmem.c */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: devmem <addr> [value]\n"); return 2; }
	uint64_t addr = strtoull(argv[1], NULL, 0), page = addr & ~0xfffULL;
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *p = mmap(NULL, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	p += (addr - page) / 4;
	if (argc > 2)
		*p = (uint32_t)strtoul(argv[2], NULL, 0);
	printf("0x%08x\n", *p);
	return 0;
}
