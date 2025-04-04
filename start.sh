#!/bin/bash

# Set the directory for the docker-compose.yml and other configurations
DIR=~/davidlan

# Check if Docker is installed and running
echo "Checking if Docker is installed and running..."
if ! command -v docker &> /dev/null
then
    echo "Docker is not installed. Please install Docker before proceeding."
    exit 1
fi

# Create the directory if it doesn't exist
if [ ! -d "$DIR" ]; then
    echo "Creating directory $DIR..."
    mkdir -p "$DIR"
else
    echo "Directory $DIR already exists."
fi

# Navigate to the directory
cd "$DIR"

# Hardcoded GitHub Token
GITHUB_TOKEN="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"

# Create docker-compose.yml for Docker-in-Docker with restart policy
echo "Creating docker-compose.yml for Docker-in-Docker..."
cat <<EOF > docker-compose.yml

services:
  docker-in-docker:
    image: docker:latest
    privileged: true
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      sh -c "
        apk add --no-cache git &&
        git clone https://davviie:${GITHUB_TOKEN}@github.com/YOUR_USERNAME/YOUR_REPO.git /repo &&
        cd /repo &&
        docker-compose up -d &&
        tail -f /dev/null
      "
EOF

# Launch Docker
echo "Starting Docker service..."
sudo systemctl start docker

# Enable Docker to start on boot
echo "Enabling Docker to start on boot..."
sudo systemctl enable docker

# Run Docker Compose for Docker in Docker container
echo "Running Docker Compose to start Docker-in-Docker..."
sudo docker-compose -f "$DIR/docker-compose.yml" up -d

# Check if Docker in Docker is running
echo "Checking if Docker-in-Docker is running..."
if sudo docker ps | grep -q 'docker-in-docker'; then
    echo "Docker-in-Docker is running successfully."
else
    echo "Exiting with failure. Stopping the Docker Compose..."
    sudo docker-compose down
    exit 1
fi

# Create a systemd service to ensure Docker Compose starts on boot
echo "Creating systemd service for Docker Compose..."
sudo tee /etc/systemd/system/docker-compose-dind.service > /dev/null <<EOF
[Unit]
Description=Docker Compose for Docker-in-Docker
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=$DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
Restart=always
TimeoutSec=60

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
echo "Reloading systemd and enabling the service..."
sudo systemctl daemon-reload
sudo systemctl enable docker-compose-dind.service
sudo systemctl start docker-compose-dind.service

echo "Docker-in-Docker setup complete and will auto-start on reboot."

exit
