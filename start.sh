#!/bin/bash

# Prompt user for GitHub username
read -p "Enter your GitHub username: " GITHUB_USER
REPO_NAME="firewalla"

# Prompt for custom Docker Compose service name (optional)
read -p "Enter a custom Docker Compose service name (default: docker-in-docker): " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-docker-in-docker}

# Prompt for Docker image (default: docker:latest)
read -p "Enter Docker image to use (default: docker:latest): " DOCKER_IMAGE
DOCKER_IMAGE=${DOCKER_IMAGE:-docker:latest}

# Prompt for branch (optional)
read -p "Enter branch to clone (leave blank for default): " BRANCH_OPTION
BRANCH_CMD=""
if [ -n "$BRANCH_OPTION" ]; then
    BRANCH_CMD="-b $BRANCH_OPTION"
fi

# Define working directory
DIR=~/firewalla

# Check for Docker
echo "Checking if Docker is installed..."
if ! command -v docker &>/dev/null; then
    echo "❌ Docker is not installed. Please install it first."
    exit 1
fi

# Create main directory if it doesn't exist
if [ ! -d "$DIR" ]; then
    echo "📁 Creating main directory $DIR..."
    mkdir -p "$DIR"
else
    echo "📁 Main directory $DIR already exists."
fi

# Create subdirectory for Docker if it doesn't exist
DOCKER_DIR="$DIR/docker"
if [ ! -d "$DOCKER_DIR" ]; then
    echo "📁 Creating Docker directory $DOCKER_DIR..."
    mkdir -p "$DOCKER_DIR"
else
    echo "📁 Docker directory $DOCKER_DIR already exists."
fi

cd "$DIR"

# Clone the GitHub repo using HTTPS first (public)
if [ ! -d "$DIR/$REPO_NAME" ]; then
    echo "🌐 Cloning repository from GitHub..."
    git clone $BRANCH_CMD "https://github.com/$GITHUB_USER/$REPO_NAME.git"
else
    echo "✔️ Repository already exists."
fi

# Setup SSH for GitHub
SSH_KEY=~/.ssh/id_rsa
echo "🔐 Setting up SSH key..."

# Check if SSH key exists
if [ -f "$SSH_KEY" ]; then
    read -p "SSH key already exists. Overwrite? (y/n): " OVERWRITE
    if [[ "$OVERWRITE" == "y" ]]; then
        rm -f "$SSH_KEY" "$SSH_KEY.pub"
    fi
fi

# If key doesn't exist now, create it
if [ ! -f "$SSH_KEY" ]; then
    read -p "Enter your email for SSH key: " EMAIL
    ssh-keygen -t rsa -b 4096 -C "$EMAIL" -f "$SSH_KEY" -N ""
    echo "✅ SSH key generated."
fi

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add "$SSH_KEY"

# Show public key for GitHub
echo "🔑 Copy this SSH public key to GitHub:"
cat "$SSH_KEY.pub"
echo "➡️  Visit: https://github.com/settings/keys"
read -p "Press Enter after you've added the SSH key..."

# Test SSH access
echo "🔍 Testing SSH connection to GitHub..."
ssh -T git@github.com
if [ $? -ne 1 ]; then
    echo "❌ SSH authentication failed. Ensure the key is added to GitHub."
    exit 1
fi

# Switch repo to SSH remote
echo "🔁 Switching repository remote to SSH..."
cd "$DIR/$REPO_NAME"
git remote set-url origin git@github.com:$GITHUB_USER/$REPO_NAME.git

# Create setup.yml
echo "📝 Creating setup.yml..."

cat <<EOF > "$DIR/docker/setup.yml"

services:
  $SERVICE_NAME:
    image: $DOCKER_IMAGE
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

# Validate setup.yml
echo "🔍 Validating setup.yml..."
docker-compose -f "$DIR/docker/setup.yml" config || {
    echo "❌ setup.yml is invalid."
    exit 1
}

# Start Docker if not already running
echo "🚀 Starting Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Run docker-compose
echo "📦 Running Docker Compose..."
sudo docker-compose -f "$DIR/docker/setup.yml" up -d || {
    echo "❌ Failed to start Docker Compose."
    exit 1
}

# Confirm container is running
echo "🔍 Checking if container '$SERVICE_NAME' is running..."
if sudo docker ps | grep -q "$SERVICE_NAME"; then
    echo "✅ $SERVICE_NAME is up and running."
else
    echo "❌ Failed to start the container."
    sudo docker-compose down
    exit 1
fi

# Create systemd service
echo "⚙️ Creating systemd service for Docker Compose..."
sudo tee /etc/systemd/system/docker-compose-dind.service > /dev/null <<EOF
[Unit]
Description=Docker Compose for $SERVICE_NAME
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

# Reload and enable service
echo "🔁 Reloading systemd and enabling service..."
sudo systemctl daemon-reload
sudo systemctl enable docker-compose-dind.service
sudo systemctl start docker-compose-dind.service

echo "🎉 Setup complete! '$SERVICE_NAME' will auto-start on reboot."
