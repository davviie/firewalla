#!/bin/bash

# Ensure the script is being run by the 'pi' user
if [ "$(whoami)" != "pi" ]; then
    echo "❌ This script must be run as the 'pi' user. Please switch to the 'pi' user and try again."
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

# Navigate to the directory containing the Docker Compose file
DOCKER_DIR=~/firewalla/docker
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
dind-compose -f firewalla_dind.yml config || {
    echo "❌ firewalla_dind.yml is invalid."
    exit 1
}

# Start the services using Docker Compose
echo "📦 Launching services defined in firewalla_dind.yml..."
dind-compose -f firewalla_dind.yml up -d || {
    echo "❌ Failed to start services in firewalla_dind.yml."
    exit 1
}

echo "🎉 Services are up and running!"
