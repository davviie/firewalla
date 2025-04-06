# firewalla

# Firewalla Docker-in-Docker Setup

## Prerequisites
- Ensure your Firewalla device has Docker and Git installed.
- Ensure the `pi` user has the necessary permissions to run the scripts.
- The `start.sh` script will automatically create a custom group (`firewalla`) and add the `pi` user to it.

---

## Setup Instructions
Follow these steps to set up Docker-in-Docker on Firewalla:

### 1. Clone the Repository
```bash
git clone https://github.com/davviie/firewalla.git ~/repo
```

### 2. Navigate to the Repository Directory
```bash
cd ~/repo
```

### 3. Make the Setup Script Executable
```bash
chmod +x start.sh
```

### 4. Run the Setup Script as the `pi` User
The `start.sh` script will:
- Create the `firewalla` group (if it doesn’t already exist).
- Add the `pi` user to the `firewalla` group.
- Set up permissions and ownership for the `~/repo` directory.
- Pull the necessary Docker images and set up Docker-in-Docker.

Run the script:
```bash
./start.sh
```

### 5. Navigate to the Docker Directory
```bash
cd ~/repo/docker
```

### 6. Run the `dind.sh` Script as the `pi` User
The `dind.sh` script will:
- Prompt you to configure environment variables.
- Validate the `firewalla_dind.yml` file.
- Launch the services defined in the `firewalla_dind.yml` file.

Run the script:
```bash
./dind.sh
```

### 7. Access the Alpine Shell of Docker-in-Docker
To access the Alpine shell of the `docker-in-docker` container, use the following command:
```bash
docker exec -it docker-in-docker sh
```

Once inside the shell, you can run commands like `apk` to install packages or perform other operations.

---

## Installing Necessary Packages
If you need to install additional packages inside the `docker-in-docker` container, you can use the following commands:

### Update Alpine Packages
```bash
apk update && apk upgrade
```

### Install Commonly Used Packages
```bash
apk add --no-cache \
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
    vim
```

### Upgrade Docker and Docker Compose
If you need to upgrade Docker and Docker Compose, you can use the following commands:
```bash
python3 -m ensurepip --upgrade
pip3 install --upgrade pip
pip3 install --upgrade docker-compose
```

---

## Features
- **Dynamic Storage Driver Selection**:
  Automatically uses `overlay2` if supported; falls back to `vfs` otherwise.
- **Secure/Insecure Binding**:
  Enables `--tlsverify` if certificates are available; otherwise, falls back to insecure binding.
- **Group-Based Permissions**:
  Ensures both `pi` and `root` users have access to the `~/repo` directory and its subdirectories.

---

## Troubleshooting

### Permission Issues
If you encounter permission issues, ensure the `pi` user owns the `~/repo` directory:
```bash
sudo chown -R pi:firewalla ~/repo
sudo chmod -R 775 ~/repo
```

### Missing `firewalla_dind.yml`
If the `firewalla_dind.yml` file is not found, ensure it exists in the `~/repo/docker` directory:
```bash
ls ~/repo/docker/firewalla_dind.yml
```

### Check Logs
To check the logs of the `docker-in-docker` container:
```bash
docker logs docker-in-docker
```

To check only error logs:
```bash
docker logs docker-in-docker 2>&1 | grep -i "error"
```
## Refresh the repo
```bash
sudo rm -rf ~/repo
git clone https://github.com/davviie/firewalla.git ~/repo
```
docker-compose -f ~/repo/docker/docker-in-docker.yaml up -d

### Nested Docker Test
To test if nested Docker is working correctly:
```bash
sudo docker exec -it docker-in-docker docker run --rm alpine echo "Hello from nested Docker!"
```
### Getting the TLS Certificates
```bash
sudo chown -R pi:pi ~/repo/docker/certs
sudo chmod -R 755 ~/repo/docker/certs
mkdir -p ~/repo/docker/certs
openssl req -newkey rsa:4096 -nodes -keyout ~/repo/docker/certs/server-key.pem -x509 -days 365 -out ~/repo/docker/certs/server-cert.pem -subj "/CN=docker-in-docker"
cp ~/repo/docker/certs/server-cert.pem ~/repo/docker/certs/ca.pem
```

### Access the Alpine Shell of Docker-in-Docker
If you need to manually access the Alpine shell of the `docker-in-docker` container, use:
```

```bash
docker exec -it docker-in-docker sh
```

Once inside, you can run commands like `apk` to install additional packages or troubleshoot the container.

### Remove the `apk` Lock File
If you encounter the error `Unable to lock database: temporary error`, it may be caused by a stale lock file. To fix this, remove the lock file manually:
```bash
rm -f /var/lib/apk/lock
```

After removing the lock file, retry the `apk` command:
```bash
apk update && apk upgrade
```

---

## License
This repository is licensed under the MIT License. Feel free to modify and use it as needed.