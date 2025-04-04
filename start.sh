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
echo "🔍 Checking if the required Docker image '$DOCKER_IMAGE' exists..."
if sudo docker images | grep -q "$DOCKER_IMAGE"; then
    echo "✅ Docker image '$DOCKER_IMAGE' already exists. Skipping image removal."
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

# Set default GitHub username
DEFAULT_GITHUB_USER="davviie"

# Check if the username is already set or prompt for it
if [ -z "$GITHUB_USER" ]; then
    read -p "Enter your GitHub username (default: $DEFAULT_GITHUB_USER): " GITHUB_USER
    GITHUB_USER=${GITHUB_USER:-$DEFAULT_GITHUB_USER}
else
    echo "Using GitHub username: $GITHUB_USER"
fi

REPO_NAME="firewalla"

# Define Docker Compose service name
SERVICE_NAME="docker-in-docker"

# Define Docker image
DOCKER_IMAGE="docker:latest"  # Use the latest version dynamically

# Pull the latest Docker image
echo "🔄 Pulling the latest Docker image..."
sudo docker pull $DOCKER_IMAGE

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

# Clone the GitHub repo using SSH
if [ ! -d "$DIR/$REPO_NAME" ]; then
    echo "🌐 Attempting to clone repository from GitHub using SSH..."
    if ! git clone "git@github.com:$GITHUB_USER/$REPO_NAME.git" "$DIR/$REPO_NAME"; then
        echo "❌ SSH cloning failed. Falling back to HTTPS cloning..."
        read -p "Enter your GitHub username: " GITHUB_USER
        git clone "https://github.com/$GITHUB_USER/$REPO_NAME.git" "$DIR/$REPO_NAME" || {
            echo "❌ Failed to clone repository using HTTPS. Please check your credentials and repository access."
            exit 1
        }
    else
        echo "✅ Repository cloned successfully using SSH."
    fi
else
    echo "✔️ Repository already exists."
fi

# Determine the storage driver
STORAGE_DRIVER="overlay2"
if ! lsmod | grep -q overlay || ! df -T /var/lib/docker | grep -q -E "ext4|xfs"; then
    echo "⚠️ 'overlay2' storage driver is not supported. Falling back to 'vfs'..."
    STORAGE_DRIVER="vfs"
else
    echo "✅ 'overlay2' storage driver is supported."
fi

# Create Compose file for docker-in-docker
COMPOSE_FILE="$DOCKER_DIR/$SERVICE_NAME.yml"
echo "📝 Creating $SERVICE_NAME.yml for docker-in-docker..."
cat <<EOF > "$COMPOSE_FILE"
version: '3.8'
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
    command: >
      sh -c "
      if [ -f /etc/alpine-release ]; then
        echo 'Detected Alpine Linux. Using apk for package installation...' &&
        apk add --no-cache curl ca-certificates docker-cli docker-compose;
      elif [ -f /etc/os-release ] && grep -qi 'ubuntu\|debian' /etc/os-release; then
        echo 'Detected Ubuntu/Debian. Using apt-get for package installation...' &&
        apt-get update &&
        apt-get install -y apt-transport-https ca-certificates curl gnupg &&
        mkdir -p /etc/apt/keyrings &&
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc &&
        chmod a+r /etc/apt/keyrings/docker.asc &&
        echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu stable' > /etc/apt/sources.list.d/docker.list &&
        apt-get update &&
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin;
      else
        echo 'Unsupported OS. Exiting...' &&
        exit 1;
      fi &&
      dockerd --debug --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --storage-driver=$STORAGE_DRIVER --tls=false
      "
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 1g
          cpus: "0.5"
      restart_policy:
        condition: on-failure
    networks:
      - default
networks:
  default:
    driver: overlay
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

    echo "🎉 Setup complete! '$SERVICE_NAME' is running with nested Docker Compose."

    # Add alias for nested Docker
    echo "🔗 Adding alias for nested Docker..."
    ALIAS_COMMAND="alias docker='sudo docker exec -it $SERVICE_NAME docker'"

    # Remove invalid references to non-existent files in ~/.bashrc
    if grep -q "/home/pi/firewalla/scripts/alias.sh" ~/.bashrc; then
        echo "⚠️ Removing invalid reference to /home/pi/firewalla/scripts/alias.sh from ~/.bashrc..."
        sed -i '/\/home\/pi\/firewalla\/scripts\/alias.sh/d' ~/.bashrc
    fi

    # Add the alias if it doesn't already exist
    if ! grep -Fxq "$ALIAS_COMMAND" ~/.bashrc; then
        echo "$ALIAS_COMMAND" >> ~/.bashrc
        echo "✅ Alias added to ~/.bashrc. Run 'source ~/.bashrc' to apply it in the current session."
    else
        echo "ℹ️ Alias already exists in ~/.bashrc."
    fi

    # Test nested Docker functionality
    echo "🔍 Testing nested Docker functionality..."
    if sudo docker exec -it "$SERVICE_NAME" docker run --rm alpine echo "Hello from nested Docker!"; then
        echo "✅ Nested Docker is working correctly."
    else
        echo "❌ Nested Docker test failed. Please check the setup."
    fi
else
    echo "❌ Container '$SERVICE_NAME' is not running. Skipping nested Docker commands."
    sudo docker-compose -f "$COMPOSE_FILE" down
    exit 1
fi

echo "🎉 Setup complete! '$SERVICE_NAME' is running with nested Docker Compose."
