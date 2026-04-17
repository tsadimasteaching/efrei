# Securing Containers

This repository contains educational materials for the **Container Security** course at EFREI. All content is intended for **educational purposes only**.

**Author:** Anargyros Tsadimas — Assistant Professor, DevOps & Software Engineer

## Topics Covered

1. **Linux Fundamentals** — Unix permissions, setuid/setgid, capabilities, namespaces, cgroups v2
2. **Threat Modeling & Attack Surface** — Privileged containers, host mounts, Docker socket attacks
3. **Runtime Hardening** — Capabilities, Seccomp, AppArmor, Docker Compose hardening
4. **Secure Image Build & Scanning** — Trivy, Grype, Dive, multi-stage builds, Alpine vs Ubuntu
5. **Security Tools** — eBPF, Tetragon, custom TracingPolicies, Docker Bench for Security
6. **Sandboxing** — Rootless Docker

## Main Files

| File | Description |
|---|---|
| `Slides.md` | Marp slide deck for the course |
| `Lab.md` | Comprehensive hands-on lab guide |
| `vuln.Dockerfile` | Deliberately vulnerable Dockerfile for scanning exercises |
| `no-rules.Dockerfile` | Unhardened Dockerfile for comparison |
| `rules.Dockerfile` | Hardened Dockerfile with security best practices |
| `rootshell.c` | Demonstrates setuid privilege escalation |
| `filefixer.c` | Demonstrates Linux capabilities (`CAP_CHOWN`) |
| `docker-deny-write-etc` | AppArmor profile that denies writes to `/etc` |
| `write-etc-policy.yaml` | Tetragon TracingPolicy — monitor file opens under `/etc` |
| `container-shell-detect-policy.yaml` | Tetragon TracingPolicy — detect shells spawned in containers |
| `day1-docker-compose.yaml` | Docker Compose file used in exercises |
| `.devcontainer/` | GitHub Codespaces / Dev Container configuration |

## Prerequisites

- Docker Engine
- Ubuntu Server 24.04.2 (VirtualBox) or GitHub Codespaces
- Tools: `strace`, `trivy`, `grype`, `dive`, `amicontained`

See [Lab.md](Lab.md) for full setup instructions.

export slides to pdf

```bash
marp Slides.md --pdf --allow-local-files -o Slides.pdf
```