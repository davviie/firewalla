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

# Ensure the 'docker' group exists
if ! getent group docker >/dev/null; then
    echo "🔧 Creating 'docker' group..."
    sudo groupadd docker
fi

# Add 'pi' to the 'sudo' and 'docker' groups
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
    sudo groupadd "$CUSTOM_GROUP"
    echo "✅ Group '$CUSTOM_GROUP' created."
else
    echo "ℹ️ Group '$CUSTOM_GROUP' already exists."
fi

# Add 'pi' to the custom group
echo "🔧 Adding 'pi' to the '$CUSTOM_GROUP' group..."
sudo usermod -aG "$CUSTOM_GROUP" pi

# Create working directory
DIR=~/firewalla
DOCKER_DIR="$DIR/docker"
mkdir -p "$DOCKER_DIR"
if [ "$(stat -c '%U:%G' "$DIR")" != "pi:$CUSTOM_GROUP" ]; then
    sudo chown -R pi:"$CUSTOM_GROUP" "$DIR"
fi
sudo chmod -R 775 "$DIR"
sudo chmod -R g+s "$DIR"

# Purge Docker
echo "🧹 Cleaning Docker..."
sudo docker ps -aq | xargs -r sudo docker stop
sudo docker ps -aq | xargs -r sudo docker rm
sudo docker images -q | xargs -r sudo docker rmi -f
sudo docker volume ls -q | xargs -r sudo docker volume rm
sudo docker network ls -q | xargs -r sudo docker network rm
sudo systemctl restart docker

# Ensure Docker Compose is installed
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "🔧 Installing Docker Compose..."
    sudo apt-get update
    sudo apt-get install -y docker-compose
fi

# Docker-in-Docker setup
SERVICE_NAME="docker-in-docker"
DOCKER_IMAGE="docker:dind"
COMPOSE_FILE="$DOCKER_DIR/docker-compose.yml"

# Generate Docker Compose file for DIND
cat <<EOF > "$COMPOSE_FILE"
version: '3.7'
services:
  $SERVICE_NAME:
    image: $DOCKER_IMAGE
    container_name: $SERVICE_NAME
    privileged: true
    environment:
      - DOCKER_TLS_CERTDIR=
      - DOCKER_HOST=tcp://0.0.0.0:2375
    command: ["dockerd", "--host=tcp://0.0.0.0:2375", "--host=unix:///var/run/docker.sock", "--debug"]
    volumes:
      - docker-data:/var/lib/docker
      - /var/run/docker.sock:/var/run/docker.sock
      - $DOCKER_DIR:/docker  # Bind-mount the Docker directory to /docker inside the container
    ports:
      - "2375:2375"
    networks:
      - dind-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "docker", "info"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  docker-data:
    driver: local
    driver_opts:
      type: bind
      o: bind
      device: ./docker/docker-data

networks:
  dind-network:
    driver: bridge
EOF

echo "✅ Docker Compose file created at $COMPOSE_FILE"

# Pull image and run
echo "🔧 Pulling Docker images..."
if ! sudo docker-compose -f "$COMPOSE_FILE" pull; then
    echo "❌ Failed to pull Docker images."
    exit 1
fi

echo "🔧 Starting Docker Compose services..."
if ! sudo docker-compose -f "$COMPOSE_FILE" up -d; then
    echo "❌ Failed to start Docker Compose services."
    exit 1
fi

echo "🚀 Docker-in-Docker is up and running on port 2375."
echo "💡 You can now connect to it via: tcp://localhost:2375"
