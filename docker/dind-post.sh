#!/bin/sh
#set timeout to 300 (5 minutes)
export TMOUT=300

# Ensure the script is running inside the docker-in-docker container
if ! docker info >/dev/null 2>&1; then
    echo "❌ This script must be run inside the docker-in-docker container."
    echo "ℹ️ To enter the container shell, run:"
    echo "   docker exec -it docker-in-docker sh"
    exit 1
fi

# Retry logic for apk commands
retry_apk() {
    local retries=5
    local count=0
    until apk "$@" || [ $count -ge $retries ]; do
        count=$((count + 1))
        echo "⚠️ apk command failed. Retrying ($count/$retries)..."
        sleep 2
    done

    if [ $count -ge $retries ]; then
        echo "❌ apk command failed after $retries attempts."
        exit 1
    fi
}

# Update Alpine packages
echo "🔄 Updating Alpine packages..."
retry_apk update && retry_apk upgrade

# Install necessary Alpine packages
echo "📦 Installing necessary packages..."
retry_apk add --no-cache \
    bash \
    curl \
    git \
    openssh \
    docker-cli \
    docker-compose \
    build-base \
    python3 \
    py3-pip \
    jq \
    nano \
    vim

# Upgrade Docker and Docker Compose
echo "⬆️ Upgrading Docker and Docker Compose..."
pip3 install --upgrade pip
pip3 install --upgrade docker-compose

# Verify installations
echo "✅ Verifying installations..."
docker --version || { echo "❌ Docker installation failed."; exit 1; }
docker-compose --version || { echo "❌ Docker Compose installation failed."; exit 1; }
git --version || { echo "❌ Git installation failed."; exit 1; }
python3 --version || { echo "❌ Python3 installation failed."; exit 1; }
pip3 --version || { echo "❌ Pip3 installation failed."; exit 1; }

# Set up SSH for GitHub (optional)
echo "🔐 Setting up SSH for GitHub..."
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "➡️ Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -C "your_email@example.com" -f ~/.ssh/id_rsa -N ""
    echo "✅ SSH key generated. Add the following public key to GitHub:"
    cat ~/.ssh/id_rsa.pub
    echo "➡️ Visit: https://github.com/settings/keys"
else
    echo "ℹ️ SSH key already exists."
fi

# Clean up
echo "🧹 Cleaning up..."
rm -rf /var/cache/apk/*

echo "🎉 Post-install setup complete!"