---
marp: true
theme: default
paginate: true
style: |
  section {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  }
  section.title {
    background-color: #E8686D;
    color: white;
    text-align: center;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  section.title h1, section.title h2 {
    color: white;
  }
  section.small {
    font-size: 18px;
  }

  section.xsmall {
    font-size: 16px;
  }

  section.xxsmall {
    font-size: 14px;
  }
  h1 {
    color: #E8686D;
  }
  h2 {
    color: #E8686D;
  }
  code {
    background-color: #f0f0f0;
    padding: 2px 6px;
    border-radius: 3px;
  }
  pre {
    background-color: #2d2d2d;
    color: #f8f8f2;
    padding: 16px;
    border-radius: 8px;
  }
  table {
    font-size: 0.7em;
  }
---

<!-- _class: title -->

# Container Security

## dive into kernel foundations

---

# Contents

- Virtualization: Containers vs VMs
- Containers Standards
- Container Internals: The Kernel Foundations
  - Namespaces
  - Control Groups
  - Linux Capabilities
- Attack Surface
- Securing the Container Build Process
- Securing the Container Runtime Process
- Container Sandboxing Approaches

---
<!-- _class: small -->

# Virtualization

Resource virtualization

Pretend that we have many CPUs

- A single CPU is time-sliced across multiple threads (T1, T2, T3)
- Each thread believes it has its own dedicated processor

![h:400](./img/virtualization.png)

---

<!-- _class: small -->

# Virtualization

It is the process of creating a virtual representation of something based on software, such as a virtual application, server, storage or network

- Each VM runs its own OS on top of a **Virtualization layer (Hypervisor)**
- All running on a **Physical server**

![h:400](./img/virtualization-vm.png)

---

# Virtualization



![h:800](./img/virt-types.png)

---

# Container Ecosystem

![h:700](./img/ecosystem.png)

---

# Container Standards

**Open Container Initiative** (OCI): a set of standards for containers, describing the image format, runtime, and distribution.
- low-level specs: standardizes container images, runtimes, and registries.
- NOT specific to kubernetes.

**Container Runtime Interface** (CRI) in Kubernetes: An API that allows you to use different container runtimes in Kubernetes.
- high-level specs: enables kubelet to talk to any OCI compliant container runtimes.
- specific to Kubernetes.

---

<!-- _class: xsmall -->

# All together


![h:400](./img/cri.png)


- **CRI** defines how Kubernetes interacts with different container runtimes
- **OCI** provides specifications for container images and running containers
- **runc** is an OCI-compliant tool for spawning and running containers

---

# Docker projects

```
docker --> containerd --> OCI spec --> runc --> container
```

- End users create and run containers with the **docker** command.
- **containerd** pulls images, manages networking & storage, and uses runc to run containers.
- **runc** does the low-level 'stuff' to create and run containerised processes.

---

# Containerd vs CRI-O

**containerd**

containerd is a high-level container runtime that came from Docker. It implements the CRI spec. It pulls images from registries, manages them and then hands over to a lower-level runtime, which uses the features of the Linux kernel to create processes we call 'containers'.

**CRI-O**

CRI-O is another high-level container runtime which implements the Kubernetes Container Runtime Interface (CRI). It's an alternative to containerd.

Detect which one is used in kubernetes: `kubectl get nodes -o wide`

---

# runc

**runc** is an OCI-compatible container runtime. It implements the OCI specification and runs the container processes.

runc is sometimes called the "reference implementation" of OCI.

**runc** provides all of the low-level functionality for containers, interacting with existing low-level Linux features, like **namespaces** and **control groups**. It uses these features to create and run container processes.

runc is a tool for running containers on Linux. On Windows, the equivalent is Microsoft's Host Compute Service (HCS) with **runhcs**.

---

# Definitions

- **Container engine** - accepts user requests, pulls images, and from the end user's perspective runs the container

- **Container runtime** - manages the container lifecycle: configuring its environment, running it, stopping it
  - **high level** container runtimes (CRI) - the valves which feed the pistons
  - **low level** container runtimes - the pistons which do the heavy lifting

- **Container orchestrator** - manages sets of containers across different computing resources, handling network and storage configurations

---

# Comparison

| Task | Container Engine (docker,podman) | Container Runtime (containerd, runc) |
|---|---|---|
| Image Build | YES | NO |
| Image management | YES | YES |
| Container Lifecycle Management | YES | YES |
| Container Orchestration | YES | NO |
| Networking | YES | NO |
| Volume Management | YES | LIMITED |
| Logging | YES | LIMITED |
| Security and Access Controls | YES | LIMITED |
| cli/API | YES | LIMITED |
| Resource Management | YES | YES |

---

# Alternatives

| Feature | Docker | containerd | LXD | BuildKit | Podman | buildah | runc |
|---|---|---|---|---|---|---|---|
| Performance | High with caching | Efficient, low overhead | High with system containers | Optimized for concurrent ops | Comparable to Docker | Optimized for OCI images | Low-level tool |
| Security | Namespaces, cgroups, SELinux | Namespaces, cgroups | Unprivileged containers | Content-addressable | Rootless, daemonless | Rootless build | Namespaces and cgroups |
| Ease of Use | User-friendly CLI | Lower-level API | Simple REST API | Low-Level Build | Native CLI, similar to Docker | Simple CLI for images | Used indirectly |

---

<!-- _class: title -->

# Container Internals: The Kernel Foundations

---

# Linux System Calls

Applications run in what's called **user space**, which has a lower level of privilege than the operating system kernel.

If an application wants to do something like access a file, communicate using a network, or even find the time of day, it has to **ask the kernel** to do it on the application's behalf. The programmatic interface that the user space code uses to make these requests of the kernel is known as the **system call** or **syscall** interface.

```
User Program -> C library -> [System Call] -> Kernel
  write()      libc write()                  sys_write()
```

---

# Linux System Calls

There are some 300+ different system calls:

- `read` - read data from a file
- `write` - write data to a file
- `open` - open a file for subsequent reading or writing
- `execve` - run an executable program
- `chown` - change the owner of a file
- `fork` - create a new process

Example:
```bash
strace -f -e trace=all cat /etc/passwd
strace -c cat /etc/passwd
ausyscall --dump  # see all system calls
```

---

# Permissions

```
- r w x r w x r w x
|  |       |       |
|  |       |       +-- Read, write, and execute for all other users
|  |       +---------- Read, write, and execute for group owner
|  +------------------ Read, write, and execute for file owner
+--------------------- File type (- = regular, d = directory)
```

Numeric mode example: `754`
- **7** (user): rwx = 4+2+1
- **5** (group): r-x = 4+0+1
- **4** (other): r-- = 4+0+0

---

# Permissions

**Setuid** - "Regardless of who runs this program, run it as the user who owns it, not the user that executes it."
```bash
ls -l /usr/bin/passwd
-rwsr-xr-x 1 root root 68208 /usr/bin/passwd
```

**Setgid** - When used on a file, it executes with the privileges of the group of the user who owns it.

**Sticky Bits** - When a directory has the sticky bit set, its files can be deleted or renamed only by the file owner, directory owner and the root user.
```bash
drwxrwxrwt 26 root root 1191936 tmp
```

---

# Security implications of setuid

Imagine what would happen if you set setuid on, say, bash. Any user who runs it would be in a shell, running as the root user.

Because setuid provides a dangerous pathway to privilege escalation, some container image scanners will report on the presence of files with the setuid bit set.

You can also prevent it from being used with the `--no-new-privileges` flag on a docker run command.

---

# Linux Capabilities

- In traditional Linux systems, the root user (UID 0) has all privileges. However, this "all-or-nothing" model can be risky.
- **Linux Capabilities** break down root's powers into distinct units, allowing processes to get only the privileges they actually need -- improving security.
- **Split the root permission into small pieces** that are able to be distributed individually on a thread basis without having to grant all permissions to a specific process at once

---

# Linux Capabilities - how to?

There are two ways a process can obtain a set of capabilities:

- **Inherited capabilities**: A process can inherit a subset of the parent's capability set. To inspect: `/proc/<PID>/status`

- **File capabilities**: It's possible to assign capabilities to a binary, e.g. using `setcap`. The process created when executing a binary of this type is then allowed to use the specified capabilities on runtime.

---

# Linux Capabilities

```bash
$ ps
    PID TTY          TIME CMD
 142586 pts/1    00:00:01 zsh

$ cat /proc/142586/status | grep Cap
CapInh: 0000000800000000
CapPrm: 0000000000000000
CapEff: 0000000000000000
CapBnd: 000001ffffffffff
CapAmb: 0000000000000000

$ capsh --decode=000001ffffffffff
0x000001ffffffffff=cap_chown,cap_dac_override,...

$ getpcaps 142586
142586: cap_wake_alarm=i
```

---

# Linux Capabilities - how to?

- **CapInh** -- Inherited - Which capabilities can be passed from parent to child processes during exec()
- **CapPrm** -- Permitted - What the process is allowed to make effective or pass to child processes
- **CapEff** -- Effective - What the process is currently allowed to do
- **CapBnd** -- Bounding - Hard limit for the process and its children. You can't ever get a capability if it's not in this set
- **CapAmb** -- Ambient - A newer mechanism to preserve capabilities across exec() without needing special binaries

---

# Linux Capabilities examples

- `CAP_NET_BIND_SERVICE` - Bind to ports < 1024 (e.g., port 80)
- `CAP_SYS_ADMIN` - Powerful & broad: mount filesystems, set hostname, etc. Often called "the new root"
- `CAP_NET_ADMIN` - Modify network interfaces, routing tables
- `CAP_SYS_TIME` - Change system clock
- `CAP_CHOWN` - Change file ownership
- `CAP_DAC_OVERRIDE` - Bypass file permission checks
- `CAP_SETUID` / `CAP_SETGID` - Change user/group IDs

To see all: `man 7 capabilities`

---

# Replacing setuid with capabilities

Assigning the setuid bit to binaries is a common way to give programs root permissions. Linux capabilities is a great alternative to reduce the usage of setuid.

Example:
```bash
$ ls -l $(which passwd)
-rwsr-xr-x 1 root root 80856 /usr/bin/passwd
```

Instead of giving full root via setuid, grant only the specific capability needed.

---

# Linux Capabilities in containers

By default, containers may run as root but with reduced capabilities, making them safer than full root access.

Example:
```bash
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE myapp
```

This drops all privileges, then only adds the ability to bind to low ports.

---

# Linux Capabilities

The `capsh` command can run a particular process and restrict the set of available capabilities.

```bash
$ capsh --print -- -c "/bin/ping -c 1 localhost"
# ping works

$ capsh --drop=cap_net_raw --print -- -c "/bin/ping -c 1 localhost"
# unable to raise CAP_SETPCAP for BSET changes: Operation not permitted
```

If we drop the `CAP_NET_RAW` capabilities for ping, then the ping utility should no longer work.

---

# Linux Capabilities commands

| Command | Description |
|---|---|
| **capsh** | capability shell wrapper to test Linux capabilities |
| **captest** | performs a set of tests related to capabilities |
| **filecap** | shows available capabilities set on binaries in $PATH |
| **firejail** | sandboxes applications |
| **getcap** | queries the available file capabilities |
| **getpcaps** | shows the available process capabilities |
| **netcap** | shows network-related processes and their capabilities |
| **pscap** | shows overview of processes and their assigned capabilities |
| **setcap** | adds or removes available file capabilities |

---

# Docker is based on

**Namespaces** - Isolate what a process sees - Separate hostname, PID space, network

| Processes | Hard drive | Network |
|---|---|---|
| Users | Hostnames | Inter Process Communication |

**Cgroups** - Limit what a process can use - Limit CPU, memory, I/O

| Memory | CPU Usage | HD I/O |
|---|---|---|
| Network Bandwidth | | |

---

# Namespaces

Namespaces are a Linux kernel feature released in kernel version 2.6.24 in 2008. They provide **processes** with **their own system view**, thus **isolating** independent processes from each other. In other words, namespaces **define the set of resources that a process can use** (You cannot interact with something that you cannot see).

At a high level, they allow fine-grain partitioning of global operating system resources such as mounting points, network stack and inter-process communication utilities. They are represented as files under the `/proc/<pid>/ns` directory.

---

# Namespaces

- **user** namespace - its own set of user IDs and group IDs. Root inside != root outside
- **process ID** (PID) namespace - independent set of PIDs. First process is PID 1
- **network** namespace - independent network stack: routing table, IP addresses, sockets, firewall
- **mount** namespace - independent list of mount points
- **IPC** namespace - its own IPC resources (POSIX message queues)
- **UTS** namespace - different host and domain names

```bash
unshare --user --pid --map-root-user --mount-proc --fork bash
```

---

# User namespace

- Isolates user and group IDs
- Allows a process to have root privileges inside the container but map to a non-root user outside (on the host)

```bash
$ id
uid=1000(rg) gid=1000(rg) groups=1000(rg),963(docker),998(wheel)

$ unshare -U /bin/bash
[nobody@rg-norbloc ~]$ id
uid=65534(nobody) gid=65534(nobody) groups=65534(nobody)
```

If a user ID has no mapping inside the namespace, system calls return the value `65534` (overflowuid).

---

# Process namespaces

- Isolates process IDs
- Processes in one namespace can't see or affect processes in another. Each container can have its own process tree, starting from PID 1.

**PID namespace isolation**: processes in the child namespace have no way of knowing of the parent process's existence. However, processes in the parent namespace have a complete view of processes in the child namespace.

---

# Network namespaces

- Isolates network resources like interfaces, IP addresses, ports, and routing tables
- Containers can have separate network stacks

A network namespace allows each process to see an entirely different set of networking interfaces. Even the loopback interface is different for each network namespace.

```bash
ip a
sudo unshare --net /bin/bash
ip a
```

---

# mount namespace

- Isolates filesystem mount points
- Each container can have its own view of the filesystem

Linux maintains a data structure for all the mountpoints of the system. With namespaces, this data structure can be cloned so that processes under different namespaces can change the mountpoints without affecting each other.

```bash
sudo unshare --fork --pid /bin/bash
ps   # still sees host processes
sudo unshare --fork --pid --mount-proc /bin/bash
ps   # only sees processes in this namespace
```

---

# IPC namespace

- Isolates hostname and domain name
- Containers can have custom hostnames different from the host system

The IPC namespace provides isolation for process communication mechanisms such as semaphores, message queues, shared memory segments, etc. The processes inside an IPC namespace can't see or interact with the IPC resources of the upper namespace.

---

# Useful namespaces commands

- **unshare** - run a program in a new namespace, isolating it from the parent process
- **lsns** - lists the current namespaces on the system
- **ip netns** - is part of the iproute2 suite and is used to manage network namespaces
- **nsenter** - enter an existing namespace of another process

---

# cgroups

A control group (cgroup) is a Linux kernel feature that limits, accounts for, and isolates the resource usage (CPU, memory, disk I/O, network) of a collection of processes.

Cgroups provide:

- **Resource limits** -- limit how much of a resource a process can use
- **Prioritization** -- control resource usage compared to other cgroups
- **Accounting** -- resource limits are monitored and reported
- **Control** -- change the status (frozen, stopped, restarted) of all processes in a cgroup

---

# cgroups

Check version:
```bash
mount -l | grep cgroup
```

Create a new cgroup:
```bash
mkdir /sys/fs/cgroup/my_cgroup
ls /sys/fs/cgroup/my_cgroup
echo "100M" | sudo tee /sys/fs/cgroup/my_cgroup/memory.max
```

---

# Linux vs Windows

**Architecture In Linux:**
Docker Client -> REST Interface -> Docker Engine (libcontainerd, libnetwork) -> containerd + runc -> Control Groups, Namespaces, Layer Capabilities (AUFS, btrfs, zfs)

**Architecture In Windows:**
Docker Client -> REST Interface -> Docker Engine (libcontainerd, libnetwork) -> runhcs -> Host Compute Service -> Control Groups (Job objects), Namespaces (Object Namespace, Process Table), Layer Capabilities (Registry, Union-like filesystem extensions)

> runhcs is a fork of runc

---

# Linux containers on Windows

- Windows uses a **Moby VM** (Full Hyper-V Virtual Machine) as a Linux Container Host
- Docker Client on Windows Container Host communicates with Docker Daemon in the Linux Container Host
- Windows Process Containers run on NT Kernel
- Linux Process Containers run on Linux Kernel
- Both run on top of a hypervisor

---

# Security Challenges in Containers vs. VMs

| | Containers | VMs |
|---|---|---|
| **Isolation** | Weaker. Shared host kernel | Stronger. Own OS and kernel |
| **Attack Surface** | Larger. Runtime, images, registries, orchestrators | Smaller. Hypervisor and guest OS |
| **Kernel Sharing** | All share host kernel | Separate kernels |
| **Image Security** | Relies on trusted base images | Less exposure to untrusted images |
| **Configuration** | Complex, prone to misconfig | More straightforward |
| **Resource Isolation** | cgroups, can be bypassed | Harder to escape |
| **Runtime Security** | Difficult to monitor ephemeral workloads | Easier to monitor |

---

<!-- _class: title -->

# Attack Surface

---

# Attack surface

1. **Via Network**
2. **Host Configuration**
3. **Host Vulnerabilities**
4. **Host Application Vulnerabilities**
5. **Container Orchestration Vulnerabilities, Misconfigurations**
6. **Compromised Container Images**
7. **Container Vulnerabilities, Misconfigurations**
8. **Container Escape**

---

# Attack via Network

**Attack Vector:** Malicious Network Traffic -- Containers may be exposed to untrusted networks unintentionally.

**Example:**
- A containerized app runs with `-p 80:80` and is unintentionally exposed to the internet. If the app has a known RCE vulnerability, an attacker can directly access it.
- Scanning for open ports and exploiting misconfigurations to gain access to worker nodes.

**Mitigation:**
Use network policies, only expose needed ports, use firewalls and reverse proxies.

---

# Attack via Host Configuration

**Attack Vector:** Misconfigured Host System

**Examples:**
- Discovering insecure file permissions to access sensitive files, such as container configuration files.
- Running a container with `--privileged` grants it almost full access to the host.

**Mitigation:**
Never use `--privileged` unless absolutely necessary. Use seccomp, AppArmor, and drop capabilities.

---

# Attack via Host Vulnerabilities

**Attack Vector:** Unpatched Host Vulnerabilities

**Example:**
- Identifying and exploiting unpatched kernel vulnerabilities to gain root privileges on worker nodes.
- An unpatched kernel vulnerability (like Dirty COW) can be exploited from a container to escalate privileges to host root.

**Mitigation:**
Keep the host OS and kernel up to date. Use security modules like SELinux/AppArmor.

---

# Attack via Host Application Vulnerabilities

**Attack Vector:** Unpatched Host Application Vulnerabilities

**Description:** Exploiting vulnerabilities in host applications to gain access to the container environment.

**Example:** Targeting older versions of Docker with vulnerabilities to gain root privileges on worker nodes.

---

# Attack via Container Orchestration Vulnerabilities

**Attack Vector:** Misconfigured Container Orchestration

**Description:** Exploiting misconfigurations in the container orchestration system to gain access to the container environment.

**Example:** Taking advantage of insecure access control policies in Kubernetes clusters to access pods and services.

---

# Attack via Compromised Container Images

**Attack Vector:** Attacker Gains Access to Container Image Build Process

**Description:** Compromising the container image build process to inject malicious code into container images.

**Example:** Exploiting vulnerabilities in CI/CD pipelines to inject malicious code during the container image build process.

---

# Attack via Container Vulnerabilities and Misconfigs

**Attack Vector:** Unpatched Container Vulnerabilities

**Description:** Exploiting vulnerabilities in the container itself to gain access to the container environment.

**Example:** Targeting unpatched vulnerabilities in popular applications running within containers to gain access.

---

# Attack via Container Escape

**Attack Vector:** Attacker Gains Privileged Access to Container

**Description:** Breaking out of the container's isolation and gaining access to the host system.

**Example:**
- Exploiting vulnerabilities in the container runtime or abusing host system misconfigurations
- Using a misconfigured capability like `CAP_SYS_ADMIN` or a kernel exploit to mount host directories

```bash
docker run --cap-add=SYS_ADMIN -v /:/mnt alpine chroot /mnt
```

**Mitigation:**
Use runtime security (gVisor, Kata Containers), drop unnecessary capabilities, use seccomp and AppArmor.

---

# Container security spans the full lifecycle

**Build Phase** - risks: Malicious Images, Vulnerabilities, Compliance Risks

**Pipeline** - Image Analysis, Scan Registries, Enforce Compliance, Scan Malware, Validate Deployments

**Run Phase** - Detect Drift and Threats, Monitor and Enforce Compliance, Detect and Stop Attacks, Block Vulnerabilities

---

<!-- _class: title -->

# Securing the Container Build Process

---

# Rules

- Use Minimal Base Images
- Pin Image Versions
- Run as Non-Root User
- Use Multi-Stage Builds
- Scan Images for Vulnerabilities
- Use .dockerignore File
- Avoid Hardcoding Secrets
- Set Permissions on Files
- Digitally Sign Images
- Enable read-only filesystem
- Least privilege

---

# Use Minimal Base Images

Reduces attack surface and image size.

Instead of:
```dockerfile
FROM ubuntu:latest
```

Use:
```dockerfile
FROM python:3.11-alpine
```

---

# Pin Image Versions

Avoids pulling updated images with unknown changes or vulnerabilities.

Use:
```dockerfile
FROM node:18.16.1-alpine
```

Instead of:
```dockerfile
FROM node
```

Latest image can have vulnerabilities. Avoid Using `latest` Tag -- it can lead to inconsistent or insecure builds.

---

# Run as Non-Root User

Limits the damage if the container is compromised.

Bad:
```dockerfile
FROM node:18
WORKDIR /app
COPY . .
CMD ["node", "server.js"]  # runs as root user
```

Good:
```dockerfile
FROM node:18
WORKDIR /app
RUN adduser -D myuser
USER myuser
COPY . .
CMD ["node", "server.js"]
```

---

# Use Multi-Stage Builds

Keeps final image clean by excluding build tools and secrets.

```dockerfile
### Stage 1: Build the frontend ###
FROM node:18.17.0-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

### Stage 2: Serve with NGINX ###
FROM nginx:1.25-alpine
COPY --from=builder /app/build /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

---

# Scan Images for Vulnerabilities

Detects known CVEs in images.

Tools:
- **Grype** - https://github.com/anchore/grype
- **Trivy** - https://github.com/aquasecurity/trivy
- **docker scout** - https://docs.docker.com/scout/
- **Snyk** - https://docs.snyk.io/scan-with-snyk/snyk-container/scan-container-images

---

# Use .dockerignore File

Prevents sensitive files (e.g., .env, .git) from being added to images.

```
# Ignore node_modules
node_modules

# Ignore log files
*.log

# Ignore sensitive environment variables
.env

# Ignore Docker-related files
Dockerfile*
.dockerignore
.git
/test/
*.spec.js
*.tmp
```

---

# Avoid Hardcoding Secrets

Secrets can get baked into layers and be exposed.

Bad:
```dockerfile
ENV DB_PASSWORD=supersecret
```

Good:
- Use runtime secret management (e.g., Docker secrets, Kubernetes secrets)
- Inject at runtime via environment variables

---

# Set Permissions on Files

Prevents unintended access.

```dockerfile
COPY config.yaml /etc/myapp/config.yaml
RUN chmod 640 /etc/myapp/config.yaml
```

---

# Digitally Sign Images

Ensures image integrity and authenticity.

Tools:
- **Cosign** - https://github.com/sigstore/cosign
- **Content trust in Docker** - https://docs.docker.com/engine/security/trust/

```bash
cosign sign myapp:1.0
cosign verify myapp:1.0
```

---

# Enable read-only filesystem

Disallow writes in filesystem:

```bash
docker run --read-only --tmpfs /tmp mysecureimage
```

---

# Least privilege

- Use `--cap-drop=ALL` to remove unnecessary capabilities
- Avoid `--privileged` flag

```bash
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE --read-only mysecureimage
```

---

<!-- _class: title -->

# Securing the Container Runtime Process

---

# Seccomp

**Secure Computing Mode** (seccomp), a crucial **Linux kernel component** empowers administrators and developers to **restrict the system calls** available to a process. It provides a secure, controlled environment for applications, limiting their interaction with the kernel to only authorized system calls.

Seccomp functions as a **system call filter**, acting as a gatekeeper between applications and the kernel.

By limiting the syscalls a process can use, you reduce the attack surface -- which is critical for sandboxing, containers, and running untrusted code.

---

# Seccomp modes

**No Filtering** - no seccomp filtering is applied. The process can make any system call.

**Strict Mode** - allows only `read()`, `write()`, `_exit()`, and `sigreturn()`

**Filter Mode** (most common) - define fine-grained rules (via BPF -- Berkeley Packet Filter). Allow, deny, or trap specific syscalls.

**Block All** - all system calls are blocked. Most restrictive mode.

---

# AppArmor

**AppArmor** (Application Armor) is a Linux security module (LSM) that lets you define and enforce security policies for individual programs.

Think of it as a "per-application firewall" -- it controls what a program can access:

- Files and directories
- Network access
- Capabilities (like setuid, chown, etc.)
- Mount points
- Ptrace/debug permissions

---

# SELinux

**SELinux** (Security-Enhanced Linux) is a mandatory access control (MAC) system built into the Linux kernel. It enforces fine-grained security policies on processes, files, users, and more -- going far beyond traditional Unix permissions.

Think of it as the bodyguard of the Linux kernel:

It checks every action before it happens and asks:
*"Is this allowed under the security policy?"*

---

# SELinux Modes

- **Enforcing** - Policies are applied and enforced (secure mode)
- **Permissive** - Violations are logged but not blocked (great for testing)
- **Disabled** - SELinux is turned off

---

# SELinux vs AppArmor

| Feature | Seccomp | AppArmor | SELinux |
|---|---|---|---|
| **Purpose** | Restricts system calls | Restricts file access & capabilities | Mandatory Access Control (MAC) |
| **Granularity** | Fine-grained (syscall level) | Medium (paths & exec profiles) | Very fine-grained (label-based) |
| **Default Behavior** | Allow all, unless filtered | Deny unless permitted | Deny unless policy allows |
| **Policy Format** | JSON or BPF filters | Plaintext profiles | Policy rules with types & labels |
| **Ease of Use** | Moderate | Easier (Ubuntu default) | Complex, steep learning curve |
| **Container Use** | Common in Docker, K8s | Used in Ubuntu, Docker/K8s | Default in RedHat, Fedora, OpenShift |
| **Portability** | Very portable | Less portable | Low portability |

---

<!-- _class: title -->

# Container Sandboxing Approaches

---

# Linux Security Modules (LSMs)

**AppArmor**
- Uses profiles to restrict system calls and file access per application/container
- Easier to configure and audit
- Default in Ubuntu

**SELinux**
- Provides fine-grained Mandatory Access Control (MAC)
- More complex than AppArmor but more powerful
- Default in Red Hat-based systems

---

# Seccomp (Secure Computing Mode)

- Filters system calls a container can make
- Allows or denies syscalls using profiles (JSON)
- Useful for reducing kernel attack surface

Example:
```bash
docker run --security-opt seccomp=profile.json myimage
```

---

# Capabilities Dropping

Linux capabilities can be dropped or added selectively.

Reduces the privileges of the container process.

```bash
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myimage
```

---

# User Namespaces

Map container users to non-privileged users on the host.

Prevents root in the container from being root on the host.

Docker: `--userns=host` or `--userns-remap`

---

# gVisor (User-space Kernel)

- Sandboxed container runtime developed by Google
- Intercepts syscalls and emulates them in user space
- Highly secure but with a performance trade-off

https://gvisor.dev/docs/user_guide/install/

---

# Kata Containers

- Lightweight VMs for containers
- Uses KVM (Kernel-based Virtual Machine) to provide VM-level isolation
- Ideal for multi-tenant environments

---

# Firecracker

- MicroVM-based runtime by AWS (used in Lambda)
- Low overhead, high isolation
- Not full-featured like Docker but great for serverless/container workloads

---

# Rootless Containers

- Run containers without root privileges
- Available in Docker, Podman, and containerd
- Reduces the risk of container escape

Rootless mode executes the Docker daemon and containers inside a user namespace. Both the daemon and the container are running without root privileges.

- https://docs.docker.com/engine/security/rootless/
- https://docs.docker.com/engine/security/rootless/#known-limitations
