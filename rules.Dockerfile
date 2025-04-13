# Stage 1: Build (if needed)
FROM python:3.11-slim AS builder

WORKDIR /build

# Copy only what’s needed for install
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir --user -r requirements.txt

# Stage 2: Final image
FROM gcr.io/distroless/python3

WORKDIR /app

# Copy app and installed Python packages from builder
COPY --from=builder /build /app
COPY main.py /app

# Add non-root user
RUN adduser --disabled-password --gecos '' appuser \
 && chown -R appuser /app

USER appuser

# Restrict file permissions
RUN chmod 500 /app/main.py

# Make filesystem read-only
VOLUME /tmp
CMD ["main.py"]

