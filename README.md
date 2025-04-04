# firewalla

# Firewalla Docker-in-Docker Setup

# This repository contains an automated setup script for configuring Docker-in-Docker on Firewalla. The script handles the following:
# - Setting up Docker-in-Docker with dynamic storage driver selection (`overlay2` or `vfs`).
# - Configuring secure or insecure Docker daemon binding based on available certificates.
# - Building a default Dockerfile inside the Docker-in-Docker container.
# - Saving error logs for debugging.

# ---

## Prerequisites
# Ensure your Firewalla device has Docker and Git installed before proceeding.

# ---

## Setup Instructions
# Clone this repository to your Firewalla:
sudo git clone https://github.com/davviie/firewalla.git ~/firewalla

# Navigate to the repository directory:
cd ~/firewalla

# Make the setup script executable:
sudo chmod +x start.sh

# Run the setup script:
sudo ./start.sh

# # ---

## Features
# - **Dynamic Storage Driver Selection**:
#   Automatically uses `overlay2` if supported; falls back to `vfs` otherwise.
# - **Secure/Insecure Binding**:
#   Enables `--tlsverify` if certificates are available; otherwise, falls back to insecure binding.
# - **Error Log Saving**:
#   Saves error logs from the `docker-in-docker` container to `docker-in-docker-error.log` in the repository directory.

# # ---

## Troubleshooting
# If you encounter permission issues, ensure the repository directory is writable:
sudo chmod -R 777 ~/firewalla

# To check the logs of the `docker-in-docker` container:
sudo docker logs docker-in-docker

# To check only error logs of the `docker-in-docker` container:
sudo docker logs docker-in-docker 2>&1 | grep -i "error"

# To re-run the setup script after cleaning up:
cd ~/firewalla
sudo ./start.sh

# ---

## Example Commands
# Run a test container inside the Docker-in-Docker container:
sudo docker exec -it docker-in-docker docker run --rm alpine echo "Hello from nested Docker!"

# Check error logs:
sudo cat ~/firewalla/docker-in-docker-error.log

# ---

## License
# This repository is licensed under the MIT License. Feel free to modify and use it as needed.