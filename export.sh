export PGUSER="admin"
export PGDATABASE="osm2vdv462"

export DOCKER_NETWORK="osm2vdv462_net"

EXPORT_FILE="export.xml"

export IMPORT_FILE_PATH=""
export IMPORT_FILE=""

# Optionally import a new OSM file to be used for PPR and OSM2PGSQL
read -p "Do you want to import an OSM file? (y/n) " RUN_IMPORT
# Import osm data file
if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
  read -p "Enter the OSM file(s) that should be imported: " IMPORT_FILE_PATH
  if ! [ -f $IMPORT_FILE_PATH ]; then
    echo "File does not exist. Quitting ..."
    exit 1
  fi

  export IMPORT_FILE_PATH
  export IMPORT_FILE=$(basename "$IMPORT_FILE_PATH")

  read -p "Do you want to (re)run the routing preprocessing? (y/n) " RUN_PREPROCESSING
  #if [ "$RUN_PREPROCESSING" = "y" ] || [ "$RUN_PREPROCESSING" = "Y" ]; then
    #docker pull ghcr.io/motis-project/ppr:edge
    #docker run -u root --rm -it -v data:/data -v $IMPORT_FILE:/data/$(basename "$IMPORT_FILE") ghcr.io/motis-project/ppr:edge /ppr/ppr-preprocess --osm /data/$(basename "$IMPORT_FILE") --graph /data/germany.ppr

    # alternatively, if [elevation data](https://github.com/motis-project/ppr/wiki/Elevation-Data-(DEM)) is used:
    # docker run -u root --rm -it -v data:/data -v $IMPORT_FILE:/data/$(basename "$IMPORT_FILE") ghcr.io/motis-project/ppr:edge -v /path/to/srtm:/srtm /ppr/ppr-preprocess --osm /data/$(basename "$IMPORT_FILE") --graph /data/germany.ppr --dem /srtm
  #fi
fi

# Optionally install and run pgadmin for easier database management
read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4

# Start Docker Compose project:
echo "Starting Docker Compose project ..."

if [ "$RUN_PREPROCESSING" = "y" ] || [ "$RUN_PREPROCESSING" = "Y" ]; then
  docker-compose up osm2vdv462_ppr_preprocess

  exit_status=$(docker inspect osm2vdv462_ppr_preprocess --format='{{.State.ExitCode}}')

  # always remove the preprocessing container, even if it exited succesfully
  docker-compose rm osm2vdv462_ppr_preprocess -f

  if [ ! $exit_status -eq 0 ]; then
    echo "Error: Preprocess exited with status $exit_status. Quitting ..."
    exit 1
  fi

  # restart the PPR backend container to reload the new routing graph file
  docker-compose restart osm2vdv462_ppr_backend
fi

if [ $USE_PGADMIN4 ]; then
  docker-compose --profile pgadmin4 up -d
else
  docker-compose up -d
fi

# Check the exit status of the docker compose command
if [ $? -eq 0 ]; then
  echo "Docker Compose stack started successfully"
else
  echo "Error while starting Docker Compose stack. Quitting ..."
  exit 1
fi

echo "Waiting for PPR to load the routing graph ..."
MAX_RETRIES=20
RETRY_DELAY=10

# loop until the maximum number of retries is reached
for i in $(seq 1 $MAX_RETRIES); do
    # check the health of the container using curl command
    HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9042)

    # check the status code returned by curl
    if [ "$HEALTH" -eq "200" ]; then
        # exit the loop if the container is healthy
        echo "PPR container is healthy"
        break
    else
        # wait for the retry delay before checking again
        sleep $RETRY_DELAY
        printf "."
    fi
done

# exit with error if the container is still not healthy
if [ "$HEALTH" -ne "200" ]; then
    echo "Container is not healthy after $MAX_RETRIES retries"
    exit 1
fi
echo "Docker Compose project started."

# Run setup scripts
pipeline/setup/setup.sh

# Run organisations import script
pipeline/organisations/organisations.sh

if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
  # Run osm2pgsql import scripts
  docker-compose --profile osm2pgsql up -d
  docker-compose exec osm2vdv462_osm2pgsql osm2pgsql \
    --slim \
    --drop \
    --cache 2048 \
    --output flex \
    --style "/scripts/osm2pgsql/main.lua" \
    /input/$IMPORT_FILE
fi


read -p "Do you want to run the export? (y/n) " RUN_EXPORT
# Export to VDV462 xml file
if [ "$RUN_EXPORT" = "y" ] || [ "$RUN_EXPORT" = "Y" ]; then
  echo "Exporting..."
  # Run export sql script via psql
  cat \
    ./pipeline/export/stop_places.sql \
  | docker exec -i osm2vdv462_postgis \
    psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction

  # Start python ppr docker
  echo "Getting paths from PPR: "
  docker exec osm2vdv462_python python3 ppr.py

  cat \
    ./pipeline/export/organisations.sql \
    ./pipeline/export/export.sql \
  | docker exec -i osm2vdv462_postgis \
    psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction \
  > $EXPORT_FILE

  echo "Done. Export has been saved to $(pwd)/$EXPORT_FILE"
fi


read -p "Press Enter to exit"
