#!/bin/bash

# Ensure the 'pi' user exists
if ! id -u pi >/dev/null 2>&1; then
    echo "🔧 User 'pi' does not exist. Creating the 'pi' user..."
    sudo useradd -m -s /bin/bash pi
    echo "✅ User 'pi' created successfully."

    # Set a default password for the 'pi' user
    echo "pi:raspberry" | sudo chpasswd
    echo "ℹ️ Default password for 'pi' is set to 'raspberry'. Please change it later for security."
else
    echo "ℹ️ User 'pi' already exists."
fi

# Add 'pi' to the sudo and docker groups
echo "🔧 Adding 'pi' to the 'sudo' and 'docker' groups..."
sudo usermod -aG sudo pi
sudo usermod -aG docker pi
echo "✅ User 'pi' added to the 'sudo' and 'docker' groups."

# Add 'pi' to the sudoers file
if [ ! -f /etc/sudoers.d/pi ]; then
    echo "🔧 Adding 'pi' to the sudoers file..."
    echo "pi ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/pi >/dev/null
    sudo chmod 0440 /etc/sudoers.d/pi
    echo "✅ 'pi' added to the sudoers file with passwordless sudo access."
else
    echo "ℹ️ 'pi' is already in the sudoers file."
fi

# Check if the script is being run as the 'pi' user
if [ "$(whoami)" != "pi" ]; then
    echo "❌ This script must be run as the 'pi' user."
    echo "ℹ️ Please switch to the 'pi' user by running: su - pi"
    exit 1
fi

# Check if the 'pi' user has sudo privileges
if sudo -v >/dev/null 2>&1; then
    echo "✅ The 'pi' user has sudo privileges."
else
    echo "❌ The 'pi' user does not have sudo privileges."
    echo "ℹ️ Please ensure the 'pi' user has sudo access before running this script."
    exit 1
fi

# Define the custom group name
CUSTOM_GROUP="firewalla"

# Create the custom group if it doesn't exist
if ! getent group "$CUSTOM_GROUP" >/dev/null; then
    echo "🔧 Creating custom group '$CUSTOM_GROUP'..."
    sudo groupadd "$CUSTOM_GROUP"  # Added sudo here
    echo "✅ Group '$CUSTOM_GROUP' created."
else
    echo "ℹ️ Group '$CUSTOM_GROUP' already exists."
fi

# Add 'pi' to the custom group
echo "🔧 Adding 'pi' to the '$CUSTOM_GROUP' group..."
sudo usermod -aG "$CUSTOM_GROUP" pi
echo "✅ 'pi' added to the '$CUSTOM_GROUP' group."

# Define working directory
DIR=~/firewalla
DOCKER_DIR="$DIR/docker"
DOCKER_DATA_DIR="$DOCKER_DIR/docker-data"

# Create main directory if it doesn't exist
if [ ! -d "$DIR" ]; then
    echo "📁 Creating main directory $DIR..."
    mkdir -p "$DIR"
else
    echo "📁 Main directory $DIR already exists."
fi

# Create subdirectory for Docker if it doesn't exist
if [ ! -d "$DOCKER_DIR" ]; then
    echo "📁 Creating Docker directory $DOCKER_DIR..."
    mkdir -p "$DOCKER_DIR"
else
    echo "📁 Docker directory $DOCKER_DIR already exists."
fi

# Create subdirectory for Docker data if it doesn't exist
if [ ! -d "$DOCKER_DATA_DIR" ]; then
    echo "📁 Creating Docker data directory $DOCKER_DATA_DIR..."
    mkdir -p "$DOCKER_DATA_DIR"
else
    echo "📁 Docker data directory $DOCKER_DATA_DIR already exists."
fi

# Set group ownership and permissions for the entire directory and subdirectories
echo "🔧 Setting group ownership and permissions for the entire directory and subdirectories..."
sudo chown -R pi:"$CUSTOM_GROUP" "$DIR"
sudo chmod -R 775 "$DIR"
sudo chmod -R g+s "$DIR"  # Set the group sticky bit
echo "✅ Group ownership and permissions set for $DIR and its subdirectories."

# Ensure the pi user owns the ~/firewalla directory
echo "🔧 Ensuring 'pi' user owns the ~/firewalla directory..."
sudo chown -R pi:firewalla ~/firewalla
echo "✅ Ownership set for ~/firewalla."

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

# Function to check Docker socket connectivity
check_docker_socket() {
    echo "🔍 Checking Docker socket connectivity..."
    if sudo docker info >/dev/null 2>&1; then
        echo "✅ Docker socket is accessible."
        return 0
    else
        echo "❌ Docker socket is not accessible."
        return 1
    fi
}

# Function to restart Docker service
restart_docker_service() {
    echo "🔄 Attempting to restart Docker service..."
    if sudo service docker restart >/dev/null 2>&1; then
        echo "✅ Docker service restarted successfully."
        return 0
    else
        echo "❌ Failed to restart Docker service. Please check your Docker installation."
        return 1
    fi
}

# Function to attempt TCP binding fallback
fallback_to_tcp_binding() {
    echo "⚠️ Falling back to TCP binding for Docker..."
    DOCKER_COMMAND="dockerd --debug --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --storage-driver=vfs --tls=false"
    echo "🔄 Starting Docker daemon with TCP binding..."
    if eval "$DOCKER_COMMAND" >/dev/null 2>&1 &; then
        echo "✅ Docker daemon started with TCP binding."
        return 0
    else
        echo "❌ Failed to start Docker daemon with TCP binding."
        return 1
    fi
}

