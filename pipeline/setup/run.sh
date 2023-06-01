export PGUSER="admin"
export PGDATABASE="osm2vdv462"

export DOCKER_NETWORK="osm2vdv462_net"

export EXPORT_FILE="export.xml"

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
fi

# Optionally install and run pgadmin for easier database management
read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4

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