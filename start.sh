#!/bin/bash

# Purge all Docker containers, images, volumes, and networks
echo "🧹 Purging all Docker containers, images, volumes, and networks..."
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    sudo docker-compose down --volumes --remove-orphans || true
else
    echo "⚠️ No docker-compose.yml file found. Skipping docker-compose down."
fi
sudo docker stop $(docker ps -aq) 2>/dev/null || true
sudo docker rm $(docker ps -aq) 2>/dev/null || true

# Check if the Docker image exists locally
if sudo docker images | grep -q "docker:latest"; then
    echo "✅ Docker image 'docker:latest' already exists. Skipping image removal."
else
    echo "🧹 Removing all Docker images..."
    sudo docker rmi -f $(docker images -q) 2>/dev/null || true
fi

sudo docker volume rm $(docker volume ls -q) 2>/dev/null || true
sudo docker network rm $(docker network ls -q) 2>/dev/null || true
echo "✅ Docker environment purged."

# Restart Docker to fix DNS issues
echo "🔄 Restarting Docker service to fix DNS issues..."
sudo systemctl restart docker
if [ $? -ne 0 ]; then
    echo "❌ Failed to restart Docker. Please check your Docker installation."
    exit 1
fi

# Prompt user for GitHub username
read -p "Enter your GitHub username: " GITHUB_USER
REPO_NAME="firewalla"

# Define Docker Compose service name
SERVICE_NAME="docker-in-docker"

# Define Docker image
DOCKER_IMAGE="docker:latest"

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

# Clone the GitHub repo using HTTPS first (public)
if [ ! -d "$DIR/$REPO_NAME" ]; then
    echo "🌐 Cloning repository from GitHub..."
    git clone "https://github.com/$GITHUB_USER/$REPO_NAME.git" "$DIR/$REPO_NAME"
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

# Create Compose file for docker-in-docker
COMPOSE_FILE="$DOCKER_DIR/$SERVICE_NAME.yml"
echo "📝 Creating $SERVICE_NAME.yml for docker-in-docker..."
cat <<EOF > "$COMPOSE_FILE"
version: '3.3'
services:
  $SERVICE_NAME:
    container_name: $SERVICE_NAME
    image: $DOCKER_IMAGE
    privileged: true
    restart: unless-stopped
    environment:
      - DOCKER_TLS_CERTDIR=
    volumes:
      - $DIR:/repo
    command: dockerd --debug --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --storage-driver=overlay2 --tls=false
    deploy:
      resources:
        limits:
          memory: 1g
          cpus: "0.5"
EOF

# Validate the Compose file
echo "🔍 Validating $SERVICE_NAME.yml..."
docker-compose -f "$COMPOSE_FILE" config || {
    echo "❌ $SERVICE_NAME.yml is invalid."
    exit 1
}

# Start Docker if not already running
echo "🚀 Starting Docker..."
sudo systemctl start docker
sudo systemctl enable docker

# Run docker-compose
echo "📦 Running Docker Compose for $SERVICE_NAME..."
sudo docker-compose -f "$COMPOSE_FILE" up -d || {
    echo "❌ Failed to start Docker Compose."
    exit 1
}

# Confirm container is running
echo "🔍 Checking if container '$SERVICE_NAME' is running..."
if sudo docker ps | grep -q "$SERVICE_NAME"; then
    echo "✅ $SERVICE_NAME is up and running."

    # Wait for Docker daemon to initialize
    echo "⏳ Waiting for Docker daemon to initialize..."
    sleep 20

    # Check if 'dockerd' is running
    echo "🔍 Checking if 'dockerd' is running inside the container..."
    if ! docker exec -it "$SERVICE_NAME" ps aux | grep -q "[d]ockerd"; then
        echo "❌ 'dockerd' is not running inside the container. Checking container logs for errors and warnings..."
        docker logs "$SERVICE_NAME" 2>&1 | grep -E "error|warn|failed|restart" --ignore-case
        exit 1
    fi

    # Test Docker daemon connections
    echo "🔍 Testing Docker daemon connections..."
    if docker exec -it "$SERVICE_NAME" docker -H tcp://127.0.0.1:2375 info; then
        echo "✅ Successfully connected to Docker daemon via TCP."
        DOCKER_HOST="tcp://127.0.0.1:2375"
    elif docker exec -it "$SERVICE_NAME" docker -H unix:///var/run/docker.sock info; then
        echo "✅ Successfully connected to Docker daemon via Unix socket."
        DOCKER_HOST="unix:///var/run/docker.sock"
    else
        echo "❌ Failed to connect to Docker daemon. Check container logs for details."
        docker logs "$SERVICE_NAME"
        exit 1
    fi

    # Run `docker ps` inside the Docker-in-Docker container
    echo "🐳 Running 'docker ps' inside the Docker-in-Docker container..."
    docker exec -it "$SERVICE_NAME" docker -H "$DOCKER_HOST" ps

    # Check if Dockerfile exists in the repository directory
    if [ ! -f "$DIR/$REPO_NAME/Dockerfile" ]; then
        echo "⚠️ Dockerfile not found in $DIR/$REPO_NAME. Creating a default Dockerfile..."
        cat <<EOF > "$DIR/$REPO_NAME/Dockerfile"
# Default Dockerfile
FROM alpine:latest
RUN apk add --no-cache bash
CMD ["bash"]
EOF
        echo "✅ Default Dockerfile created at $DIR/$REPO_NAME/Dockerfile."
    fi

    # Run `docker build` inside the Docker-in-Docker container
    echo "🐳 Running 'docker build .' inside the Docker-in-Docker container..."
    docker exec -it "$SERVICE_NAME" docker -H "$DOCKER_HOST" build -f /repo/firewalla/Dockerfile /repo/firewalla
else
    echo "❌ Container '$SERVICE_NAME' is not running. Skipping nested Docker commands."
    sudo docker-compose -f "$COMPOSE_FILE" down
    exit 1
fi

echo "🎉 Setup complete! '$SERVICE_NAME' is running with nested Docker Compose."
