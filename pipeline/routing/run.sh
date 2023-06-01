# Optionally run the PPR preprocessing
read -p "Do you want to (re)run the routing preprocessing? (y/n) " RUN_PREPROCESSING
  #if [ "$RUN_PREPROCESSING" = "y" ] || [ "$RUN_PREPROCESSING" = "Y" ]; then
    #docker pull ghcr.io/motis-project/ppr:edge
    #docker run -u root --rm -it -v data:/data -v $IMPORT_FILE:/data/$(basename "$IMPORT_FILE") ghcr.io/motis-project/ppr:edge /ppr/ppr-preprocess --osm /data/$(basename "$IMPORT_FILE") --graph /data/germany.ppr

    # alternatively, if [elevation data](https://github.com/motis-project/ppr/wiki/Elevation-Data-(DEM)) is used:
    # docker run -u root --rm -it -v data:/data -v $IMPORT_FILE:/data/$(basename "$IMPORT_FILE") ghcr.io/motis-project/ppr:edge -v /path/to/srtm:/srtm /ppr/ppr-preprocess --osm /data/$(basename "$IMPORT_FILE") --graph /data/germany.ppr --dem /srtm
  #fi

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

# perform healthcheck on the PPR container to wait until the routing graph is loaded
# it is not possible to do this in docker compose, because the container would need a tool like curl or wget to perform the healthcheck
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

# Execute ppr script in the python docker
echo "Getting paths from PPR: "
docker exec osm2vdv462_python python3 ppr.py