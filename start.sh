export PGUSER="admin"
export PGPASSWORD="admin"
export PGDATABASE="osm2vdv462"

# Create a network to use the Postgis-Server in another container.
# Networks are used to connect containers and allow them to communicate.
# If it fails (for example because it already exists) ignore the error.
docker network create osm2vdv462_net || true


# Create docker volume which is a storage point located outside of containers.
# This is required to persistently store the database between docker restarts.
docker volume create osm2vdv462_postgis


echo "Starting postgis db docker"
# Start postgis docker if already existing and not running
# Otherwise install and run it
docker start osm2vdv462_postgis || docker run \
  --name "osm2vdv462_postgis" \
  --network "osm2vdv462_net" \
  --publish 5432:5432 \
  --volume "osm2vdv462_postgis:/var/lib/postgresql/data" \
  --env "POSTGRES_DB=$PGDATABASE" \
  --env "POSTGRES_USER=$PGUSER" \
  --env "POSTGRES_PASSWORD=$PGPASSWORD" \
  --env "PG_PRIMARY_PORT=5432" \
  --hostname "osm2vdv462_postgis" \
  --detach \
  postgis/postgis


read -p "Do you want to use pgadmin4? (y/n) " RESP
# Optionally install and run pgadmin for easier database management
if [ "$RESP" = "y" ]; then
  docker start pgadmin4 || docker run \
    --publish 80:80 \
    --name "pgadmin4" \
    --volume "$(pwd)/config/pgadmin_servers.json:/pgadmin4/servers.json" \
    --env "PGADMIN_DEFAULT_EMAIL=admin@mail.com" \
    --env "PGADMIN_DEFAULT_PASSWORD=admin" \
    --network="osm2vdv462_net" \
    --detach \
    dpage/pgadmin4
fi

read -p "Press Enter to exit"

