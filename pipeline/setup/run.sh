export PGUSER="admin"
export PGDATABASE="osm2vdv462"

export DOCKER_NETWORK="osm2vdv462_net"

export EXPORT_FILE="export.xml"

export IMPORT_FILE_PATH=""
export IMPORT_FILE=""

export RUN_IMPORT=""


# Optionally import a new OSM file to be used for PPR and OSM2PGSQL
read -p "Do you want to import an OSM file? (y/n) " RUN_IMPORT
# Import osm data file
if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
  read -p "Enter the OSM file(s) that should be imported: " IMPORT_FILE_PATH
  if ! [ -f $IMPORT_FILE_PATH ]; then
    echo "File does not exist."
    return 1
  fi

  export IMPORT_FILE_PATH
  export IMPORT_FILE=$(basename "$IMPORT_FILE_PATH")
fi
