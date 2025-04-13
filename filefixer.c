#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

int main(int argc, char *argv[]) {
	if (argc != 2) {
    	fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
    	return 1;
	}

	const char *filename = argv[1];

	// Change ownership to user ID 969 and group ID 969
	if (chown(filename, 969, 969) != 0) {
    	perror("chown failed");
    	return 1;
	}

	printf("Ownership of '%s' changed to UID 1000 and GID 1000.\n", filename);
	return 0;
}

