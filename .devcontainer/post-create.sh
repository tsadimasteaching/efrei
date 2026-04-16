#!/bin/bash
set -e

# Install grype
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin

# Install trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Install dive
DIVE_VERSION=$(curl -sL https://api.github.com/repos/wagoodman/dive/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -OL "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb"
sudo dpkg -i "dive_${DIVE_VERSION}_linux_amd64.deb"
rm -f "dive_${DIVE_VERSION}_linux_amd64.deb"

# Pre-pull images used in labs
docker pull alpine
docker pull debian
docker pull jess/amicontained
docker pull quay.io/cilium/tetragon:v1.3.0

echo "All prerequisites installed successfully."
