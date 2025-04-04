#!/bin/bash

# Define default values for environment variables
DEFAULT_NEXTDNS_CONFIG="default_config_id"
DEFAULT_PIHOLE_TZ="UTC"
DEFAULT_PIHOLE_WEBPASSWORD="admin"
DEFAULT_PORTAINER_PORT="9000"

# Prompt the user for environment variable values (or use defaults)
echo "🔧 Configuring environment variables for firewalla_dind.yml..."
read -p "Enter NextDNS Config ID (default: $DEFAULT_NEXTDNS_CONFIG): " NEXTDNS_CONFIG
NEXTDNS_CONFIG=${NEXTDNS_CONFIG:-$DEFAULT_NEXTDNS_CONFIG}

read -p "Enter Pi-hole Timezone (default: $DEFAULT_PIHOLE_TZ): " PIHOLE_TZ
PIHOLE_TZ=${PIHOLE_TZ:-$DEFAULT_PIHOLE_TZ}

read -p "Enter Pi-hole Admin Password (default: $DEFAULT_PIHOLE_WEBPASSWORD): " PIHOLE_WEBPASSWORD
PIHOLE_WEBPASSWORD=${PIHOLE_WEBPASSWORD:-$DEFAULT_PIHOLE_WEBPASSWORD}

read -p "Enter Portainer Port (default: $DEFAULT_PORTAINER_PORT): " PORTAINER_PORT
PORTAINER_PORT=${PORTAINER_PORT:-$DEFAULT_PORTAINER_PORT}

# Check if the directory is writable
if [ ! -w ./ ]; then
    echo "❌ Current directory is not writable. Please fix permissions."
    exit 1
fi

# Write environment variables to a .env file
ENV_FILE=./.env
{
    echo "NEXTDNS_CONFIG=$NEXTDNS_CONFIG"
    echo "PIHOLE_TZ=$PIHOLE_TZ"
    echo "PIHOLE_WEBPASSWORD=$PIHOLE_WEBPASSWORD"
    echo "PORTAINER_PORT=$PORTAINER_PORT"
} > $ENV_FILE || {
    echo "❌ Failed to create .env file. Check permissions."
    exit 1
}
echo "✅ Environment variables written to $ENV_FILE"

# Navigate to the directory containing the Compose file
DOCKER_DIR=~/firewalla/docker
cd "$DOCKER_DIR" || {
    echo "❌ Failed to navigate to $DOCKER_DIR. Please check if the directory exists."
    exit 1
}

# Validate the Compose file
echo "🔍 Validating firewalla_dind.yml..."
docker-compose -f firewalla_dind.yml config || {
    echo "❌ firewalla_dind.yml is invalid."
    exit 1
}

# Launch the Compose file
echo "📦 Launching services defined in firewalla_dind.yml..."
docker-compose -f firewalla_dind.yml up -d || {
    echo "❌ Failed to start services in firewalla_dind.yml."
    exit 1
}

echo "🎉 Services are up and running!"