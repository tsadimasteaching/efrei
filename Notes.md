# Securing Containers

**Author:** Anargyros Tsadimas
**Role:** Teaching Laboratory Staff, DevOps & Software Engineer

---

## Contents

* [Prerequisites](#prerequisites)
* [Part 1: Linux Fundamentals](#part-1-linux-fundamentals)
    * [Explore setuid](#explore-setuid)
    * [Explore Linux Capabilities](#explore-linux-capabilities)
    * [Introduction to Containers and Namespaces](#introduction-to-containers-and-namespaces)
    * [Exploring and Using Linux Control Groups (cgroups v2)](#exploring-and-using-linux-control-groups-cgroups-v2)
    * [Exercise: Create an isolated environment without Docker](#exercise-create-an-isolated-environment-without-docker)
* [Part 2: Containers Threat Modeling and Attack Surface](#part-2-containers-threat-modeling-and-attack-surface)
* [Part 3: Runtime Hardening](#part-3-runtime-hardening)
    * [Capabilities](#capabilities)
    * [Seccomp](#seccomp)
    * [AppArmor](#apparmor)
* [Part 4: Secure Image Build and Scanning](#part-4-secure-image-build-and-scanning)
* [Part 5: Security Tools](#part-5-security-tools)
* [Part 6: Sandboxing](#part-6-sandboxing)

---

## Prerequisites

To follow the exercises in this guide, ensure you have the following setup:

* **Docker Engine:** [Installation Guide](https://docs.docker.com/engine/install/)
* **Security Tools:**
    * `strace`: [Install Guide](https://ioflood.com/blog/install-strace-command-linux/)
    * `grype`: [GitHub](https://github.com/anchore/grype)
    * `trivy`: [GitHub](https://github.com/aquasecurity/trivy)
    * `dive`: [GitHub](https://github.com/wagoodman/dive)
    * `amicontained`: [GitHub](https://github.com/genuinetools/amicontained)
* **Environment:** VirtualBox with Ubuntu Server (LTS 24.04.2), 4GB RAM, 2 CPUs.
* **SSH Config:** Add the following to the end of `/etc/ssh/sshd_config` and restart the service:
  ```text
  Match User stud
  PasswordAuthentication yes
  ```

---

## Part 1: Linux Fundamentals

### Explore setuid

setuid allows a user to execute a binary with the permissions of the file owner (e.g., root).

**1. Create `rootshell.c`**

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    printf("[+] Current UID: %d\n", getuid());
    printf("[+] Switching to /bin/sh as root...\n");
    setuid(0); // ensure we become root
    system("/bin/sh");
    return 0;
}
```

**2. Compile and set permissions**

```bash
gcc -o rootshell rootshell.c
sudo chown root:root rootshell
sudo chmod 4755 rootshell
ls -l rootshell
```

**3. Execution**

Running `./rootshell` as a normal user will result in a root prompt (`#`).

### Explore Linux Capabilities

Capabilities divide root privileges into smaller units.

**1. Create `filefixer.c`**

```c
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
    if (chown(filename, 969, 969) != 0) {
        perror("chown failed");
        return 1;
    }
    printf("Ownership changed to UID 969 and GID 969.\n");
    return 0;
}
```

**2. Test and Grant Capability**

```bash
gcc -o filefixer filefixer.c
touch file1
./filefixer file1 # Fails
sudo setcap 'cap_chown=+ep' ./filefixer
./filefixer file1 # Succeeds
```

### Introduction to Containers and Namespaces

Namespaces provide isolation for resources.

Check Namespaces: `ls -l /proc/1/ns/`

Using `unshare`:

```bash
sudo unshare --mount --uts --ipc --net --pid --fork sh
hostname spiderman
```

### Exploring and Using Linux Control Groups (cgroups v2)

Cgroups manage resource limits (CPU, Memory).

**1. Create a memory-limited group**

```bash
sudo mkdir /sys/fs/cgroup/my_cgroup
echo $((100*1024*1024)) | sudo tee /sys/fs/cgroup/my_cgroup/memory.max
```

**2. Add PID and Test:**

```bash
echo <PID> | sudo tee /sys/fs/cgroup/my_cgroup/cgroup.procs
# Run a memory-heavy process to trigger OOM kill
```

### Exercise: Create an isolated environment without Docker

**Setup rootfs:**

```bash
mkdir -p ~/sandbox/rootfs && cd ~/sandbox/rootfs
wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x busybox
mkdir bin proc dev sys tmp
mv busybox bin/
```

**Link Commands:**

```bash
cd bin
for cmd in sh ls ps echo cat mount uname hostname top id; do ln -s busybox $cmd; done
```

**Chroot:**

```bash
sudo unshare --mount --uts --ipc --net --pid --fork chroot ~/sandbox/rootfs /bin/sh
mount -t proc proc /proc
```

---

## Part 2: Containers Threat Modeling and Attack Surface

**Privileged Mode:** `--privileged` grants the container access to all host devices.

**Host Mounts:** Mounting `/` into a container allows full host access.

### Lab: Attacker's Mindset with amicontained

`amicontained` is a tool that shows you the runtime security configuration of a container from the inside -- capabilities, namespaces, seccomp status, and more.

#### Step 1: Run in a default container

```bash
docker run --rm ghcr.io/genuinetools/amicontained
```

Observe the output:
- Which capabilities are granted?
- Is seccomp filtering active?
- Which namespaces are enabled?

#### Step 2: Run in a privileged container

```bash
docker run --rm --privileged ghcr.io/genuinetools/amicontained
```

Compare with Step 1:
- Notice that **all capabilities** are now granted
- Seccomp is **disabled**
- Additional devices and host resources are accessible

#### Step 3: Run in a hardened container

```bash
docker run --rm \
  --cap-drop=ALL \
  --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --read-only \
  --user 1000:1000 \
  ghcr.io/genuinetools/amicontained
```

Compare with Steps 1 and 2:
- Only `NET_BIND_SERVICE` capability remains
- Seccomp is **active**
- `no-new-privileges` prevents privilege escalation

#### Step 4: Compare side by side

Create a simple comparison table from your observations:

| Feature | Default | Privileged | Hardened |
|---|---|---|---|
| Capabilities | ~14 default | ALL (40+) | 1 (NET_BIND_SERVICE) |
| Seccomp | Enabled (default profile) | Disabled | Enabled (default profile) |
| no-new-privileges | No | No | Yes |
| Namespaces | pid, net, mnt, uts, ipc | pid, net, mnt, uts, ipc | pid, net, mnt, uts, ipc |

> **Takeaway:** A default container is not secure. A privileged container is wide open. Always harden your containers by dropping capabilities and enabling security options.

---

## Part 3: Runtime Hardening

### Capabilities

Drop all privileges and add only what is needed:

```bash
docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine sh
```

### Seccomp

Filter system calls using a profile:

```json
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "syscalls": [
        { "names": ["ptrace"], "action": "SCMP_ACT_ERRNO" }
    ]
}
```

### AppArmor

Enforce profiles to restrict file and network access:

```bash
sudo apparmor_parser -r /etc/apparmor.d/docker-deny-write-etc
```

---

## Part 4: Secure Image Build and Scanning

**Use Minimal Base Images:** (e.g., `alpine`, `distroless`).

**Non-Root User:** Avoid running processes as UID 0.

**Scan for Vulnerabilities:**

```bash
trivy image insecure-image:latest
```

---

## Part 5: Security Tools

### Explore Falco

Monitor runtime activity and detect anomalies:

```bash
# Run Falco as a container to monitor the host
docker run --rm -it --privileged -v /var/run/docker.sock:/host/var/run/docker.sock ... falcosecurity/falco
```

---

## Part 6: Sandboxing

### Rootless Docker

Run the Docker daemon as a normal user to prevent host root compromise.

```bash
dockerd-rootless-setuptool.sh install
docker context use rootless
```