# Main logic to ensure Docker socket connectivity
echo "🔧 Ensuring Docker socket connectivity..."
if ! check_docker_socket; then
    echo "⚠️ Docker socket is not accessible. Attempting fallback methods..."

    # Attempt to restart Docker service
    if ! restart_docker_service; then
        echo "⚠️ Docker service restart failed. Attempting TCP binding fallback..."

        # Attempt TCP binding fallback
        if ! fallback_to_tcp_binding; then
            echo "❌ All fallback methods failed. Unable to connect to Docker socket."
            exit 1
        fi
    fi

    # Recheck Docker socket after fallback
    if ! check_docker_socket; then
        echo "❌ Docker socket is still not accessible after fallback methods."
        exit 1
    fi
fi

echo "✅ Docker socket connectivity ensured."

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

# Check for Docker
echo "Checking if Docker is installed..."
if ! command -v docker &>/dev/null; then
    echo "❌ Docker is not installed. Please install it first."
    exit 1
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
if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "✅ SSH authentication successful."
else
    echo "❌ SSH authentication failed. Ensure the key is added to GitHub."
    exit 1
fi

# Switch repo to SSH remote
echo "🔁 Switching repository remote to SSH..."
cd "$DIR/$REPO_NAME"
git remote set-url origin git@github.com:$GITHUB_USER/$REPO_NAME.git

# Determine if secure binding is possible
TLS_CERT_DIR="/etc/docker/certs.d"
if [ -d "$TLS_CERT_DIR" ] && [ -f "$TLS_CERT_DIR/ca.pem" ] && [ -f "$TLS_CERT_DIR/server-cert.pem" ] && [ -f "$TLS_CERT_DIR/server-key.pem" ]; then
    echo "🔒 Secure binding is possible. Enabling --tlsverify..."
    DOCKER_COMMAND="dockerd --debug --host=tcp://0.0.0.0:2376 --host=unix:///var/run/docker.sock --storage-driver=vfs --tlsverify --tlscacert=$TLS_CERT_DIR/ca.pem --tlscert=$TLS_CERT_DIR/server-cert.pem --tlskey=$TLS_CERT_DIR/server-key.pem"
else
    echo "⚠️ Secure binding is not possible. Falling back to insecure binding..."
    DOCKER_COMMAND="dockerd --debug --host=tcp://0.0.0.0:2375 --host=unix:///var/run/docker.sock --storage-driver=vfs --tls=false"
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
      - $DOCKER_DATA_DIR:/var/lib/docker  # Constrain Docker data to ~/firewalla/docker/docker-data
      - /var/run/docker.sock:/var/run/docker.sock  # Share Docker socket with the host
      - $DOCKER_DIR:/docker  # Bind-mount the Docker directory to /docker inside the container
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
networks:
  dind-network:
    driver: bridge
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

    # Define aliases for Docker-in-Docker
    ALIAS_DOCKER="alias dind='sudo docker exec -it docker-in-docker docker'"
    ALIAS_DOCKER_COMPOSE="alias dind-compose='sudo docker exec -it docker-in-docker docker-compose'"
    ALIAS_DOCKER_SPACE_COMPOSE="alias dindcompose='sudo docker exec -it docker-in-docker docker compose'"

    # Ensure ~/.bashrc exists before making modifications
    if [ ! -f ~/.bashrc ]; then
        echo "❌ ~/.bashrc does not exist. Creating a new one..."
        touch ~/.bashrc
    fi

    # Remove previous conflicting aliases if they exist
    sed -i '/alias dind=/d' ~/.bashrc
    sed -i '/alias dind-compose=/d' ~/.bashrc
    sed -i '/alias dindcompose=/d' ~/.bashrc

    # Add the new aliases if they don't already exist
    if ! grep -Fxq "$ALIAS_DOCKER" ~/.bashrc; then
        echo "$ALIAS_DOCKER" >> ~/.bashrc
        echo "✅ Alias for 'dind' added to ~/.bashrc."
    else
        echo "ℹ️ Alias for 'dind' already exists in ~/.bashrc."
    fi

    if ! grep -Fxq "$ALIAS_DOCKER_COMPOSE" ~/.bashrc; then
        echo "$ALIAS_DOCKER_COMPOSE" >> ~/.bashrc
        echo "✅ Alias for 'dind-compose' added to ~/.bashrc."
    else
        echo "ℹ️ Alias for 'dind-compose' already exists in ~/.bashrc."
    fi

    if ! grep -Fxq "$ALIAS_DOCKER_SPACE_COMPOSE" ~/.bashrc; then
        echo "$ALIAS_DOCKER_SPACE_COMPOSE" >> ~/.bashrc
        echo "✅ Alias for 'dindcompose' added to ~/.bashrc."
    else
        echo "ℹ️ Alias for 'dindcompose' already exists in ~/.bashrc."
    fi

    # Inform the user about sourcing ~/.bashrc
    echo "⚠️ Please run 'source ~/.bashrc' in the current session to apply the aliases, or restart your terminal."
    echo "ℹ️ After sourcing, you can use the following aliases:"
    echo "   - dind: Run Docker commands inside the 'docker-in-docker' container."
    echo "   - dind-compose: Run Docker Compose inside the 'docker-in-docker' container."
    echo "   - dindcompose: Run Docker Compose (space-separated syntax) inside the 'docker-in-docker' container."

    # Test nested Docker functionality
    echo "🔍 Testing nested Docker functionality with 'dind'..."
    if sudo docker exec -it docker-in-docker docker run --rm alpine echo "Hello from nested Docker!"; then
        echo "✅ Nested Docker is working correctly with 'dind'."
    else
        echo "❌ Nested Docker test failed. Please check the setup."
    fi

else
    echo "❌ $SERVICE_NAME is not running. Please check the setup."
    exit 1
fi