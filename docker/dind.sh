#!/bin/bash

# Define default values for environment variables
DEFAULT_NEXTDNS_CONFIG="default_config_id"
DEFAULT_PIHOLE_TZ="UTC"
DEFAULT_PIHOLE_WEBPASSWORD="admin"
DEFAULT_PORTAINER_PORT="9000"

# Prompt the user for environment variable values (or use defaults)
echo "🔧 Configuring environment variables for firewall_dind.yml..."
read -p "Enter NextDNS Config ID (default: $DEFAULT_NEXTDNS_CONFIG): " NEXTDNS_CONFIG
NEXTDNS_CONFIG=${NEXTDNS_CONFIG:-$DEFAULT_NEXTDNS_CONFIG}

read -p "Enter Pi-hole Timezone (default: $DEFAULT_PIHOLE_TZ): " PIHOLE_TZ
PIHOLE_TZ=${PIHOLE_TZ:-$DEFAULT_PIHOLE_TZ}

read -p "Enter Pi-hole Admin Password (default: $DEFAULT_PIHOLE_WEBPASSWORD): " PIHOLE_WEBPASSWORD
PIHOLE_WEBPASSWORD=${PIHOLE_WEBPASSWORD:-$DEFAULT_PIHOLE_WEBPASSWORD}

read -p "Enter Portainer Port (default: $DEFAULT_PORTAINER_PORT): " PORTAINER_PORT
PORTAINER_PORT=${PORTAINER_PORT:-$DEFAULT_PORTAINER_PORT}

# Export environment variables for Docker Compose
export NEXTDNS_CONFIG
export PIHOLE_TZ
export PIHOLE_WEBPASSWORD
export PORTAINER_PORT

# Navigate to the directory containing the Compose file
DOCKER_DIR=~/firewalla/docker
cd "$DOCKER_DIR" || {
    echo "❌ Failed to navigate to $DOCKER_DIR. Please check if the directory exists."
    exit 1
}

# Validate the Compose file
echo "🔍 Validating firewall_dind.yml..."
docker-compose -f firewall_dind.yml config || {
    echo "❌ firewall_dind.yml is invalid."
    exit 1
}

# Launch the Compose file
echo "📦 Launching services defined in firewall_dind.yml..."
docker-compose -f firewall_dind.yml up -d || {
    echo "❌ Failed to start services in firewall_dind.yml."
    exit 1
}

echo "🎉 Services are up and running!"