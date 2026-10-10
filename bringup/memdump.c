/* memdump <addr> <len>: 32-bit MMIO reads of a whole range through one mmap of /dev/mem, printed as
 * "address: word word word word" lines (all-zero lines too, so two dumps diff line by line). Only for ranges whose
 * clocks and power are on: reading an unpowered block faults (SError). Static build:
 *   gcc -O2 -static -o memdump memdump.c */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: memdump <addr> <len>\n"); return 2; }
	uint64_t addr = strtoull(argv[1], NULL, 0) & ~3ULL, len = strtoull(argv[2], NULL, 0);
	uint64_t page = addr & ~0xfffULL, maplen = ((addr + len + 0xfff) & ~0xfffULL) - page;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *base = mmap(NULL, maplen, PROT_READ, MAP_SHARED, fd, page);
	if (base == MAP_FAILED) { perror("mmap"); return 1; }
	for (uint64_t a = addr; a < addr + len; a += 16) {
		printf("%010llx:", (unsigned long long)a);
		for (int i = 0; i < 4 && a + i * 4 < addr + len; i++)
			printf(" %08x", base[(a - page) / 4 + i]);
		printf("\n");
	}
	return 0;
}
