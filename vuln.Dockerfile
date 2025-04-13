# 🐧 Base image with known vulnerabilities
FROM ubuntu:20.04

# 🙈 Intentionally run as root (default, but we won't change it)
USER root

# Install tools and create an SUID binary
RUN apt-get update && \
    apt-get install -y \
        passwd \
        curl \
        net-tools \
        iputils-ping \
        sudo \
        vim && \
    chmod u+s /usr/bin/passwd && \
    echo "root:rootpass" | chpasswd

# Add a fake secret
RUN echo "AWS_SECRET=1234567890abcdef" > /root/.aws-creds

# Add a demo user
RUN useradd -m attacker && echo 'attacker:attacker' | chpasswd && adduser attacker sudo

# Expose a file with sensitive info
COPY secret.txt /etc/secret.txt

# Default command
CMD ["/bin/bash"]

