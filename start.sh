# export required for osm2pgsql
# see https://osm2pgsql.org/doc/manual.html#environment-variables
export PGUSER="admin"
export PGPASSWORD="admin"
export PGDATABASE="osm2vdv462"
export PGPORT="5432"

export PG_ADMIN_EMAIL="admin@mail.com"
export PG_ADMIN_PASSWORD="admin"

export DOCKER_NETWORK="osm2vdv462_net"

EXPORT_FILE="export.xml"

# Check if port PGPORT (postgresql) is already in use
# If so, kill it
if lsof -Pi :$PGPORT -sTCP:LISTEN -t >/dev/null ; then
    echo "Port $PGPORT is already in use. The process has to be stopped ... continue?"
    if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
      sudo kill -9 $(sudo lsof -t -i:$port)
    else
      echo "Aborting."
      exit
    fi
fi

# Optionally install and run pgadmin for easier database management
read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4

# Check if Docker Compose is already running
if [ ! "$(docker-compose ps -q)" ]; then
  # Start Docker Compose project:
  echo "Starting Docker Compose project ..."

  if [ $USE_PGADMIN4 ]; then
    docker-compose --profile pgadmin4 up -d
  else
    docker-compose up -d
  fi
  
  echo "Waiting for PPR to load the routing graph ..."
  MAX_RETRIES=10
  RETRY_DELAY=10
  # loop until the maximum number of retries is reached
  for i in $(seq 1 $MAX_RETRIES); do
      # check the health of the container using curl command
      HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9042)
      echo "$HEALTH"

      # check the status code returned by curl
      if [ "$HEALTH" -eq "200" ]; then
          # exit the loop if the container is healthy
          echo "PPR container is healthy"
          break
      else
          # wait for the retry delay before checking again
          sleep $RETRY_DELAY
          echo "Waiting ..."
      fi
  done

  # exit with error if the container is still not healthy
  if [ "$HEALTH" -ne "200" ]; then
      echo "Container is not healthy after $MAX_RETRIES retries"
      exit 1
  fi
  echo "Docker Compose project started."

else
  # check, if PGADMIN4 is already running
  if [ $USE_PGADMIN4 ]; then
    docker-compose --profile pgadmin4 up -d
    echo "Started PGADMIN4."
  fi
  echo "Docker Compose project is already running."
  
fi


echo "Download latest public transport operator list from Wikidata:"
csv=$(
  curl 'https://query.wikidata.org/sparql' \
    --data-urlencode query@"$(pwd)/scripts/wikidata_query.rq" \
    --header 'Accept: text/csv' \
    --progress-bar
)

docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "
    DROP TABLE IF EXISTS organisations CASCADE;
    CREATE TABLE organisations (
      id varchar(255) NOT NULL,
      label Text NOT NULL,
      alternatives Text,
      official_name Text,
      short_name varchar(255),
      website varchar(255),
      email varchar(255),
      phone varchar(255),
      address Text,
      type varchar(255)
    );
  "

docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "COPY organisations FROM STDIN DELIMITER ',' CSV HEADER;" <<< "$csv"

echo "Imported operator list into the database."


read -p "Do you want to import an OSM file? (y/n) " RUN_IMPORT
# Import osm data file
if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
  read -p "Enter the OSM file(s) that should be imported: " IMPORT_FILE
  # Run osm2pgsql import scripts
  osm2pgsql \
    --host "localhost" \
    --slim \
    --drop \
    --cache 2048 \
    --output flex \
    --style "$(pwd)/scripts/osm2pgsql/main.lua" \
    $IMPORT_FILE
fi


read -p "Do you want to run the export? (y/n) " RUN_EXPORT
# Export to VDV462 xml file
if [ "$RUN_EXPORT" = "y" ] || [ "$RUN_EXPORT" = "Y" ]; then
  echo "Exporting..."
  # Run export sql script via psql
  cat \
    ./scripts/pgsql/setup.sql \
    ./scripts/pgsql/stop_places.sql \
  | docker exec -i osm2vdv462_postgis \
    psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction

  # Start python ppr docker
  echo -n  "Executing osm2vdv462_python: "
  docker exec osm2vdv462_python python3 ppr.py

  cat \
    ./scripts/pgsql/setup.sql \
    ./scripts/pgsql/stop_places_2.sql \
    ./scripts/pgsql/organisations.sql \
    ./scripts/pgsql/export.sql \
  | docker exec -i osm2vdv462_postgis \
    psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction \
  > $EXPORT_FILE

  echo "Done. Export has been saved to $(pwd)/$EXPORT_FILE"
fi


read -p "Press Enter to exit"
