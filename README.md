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
# Copy and paste the following commands into your CLI to set up Docker-in-Docker on Firewalla:

```bash
# Clone the repository
sudo git clone https://github.com/davviie/firewalla.git ~/firewalla

# Navigate to the repository directory
cd ~/firewalla

# Make the setup script executable
sudo chmod +x start.sh

# Run the setup script
sudo ./start.sh

# If you encounter permission issues, ensure the repository directory is writable
sudo chmod -R 777 ~/firewalla

# To check the logs of the `docker-in-docker` container
sudo docker logs docker-in-docker

# To check only error logs of the `docker-in-docker` container
sudo docker logs docker-in-docker 2>&1 | grep -i "error"

# To re-run the setup script after cleaning up
cd ~/firewalla
sudo ./start.sh

# Run a test container inside the Docker-in-Docker container
sudo docker exec -it docker-in-docker docker run --rm alpine echo "Hello from nested Docker!"

# Check error logs
sudo cat ~/firewalla/docker-in-docker-error.log

# Automate cleanup of invalid references in ~/.bashrc
echo "🔧 Cleaning up invalid references in ~/.bashrc..."
sed -i '/\/home\/pi\/firewalla\/scripts\/alias.sh/d' ~/.bashrc
echo "✅ Invalid references removed from ~/.bashrc."

# Reload the shell configuration
source ~/.bashrc
echo "✅ Shell configuration reloaded. You can now use the 'docker' alias for nested Docker."
```

---

## Features
# - **Dynamic Storage Driver Selection**:
#   Automatically uses `overlay2` if supported; falls back to `vfs` otherwise.
# - **Secure/Insecure Binding**:
#   Enables `--tlsverify` if certificates are available; otherwise, falls back to insecure binding.
# - **Error Log Saving**:
#   Saves error logs from the `docker-in-docker` container to `docker-in-docker-error.log` in the repository directory.

# ---

## Troubleshooting
# If you encounter an error like `-bash: /home/pi/firewalla/scripts/alias.sh: No such file or directory`, the above commands will automatically clean up invalid references in `~/.bashrc`.

# ---

## License
# This repository is licensed under the MIT License. Feel free to modify and use it as needed.