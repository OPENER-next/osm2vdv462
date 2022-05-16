# export required for osm2pgsql
# see https://osm2pgsql.org/doc/manual.html#environment-variables
export PGUSER="admin"
export PGPASSWORD="admin"
export PGDATABASE="osm2vdv462"
export PGPORT="5432"

PG_ADMIN_EMAIL="admin@mail.com"
PG_ADMIN_PASSWORD="admin"

DOCKER_NETWORK="osm2vdv462_net"


# Create a network to use the Postgis-Server in another container.
# Networks are used to connect containers and allow them to communicate.
# If it fails (for example because it already exists) ignore the error.
docker network create $DOCKER_NETWORK || true


# Create docker volume which is a storage point located outside of containers.
# This is required to persistently store the database between docker restarts.
docker volume create osm2vdv462_postgis


echo "Starting postgis db docker"
# Start postgis docker if already existing and not running
# Otherwise install and run it
docker start osm2vdv462_postgis || docker run \
  --name "osm2vdv462_postgis" \
  --network $DOCKER_NETWORK \
  --publish "$PGPORT:5432" \
  --volume "osm2vdv462_postgis:/var/lib/postgresql/data" \
  --env "POSTGRES_DB=$PGDATABASE" \
  --env "POSTGRES_USER=$PGUSER" \
  --env "POSTGRES_PASSWORD=$PGPASSWORD" \
  --env "PG_PRIMARY_PORT=$PGPORT" \
  --hostname "osm2vdv462_postgis" \
  --detach \
  postgis/postgis


read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4
# Optionally install and run pgadmin for easier database management
if [ $USE_PGADMIN4 = "y" ] || [ $USE_PGADMIN4 = "Y" ]; then
  docker start pgadmin4 || docker run \
    --publish 80:80 \
    --name "pgadmin4" \
    --volume "$(pwd)/config/pgadmin_servers.json:/pgadmin4/servers.json" \
    --env "PGADMIN_DEFAULT_EMAIL=$PG_ADMIN_EMAIL" \
    --env "PGADMIN_DEFAULT_PASSWORD=$PG_ADMIN_PASSWORD" \
    --network=$DOCKER_NETWORK \
    --detach \
    dpage/pgadmin4
fi


# Import osm data file
read -p "The OSM file that should be imported (will be skipped if file cannot be found) " IMPORT_FILE
if [ -f "$IMPORT_FILE" ]; then
  osm2pgsql \
    --host "localhost" \
    --slim \
    --drop \
    --cache 2048 \
    --output flex \
    --style "$(pwd)/scripts/osm2pgsql/main.lua" \
    $IMPORT_FILE
fi


read -p "Press Enter to exit"
