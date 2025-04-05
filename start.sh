#!/bin/bash

# Define the custom group name
CUSTOM_GROUP="firewalla"

# Create the custom group if it doesn't exist
if ! getent group "$CUSTOM_GROUP" >/dev/null; then
    echo "🔧 Creating custom group '$CUSTOM_GROUP'..."
    groupadd "$CUSTOM_GROUP"
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


# Remove previous conflicting aliases if they exist
sed -i '/alias docker=/d' ~/.bashrc
sed -i '/alias docker-compose=/d' ~/.bashrc
sed -i '/alias docker compose=/d' ~/.bashrc

# Add the docker alias if it doesn't already exist
echo "$ALIAS_COMMAND" >> ~/.bashrc
echo "$ALIAS_COMMAND_COMPOSE" >> ~/.bashrc
echo "$ALIAS_COMMAND_COMPOSE2" >> ~/.bashrc
echo "✅ Alias for 'docker', docker compose and 'docker-compose' added to ~/.bashrc."
echo "⚠️ Please run 'source ~/.bashrc' in the current session or restart the terminal for changes to take effect."

# Add alias for nested Docker
echo "🔗 Adding alias for nested Docker..."
ALIAS_COMMAND="alias docker='sudo docker exec -it $SERVICE_NAME docker'"
ALIAS_COMMAND_COMPOSE="alias docker-compose='sudo docker exec -it $SERVICE_NAME docker-compose'"
ALIAS_COMMAND_COMPOSE2="alias docker compose='sudo docker exec -it $SERVICE_NAME docker compose'"

# Ensure ~/.bashrc exists before making modifications
if [ ! -f ~/.bashrc ]; then
    echo "❌ ~/.bashrc does not exist. Creating a new one..."
    touch ~/.bashrc
fi

# Remove invalid references to non-existent files in ~/.bashrc
if grep -q "/home/pi/firewalla/scripts/alias.sh" ~/.bashrc; then
    echo "⚠️ Removing invalid reference to /home/pi/firewalla/scripts/alias.sh from ~/.bashrc..."
    sed -i '/\/home\/pi\/firewalla\/scripts\/alias.sh/d' ~/.bashrc
fi

# Remove previous conflicting aliases if they exist
sed -i '/alias docker=/d' ~/.bashrc
sed -i '/alias docker-compose=/d' ~/.bashrc
sed -i '/alias docker compose=/d' ~/.bashrc

# Add the docker alias if it doesn't already exist
if ! grep -Fxq "$ALIAS_COMMAND" ~/.bashrc; then
    echo "$ALIAS_COMMAND" >> ~/.bashrc
    echo "✅ Alias for 'docker' added to ~/.bashrc."
else
    echo "ℹ️ Alias for 'docker' already exists in ~/.bashrc."
fi

# Add the docker-compose alias if it doesn't already exist
if ! grep -Fxq "$ALIAS_COMMAND_COMPOSE" ~/.bashrc; then
    echo "$ALIAS_COMMAND_COMPOSE" >> ~/.bashrc
    echo "✅ Alias for 'docker-compose' added to ~/.bashrc."
else
    echo "ℹ️ Alias for 'docker-compose' already exists in ~/.bashrc."
fi

# Add the docker compose alias if it doesn't already exist
if ! grep -Fxq "$ALIAS_COMMAND_COMPOSE2" ~/.bashrc; then
    echo "$ALIAS_COMMAND_COMPOSE2" >> ~/.bashrc
    echo "✅ Alias for 'docker compose' added to ~/.bashrc."
else
    echo "ℹ️ Alias for 'docker compose' already exists in ~/.bashrc."
fi

# Inform the user about sourcing ~/.bashrc
echo "⚠️ Please run 'source ~/.bashrc' in the current session or restart the terminal for changes to take effect."

# Test nested Docker functionality
echo "🔍 Testing nested Docker functionality..."
if sudo docker exec -it "$SERVICE_NAME" docker run --rm alpine echo "Hello from nested Docker!"; then
    echo "✅ Nested Docker is working correctly."
else
    echo "❌ Nested Docker test failed. Please check the setup."
fi


else
    echo "❌ $SERVICE_NAME is not running. Please check the setup."
    exit 1
fi