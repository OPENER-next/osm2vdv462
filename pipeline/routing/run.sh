# Optionally run the PPR preprocessing
if [ "$RUN_PREPROCESSING" = "y" ] ||
   [ "$RUN_PREPROCESSING" = "Y" ] ||
   [ "$PARAMETER_PREPROCESSING" = "True" ] ||
   [ "$PARAMETER_PREPROCESSING" = "true" ]; then
  if [ "$IMPORT_FILE_PATH" != "" ]; then
    docker-compose up osm2vdv462_ppr_preprocess

    exit_status=$(docker inspect osm2vdv462_ppr_preprocess --format='{{.State.ExitCode}}')

    # always remove the preprocessing container, even if it exited succesfully
    docker-compose rm osm2vdv462_ppr_preprocess -f

    if [ ! $exit_status -eq 0 ]; then
      echo "Error: Preprocess exited with status $exit_status."
      exit 1
    fi

    # restart the PPR backend container to reload the new routing graph file
    # before restarting, check if the container is already running
    if [ "$(docker inspect -f '{{.State.Running}}' osm2vdv462_ppr_backend)" = "running" ]; then
      echo "Restarting PPR backend container ..."
      docker-compose restart osm2vdv462_ppr_backend
    else
      docker-compose up -d osm2vdv462_ppr_backend
    fi
  else
    echo "Error: Cannot run preprocessing without importing an OSM file."
    exit 1
  fi
else
  echo "Skipping preprocessing ..."
  docker-compose up -d osm2vdv462_ppr_backend
fi

echo "Waiting for PPR container to start ..."
sleep 10

# perform healthcheck on the PPR container and wait until the routing graph is loaded
# it is not possible to do this in docker compose, because the container would need a tool like curl or wget to perform the healthcheck

# check the current status of the container
if ! [ "$(docker inspect -f '{{.State.Status}}' osm2vdv462_ppr_backend)" = "running" ]; then
  # wait 10 seconds and check again
  sleep 10
  if ! [ "$(docker inspect -f '{{.State.Status}}' osm2vdv462_ppr_backend)" = "running" ]; then
    echo "Error: PPR container is not running after 10 seconds."
    echo "--> Has the preprocessing been run once?"
    exit 1
  fi
fi

echo "Waiting for PPR to load the routing graph ..."
MAX_RETRIES=20
RETRY_DELAY=10

# loop until the maximum number of retries is reached
for i in $(seq 1 $MAX_RETRIES); do
  # check, if the webserver is running an so if the routing graph is loaded
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