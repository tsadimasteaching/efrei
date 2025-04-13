# Use a large, mutable base image
FROM ubuntu:latest

# Install dependencies for Python and creating a virtual environment
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv curl

# Create a virtual environment
RUN python3 -m venv /env

# Install dependencies in the virtual environment
COPY requirements.txt .
RUN /env/bin/pip install --no-cache-dir -r requirements.txt

# Set working directory
WORKDIR /app

# Copy the application into the container
COPY . /app

# Set environment variable (e.g., secret! Avoid this in real production)
ENV API_KEY=my_secret_api_key

# Create a non-root user and assign ownership of the app directory
RUN adduser --disabled-password --gecos '' appuser \
 && chown -R appuser /app

USER appuser

# Expose port for FastAPI
EXPOSE 8000

# Run FastAPI app using the Python interpreter from the virtual environment
CMD ["/env/bin/python", "main.py"]

