#!/bin/bash

# Set the directory for the docker-compose.yml and other configurations
DIR=~/firewalla-git

# Check if Docker is installed and running
echo "Checking if Docker is installed and running..."
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed. Please install Docker before proceeding."
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

# Clone the repository publicly
echo "Cloning the repository publicly..."
if [ ! -d "$DIR/firewalla" ]; then
    git clone https://github.com/davviie/firewalla.git
else
    echo "Repository already cloned."
fi

# Set up SSH for GitHub
echo "Setting up SSH for GitHub..."
SSH_KEY=~/.ssh/id_rsa

# Check if an SSH key already exists
if [ ! -f "$SSH_KEY" ]; then
    echo "No SSH key found. Generating a new SSH key..."
    read -p "Enter your email address for the SSH key: " EMAIL
    ssh-keygen -t rsa -b 4096 -C "$EMAIL" -f "$SSH_KEY" -N ""
    echo "SSH key generated successfully."
else
    echo "SSH key already exists at $SSH_KEY."
fi

# Add the SSH key to the SSH agent
echo "Adding SSH key to the SSH agent..."
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY"

# Display the public key and prompt the user to add it to GitHub
echo "Copy the following SSH public key and add it to your GitHub account:"
cat "${SSH_KEY}.pub"
echo "Visit https://github.com/settings/keys to add the SSH key."
read -p "Press Enter after adding the SSH key to GitHub..."

# Test SSH connection to GitHub
echo "Testing SSH connection to GitHub..."
ssh -T git@github.com
if [ $? -ne 1 ]; then
    echo "Error: Unable to authenticate with GitHub via SSH. Please ensure your SSH key is added to your GitHub account."
    exit 1
fi

# Update the repository to use SSH for future operations
echo "Updating the repository to use SSH for future operations..."
cd "$DIR/firewalla"
git remote set-url origin git@github.com:davviie/firewalla.git

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
        cd /repo &&
        docker-compose up -d &&
        tail -f /dev/null
      "
EOF

# Validate docker-compose.yml
echo "Validating docker-compose.yml..."
docker-compose -f "$DIR/docker-compose.yml" config
if [ $? -ne 0 ]; then
    echo "Error: docker-compose.yml is invalid."
    exit 1
fi

# Launch Docker
echo "Starting Docker service..."
sudo systemctl start docker
if [ $? -ne 0 ]; then
    echo "Error: Failed to start Docker service."
    exit 1
fi

# Enable Docker to start on boot
echo "Enabling Docker to start on boot..."
sudo systemctl enable docker

# Run Docker Compose for Docker in Docker container
echo "Running Docker Compose to start Docker-in-Docker..."
sudo docker-compose -f "$DIR/docker-compose.yml" up -d
if [ $? -ne 0 ]; then
    echo "Error: Failed to start Docker Compose."
    exit 1
fi

# Check if Docker in Docker is running
echo "Checking if Docker-in-Docker is running..."
if sudo docker ps | grep -q 'docker-in-docker'; then
    echo "Docker-in-Docker is running successfully."
else
    echo "Error: Docker-in-Docker failed to start. Stopping Docker Compose..."
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
