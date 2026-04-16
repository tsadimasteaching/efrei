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
docker run -it --rm --name vuln --privileged ubuntu bash
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
docker run -v /:/mnt -it ubuntu bash
ls /mnt/root
```

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

Restrict container privileges using security features.

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

Filter system calls using a profile.

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

**1. Install AppArmor:**

```bash
sudo apt install apparmor apparmor-profiles apparmor-utils
sudo apparmor_status
```

**2. Create a test script (`test.sh`):**

```bash
#!/bin/sh
echo "test" > /etc/testfile
```

```bash
chmod +x test.sh
```

**3. Create a Dockerfile (`apparmor.Dockerfile`):**

```dockerfile
FROM alpine
COPY test.sh /test.sh
RUN chmod +x /test.sh
CMD ["/test.sh"]
```

```bash
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

---

## Part 4: Secure Image Build and Scanning

### Compare Ubuntu vs Alpine base images

**Build a Ubuntu-based image (`mypythonubuntu.Dockerfile`):**

```dockerfile
FROM ubuntu
RUN apt update -y && apt install curl python3 -y
```

```bash
docker build -t mypythonubuntu -f mypythonubuntu.Dockerfile .
```

**Build an Alpine-based image:**

```dockerfile
FROM alpine
RUN apk add curl python3
```

```bash
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
docker build -f no-rules.Dockerfile -t no-rules .
trivy image --security-checks vuln,config,secret no-rules
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

---

## Part 5: Security Tools

### Explore Falco

Falco monitors runtime activity and detects anomalies using kernel-level instrumentation.

**1. Run Falco as a container:**

```bash
sudo docker run --rm -i -t --name falco --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev -v /proc:/host/proc:ro -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro -v /usr:/host/usr:ro -v /etc:/host/etc:ro \
  falcosecurity/falco:0.40.0
```

**2. Trigger an alert:**

In another terminal, run:

```bash
sudo cat /etc/shadow
```

Go back to the Falco terminal — you'll see a warning about sensitive file access.

### Create custom rules

**1. Write below `/etc` rule:**

Stop Falco with Ctrl-C. Download the custom rule:

```bash
wget https://raw.githubusercontent.com/tsadimasteaching/efrei/refs/heads/main/falco_custom_rules.yaml
```

Contents of `falco_custom_rules.yaml`:

```yaml
- rule: Write below etc
  desc: An attempt to write to /etc directory
  condition: >
    (evt.type in (open,openat,openat2) and evt.is_open_write=true and fd.typechar='f' and fd.num>=0)
    and fd.name startswith /etc
  output: >
    File below /etc opened for writing
    (file=%fd.name pcmdline=%proc.pcmdline gparent=%proc.aname[2]
    evt_type=%evt.type user=%user.name user_uid=%user.uid
    process=%proc.name proc_exepath=%proc.exepath
    parent=%proc.pname command=%proc.cmdline terminal=%proc.tty %container.info)
  priority: WARNING
  tags: [filesystem, mitre_persistence]
```

**2. Run Falco with the custom rule:**

```bash
sudo touch /etc/test_file_falco_rule
sudo docker run --name falco --rm -i -t --privileged \
  -v $(pwd)/falco_custom_rules.yaml:/etc/falco/falco_rules.local.yaml \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev -v /proc:/host/proc:ro -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro -v /usr:/host/usr:ro -v /etc:/host/etc:ro \
  falcosecurity/falco:0.40.0
```

In another terminal, write to `/etc` and observe Falco alerting.

### Detect shell spawned in containers

**1. Download the shell detection rule:**

```bash
wget https://raw.githubusercontent.com/tsadimasteaching/efrei/refs/heads/main/container_shell_detect.yaml
```

Contents of `container_shell_detect.yaml`:

```yaml
- rule: Shell in Container
  desc: Detect an interactive shell spawned inside a container
  condition: >
    container and proc.name in (bash, sh, zsh, ash) and
    evt.type = execve and
    not proc.pname in (docker, containerd, entrypoint)
  output: >
    Interactive shell detected inside container
    (container=%container.name command=%proc.cmdline user=%user.name)
  priority: NOTICE
  tags: [container, shell, behavioral]
```

**2. Run Falco with the shell detection rule:**

```bash
docker run --rm -it --name falco --privileged \
  -v /var/run/docker.sock:/host/var/run/docker.sock \
  -v /dev:/host/dev \
  -v /proc:/host/proc:ro \
  -v /boot:/host/boot:ro \
  -v /lib/modules:/host/lib/modules:ro \
  -v /usr:/host/usr:ro \
  -v /etc:/host/etc:ro \
  -v $(pwd)/container_shell_detect.yaml:/etc/falco/rules.d/container_shell_detect.yaml \
  falcosecurity/falco:0.40.0
```

**3. Trigger the alert:**

In another terminal:

```bash
docker run --rm -it alpine sh
```

Falco will report: `Interactive shell detected inside container`.

### Exercise: Monitor a real application with Falco

Check and run the Budibase docker-compose:

```bash
wget https://raw.githubusercontent.com/Budibase/budibase/master/hosting/docker-compose.yaml
docker compose up -d
```

Run Falco and observe the output. You may see alerts like:

```
Redirect stdout/stdin to network connection
(fd.sip=127.0.0.1 connection=127.0.0.1:41048->127.0.0.1:9000
process=bash command=bash -c :> /dev/tcp/127.0.0.1/9000
container_name=efrei-minio-service-1)
```

**Why is this suspicious?**
- `bash -c ':> /dev/tcp/127.0.0.1/9000'` opens a TCP connection and redirects output — this pattern is commonly used in reverse shells and data exfiltration
- The `dup2` event indicates file descriptor reassignment, typical in shell redirection attacks
- It ran as `root` inside the container

> Even loopback connections can be early stages of attack chains. Falco helps you identify these patterns in production.

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