systemctl start docker
systemctl enable docker
sudo usermod -aG docker pi
## how to refresh here without logout??##

#enter the docker-in-docker container 
docker exec -it docker-in-docker sh
##install compose inside the dind container
apk add --no-cache docker-compose


