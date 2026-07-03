#!sh

# sanity checks and defaults

if [ "$UID" = "0" ]; then
    SUDO=""
elif docker info > /dev/null 2>&1; then
    SUDO=""
else
    SUDO=$(which sudo 2>/dev/null)
    if [ ! -x "$SUDO" ] || ! $SUDO docker info > /dev/null 2>&1; then
	echo "Cannot access the Docker daemon. Start Docker Desktop or run with sufficient privileges."
	exit 1
    fi
fi

if docker compose version > /dev/null 2>&1; then
    DOCKER_COMPOSE="docker compose"
elif DOCKER_COMPOSE=$(which docker-compose 2>/dev/null) && [ -x "$DOCKER_COMPOSE" ]; then
    :
else
    echo "\`docker compose\` not installed, cannot proceed"
    exit 2
fi



DOCKER_IMAGE_TO_RUN=$1

# if not an image specified, use the default
if [ -z "$DOCKER_IMAGE_TO_RUN" ]; then
    DOCKER_IMAGE_TO_RUN=standalone
    echo "Using default image <$DOCKER_IMAGE_TO_RUN>"
fi

if [ ! -d $DOCKER_IMAGE_TO_RUN ]; then
    echo "Cannot find docker image directory <$DOCKER_IMAGE_TO_RUN>"
    exit 1
fi


cd $DOCKER_IMAGE_TO_RUN

# check there are the files to run the image
if [ ! -f "docker-compose.yml" ]; then
    echo "Cannot find file 'docker-compose.yml'"
    exit 3
fi

if [ ! -f "Dockerfile" ]; then
    echo "Dockerfile is missing"
    exit 4
fi

DOCKER_IMAGE_NAME=$($SUDO $DOCKER_COMPOSE config --images 2>/dev/null | head -n 1)
IMAGE_EXISTS=$($SUDO docker images -q "$DOCKER_IMAGE_NAME" 2>/dev/null)

if [ -n "$FORCE_REBUILD" ]; then
	echo "FORCE_REBUILD is set. Rebuilding image $DOCKER_IMAGE_NAME..."
    $SUDO $DOCKER_COMPOSE build --force-rm --no-cache
elif [ -z "$IMAGE_EXISTS" ]; then
    echo "Building the Docker image $DOCKER_IMAGE_NAME..."
    $SUDO $DOCKER_COMPOSE build --force-rm --no-cache
else
    echo "Docker image $DOCKER_IMAGE_NAME already exists. Skipping build."
fi

$SUDO $DOCKER_COMPOSE up -d --remove-orphans

if [ $? -ne 0 ]; then
    echo "Cannot start the PostgreSQL container"
    exit 10
fi

DOCKER_ID=$($SUDO $DOCKER_COMPOSE ps -q learn_postgresql)
if [ -z "$DOCKER_ID" ]; then
    echo "Cannot find running PostgreSQL container"
    exit 10
fi
DOCKER_CONTAINER_NAME=$($SUDO docker inspect --format '{{.Name}}' "$DOCKER_ID" | sed 's|^/||')


SECS=5
echo "Waiting $SECS secs for the container <$DOCKER_CONTAINER_NAME> -> <$DOCKER_ID> to complete starting up..."
sleep $SECS

if [ "$DOCKER_IMAGE_TO_RUN" = "chapter_09" ]; then
	echo "chown on tablespaces directories"
	$SUDO docker exec "$DOCKER_ID" chown -R postgres:postgres /data
fi

$SUDO docker exec --user postgres --workdir /var/lib/postgresql -it  $DOCKER_ID /bin/bash

if [ $? -ne 0 ]; then
    echo "Getting the logs to understand what went wrong"
    $SUDO docker logs $DOCKER_CONTAINER_NAME
fi

echo "Stopping the container $DOCKER_CONTAINER_NAME"
$SUDO docker stop $DOCKER_CONTAINER_NAME
