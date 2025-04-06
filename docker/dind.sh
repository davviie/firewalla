#!/bin/bash

# Ensure the script is being run by the 'pi' user
if [ "$(whoami)" != "pi" ]; then
    echo "❌ This script must be run as the 'pi' user. Please switch to the 'pi' user and try again."
    exit 1
fi

# Ensure the 'pi' user is part of the 'docker' group
if ! groups pi | grep -q "\bdocker\b"; then
    echo "🔧 Adding 'pi' to the 'docker' group..."
    sudo usermod -aG docker pi
    echo "✅ User 'pi' added to the 'docker' group. Please log out and log back in for the changes to take effect."
    exit 1
fi

# Define default values for environment variables
DEFAULT_NEXTDNS_CONFIG="dfa3a4"
DEFAULT_PIHOLE_TZ="America/Toronto"
DEFAULT_PIHOLE_WEBPASSWORD="p0tat0"
DEFAULT_PORTAINER_PORT="9000"

# Prompt the user for environment variable values (or use defaults)
echo "🔧 Configuring environment variables for firewalla_dind.yml..."
read -p "Enter NextDNS Config ID (default: $DEFAULT_NEXTDNS_CONFIG): " NEXTDNS_CONFIG
NEXTDNS_CONFIG="${NEXTDNS_CONFIG:-$DEFAULT_NEXTDNS_CONFIG}"

read -p "Enter Pi-hole Timezone (default: $DEFAULT_PIHOLE_TZ): " PIHOLE_TZ
PIHOLE_TZ="${PIHOLE_TZ:-$DEFAULT_PIHOLE_TZ}"

read -p "Enter Pi-hole Admin Password (default: $DEFAULT_PIHOLE_WEBPASSWORD): " PIHOLE_WEBPASSWORD
PIHOLE_WEBPASSWORD="${PIHOLE_WEBPASSWORD:-$DEFAULT_PIHOLE_WEBPASSWORD}"

read -p "Enter Portainer Port (default: $DEFAULT_PORTAINER_PORT): " PORTAINER_PORT
PORTAINER_PORT="${PORTAINER_PORT:-$DEFAULT_PORTAINER_PORT}"

# Check if the current directory is writable
if [ ! -w ./ ]; then
    echo "❌ Current directory is not writable. Please check permissions."
    exit 1
fi

# Create or overwrite the .env file with the environment variables
ENV_FILE=./.env
{
    echo "NEXTDNS_CONFIG=\"$NEXTDNS_CONFIG\""
    echo "PIHOLE_TZ=\"$PIHOLE_TZ\""
    echo "PIHOLE_WEBPASSWORD=\"$PIHOLE_WEBPASSWORD\""
    echo "PORTAINER_PORT=\"$PORTAINER_PORT\""
} > "$ENV_FILE" || {
    echo "❌ Failed to create .env file. Check permissions."
    exit 1
}
echo "✅ Environment variables written to $ENV_FILE"

# Ensure the docker-in-docker container is running with the correct bind mount
DIND_CONTAINER="docker-in-docker"
if ! sudo docker ps --filter "name=$DIND_CONTAINER" --format "{{.Names}}" | grep -q "^$DIND_CONTAINER$"; then
    echo "🔧 Starting the docker-in-docker container with the current directory mounted..."
    sudo docker run -d --rm \
        --name "$DIND_CONTAINER" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$(pwd):$(pwd)" \  # Bind-mount the current directory
        -w "$(pwd)" \          # Set the working directory inside the container
        --group-add $(getent group docker | cut -d: -f3) \
        docker:dind || {
        echo "❌ Failed to start the docker-in-docker container."
        exit 1
    }
    echo "✅ docker-in-docker container started successfully."
else
    echo "✅ docker-in-docker container is already running."
fi

# Authenticate with GitHub Container Registry
echo "🔑 Authenticating with GitHub Container Registry (ghcr.io)..."
if ! docker login ghcr.io >/dev/null 2>&1; then
    echo "🔐 Authentication required for ghcr.io."
    read -p "Enter your GitHub username: " GITHUB_USER
    read -s -p "Enter your GitHub Personal Access Token (PAT): " GITHUB_PAT
    echo
    echo "$GITHUB_PAT" | docker login ghcr.io -u "$GITHUB_USER" --password-stdin || {
        echo "❌ Failed to authenticate with GitHub Container Registry."
        exit 1
    }
    echo "✅ Successfully authenticated with ghcr.io."
else
    echo "✅ Already authenticated with ghcr.io."
fi

# Authenticate with Docker Hub
echo "🔑 Authenticating with Docker Hub..."
if ! docker login >/dev/null 2>&1; then
    echo "🔐 Authentication required for Docker Hub."
    # Flush input buffer to avoid issues
    read -t 1 -n 10000 discard_input 2>/dev/null || true
    read -p "Enter your Docker Hub username: " DOCKER_USER
    read -s -p "Enter your Docker Hub password: " DOCKER_PASS
    echo  # Add a newline after the password input
    echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin || {
        echo "❌ Failed to authenticate with Docker Hub."
        exit 1
    }
    echo "✅ Successfully authenticated with Docker Hub."
else
    echo "✅ Already authenticated with Docker Hub."
fi

# Authenticate with GitHub CLI
echo "🔑 Authenticating with GitHub CLI..."
if ! gh auth status >/dev/null 2>&1; then
    echo "🔐 Authentication required for GitHub CLI."
    gh auth login || {
        echo "❌ Failed to authenticate with GitHub CLI."
        exit 1
    }
    echo "✅ Successfully authenticated with GitHub CLI."
else
    echo "✅ Already authenticated with GitHub CLI."
fi

# Navigate to the directory containing the Docker Compose file
DOCKER_DIR=$(pwd)
cd "$DOCKER_DIR" || {
    echo "❌ Failed to navigate to $DOCKER_DIR. Please check if the directory exists."
    exit 1
}

# Debugging: Print the current working directory
echo "Current directory: $(pwd)"

# Ensure the Docker Compose file exists
if [ ! -f "./firewalla_dind.yml" ]; then
    echo "❌ firewalla_dind.yml not found in $(pwd)."
    exit 1
fi

# Validate the Docker Compose file
echo "🔍 Validating firewalla_dind.yml..."
sudo docker exec -it "$DIND_CONTAINER" docker compose -f firewalla_dind.yml config || {
    echo "❌ firewalla_dind.yml is invalid."
    exit 1
}

# Start the services using Docker Compose
echo "📦 Launching services defined in firewalla_dind.yml..."
sudo docker exec -it "$DIND_CONTAINER" docker compose -f firewalla_dind.yml up -d || {
    echo "❌ Failed to start services in firewalla_dind.yml."
    exit 1
}

export BROWSER=xdg-open

echo "🎉 Services are up and running!"
