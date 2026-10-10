/* scplog <seconds> [addr]: capture the SCP firmware's log. The MT8189 scp.img formats every printf into one
 * 256-byte buffer (printf_buf, SCP SRAM 0x2ca8c = AP 0x1c42ca8c) and keeps nothing else, so poll it in a tight loop
 * from the AP and print each new line with a timestamp. SCP SRAM is readable whenever the SCP runs.
 *   gcc -O2 -static -o scplog scplog.c */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 5;
	uint64_t addr = argc > 2 ? strtoull(argv[2], NULL, 0) : 0x1c42ca8c;
	uint64_t page = addr & ~0xfffULL;
	int fd = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fd < 0) { perror("/dev/mem"); return 1; }
	volatile uint32_t *map = mmap(NULL, 0x2000, PROT_READ, MAP_SHARED, fd, page);
	if (map == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *buf = map + (addr - page) / 4;
	char cur[257], last[257] = "";
	struct timespec t0, t;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	unsigned long n = 0;
	for (;;) {
		for (int i = 0; i < 64; i++)
			memcpy(cur + 4 * i, (const void *)&buf[i], 4);	/* 32-bit reads only */
		cur[256] = 0;
		for (int i = 0; i < 256 && cur[i]; i++)
			if (cur[i] == '\n' || cur[i] == '\r' || (unsigned char)cur[i] < 32)
				cur[i] = ' ';
		if (strcmp(cur, last)) {
			clock_gettime(CLOCK_MONOTONIC, &t);
			printf("%9.6f %s\n", (t.tv_sec - t0.tv_sec) + (t.tv_nsec - t0.tv_nsec) / 1e9, cur);
			fflush(stdout);
			strcpy(last, cur);
		}
		if ((++n & 1023) == 0) {
			clock_gettime(CLOCK_MONOTONIC, &t);
			if ((t.tv_sec - t0.tv_sec) + (t.tv_nsec - t0.tv_nsec) / 1e9 > secs)
				break;
		}
	}
	return 0;
}
