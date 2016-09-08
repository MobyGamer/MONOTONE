#include <stdio.h>

#define BUFFER_SIZE	32

int commitChunk(unsigned char times, unsigned short value, FILE *out_fptr)
{
	unsigned char buf[4];

	//printf("%d times 0x%04x\n", times, value);

	buf[0] = value;
	buf[1] = value >> 8;
	buf[2] = times;

	if (1 != fwrite(buf, 3, 1, out_fptr)) {
		perror("fwrite");
		return -1;
	}

	return 0;
}

int main(int argc, char **argv)
{
	FILE *in_fptr, *out_fptr;
	unsigned char buf[BUFFER_SIZE];
	int res;
	unsigned short current_value = 0;
	unsigned char current_stride = 0;
	long insize;

	if (argc != 3) {
		printf("Usage: ./pitcomp input.bin output.bin\n");
		return 1;
	}

	in_fptr = fopen(argv[1], "rb");
	if (!in_fptr) {
		perror("fopen");
		return -1;
	}

	fseek(in_fptr, 0, SEEK_END);
	insize = ftell(in_fptr);
	fseek(in_fptr, 0, SEEK_SET);

	out_fptr = fopen(argv[2], "wb");
	if (!out_fptr) {
		perror("fopen");
		return -1;
	}

	printf("Compressing music '%s' into '%s'....", argv[1], argv[2]);

	do {
		unsigned short val;
		res = fread(buf, 2, 1, in_fptr);
		if (res != 1) {
			if (feof(in_fptr))
				break;

			perror("fread");
			goto error;
		}

		// Throwing away the last 3 notes provides seemless loops. Bug somewhere.
		if (insize - ftell(in_fptr) <= 3)
			break;

		val = buf[0] | buf[1]<<8;

		if (current_value != val) {
			if (current_stride) {
				commitChunk(current_stride, current_value, out_fptr);
			}
			current_value = val;
			current_stride = 1;
		} else {
			current_stride++;
			// flush before an overflow occurs
			if (current_stride == 255) {
				commitChunk(current_stride, current_value, out_fptr);
			}
		}
	}
	while (!feof(in_fptr));

	if (current_stride) {
		commitChunk(current_stride, current_value, out_fptr);
	}
	printf(" Done. Input bytes: %ld, Output bytes: %ld\n", ftell(in_fptr), ftell(out_fptr));

	fclose(in_fptr);
	fclose(out_fptr);

	return 0;
error:
	if (in_fptr)
		fclose(in_fptr);

	return -1;
}
