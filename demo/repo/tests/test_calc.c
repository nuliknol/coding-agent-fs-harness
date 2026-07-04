#include <stdio.h>

#include "calc.h"

int main(void)
{
	if (calc_add(2, 3) != 5) {
		fprintf(stderr, "calc_add(2, 3) failed\n");
		return 1;
	}

	if (calc_add(-7, 4) != -3) {
		fprintf(stderr, "calc_add(-7, 4) failed\n");
		return 1;
	}

	puts("all tests passed");
	return 0;
}
