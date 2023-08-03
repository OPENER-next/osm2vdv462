export PGUSER="admin"
export PGDATABASE="osm2vdv462"

export DOCKER_NETWORK="osm2vdv462_net"

export EXPORT_FILE="export.xml"

export IMPORT_FILE_PATH=""
export IMPORT_FILE=""

export RUN_IMPORT=""

export USE_PGADMIN4=""

# Optionally import a new OSM file to be used for PPR and OSM2PGSQL
if ! [ "$PARAMETER_IMPORT" ]; then
  read -p "Do you want to import an OSM file? (y/n) " RUN_IMPORT
fi

if ! [ "$PARAMETER_PREPROCESSING" ]; then
  read -p "Do you want to (re)run the routing preprocessing? (y/n) " RUN_PREPROCESSING
fi

# Import osm data file
if [ "$RUN_IMPORT" = "y" ] ||
    [ "$RUN_IMPORT" = "Y" ] ||
    [ "$PARAMETER_IMPORT" = "True" ] ||
    [ "$PARAMETER_IMPORT" = "true" ] ||
    [ "$RUN_PREPROCESSING" = "y" ] ||
    [ "$RUN_PREPROCESSING" = "Y" ] ||
    [ "$PARAMETER_PREPROCESSING" = "True" ] ||
    [ "$PARAMETER_PREPROCESSING" = "true" ]; then

  if ! [ "$PARAMETER_IMPORT_FILE_PATH" ]; then
    read -p "Enter the OSM file that should be imported: " IMPORT_FILE_PATH
  else
    IMPORT_FILE_PATH="$PARAMETER_IMPORT_FILE_PATH"
  fi

  if ! [ -f $IMPORT_FILE_PATH ]; then
    echo "File $IMPORT_FILE_PATH does not exist."
    return 1
  fi
fi

if [ "$IMPORT_FILE_PATH" != "" ]; then
  export IMPORT_FILE=$(basename "$IMPORT_FILE_PATH")
fi

# Optionally install and run pgadmin for easier database management
if ! [ "$PARAMETER_PGADMIN" ]; then
  read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4
else
  if [ "$PARAMETER_PGADMIN" = "True" ] || [ "$PARAMETER_PGADMIN" = "true" ]; then
    USE_PGADMIN4="y"
  fi
fi