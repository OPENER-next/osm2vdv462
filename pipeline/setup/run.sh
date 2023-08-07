export PGUSER="admin"
export PGDATABASE="osm2vdv462"

export DOCKER_NETWORK="osm2vdv462_net"

export EXPORT_FILE="export.xml"

export RUN_IMPORT=""
export RUN_PREPROCESSING=""
export USE_PGADMIN4=""

# Optionally get user input if the script is not run automatically: 
if ! [ "$RUN_AUTOMATICALLY" = "true" ]; then
  # Import a new OSM file to be used for PPR and OSM2PGSQL
  read -p "Do you want to import an OSM file? (y/n) " RUN_IMPORT
  # Run the routing preprocessing
  read -p "Do you want to (re)run the routing preprocessing? (y/n) " RUN_PREPROCESSING
  # Install and run pgadmin for easier database management
  read -p "Do you want to use pgadmin4? (y/n) " USE_PGADMIN4
fi

# Get the import osm data file
if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ]; then
  export IMPORT_FILE_PATH=""
  read -p "Enter the OSM file that should be imported: " IMPORT_FILE_PATH
fi

# Check, if the file exists
if ! [ -f $IMPORT_FILE_PATH ]; then
  echo "File $IMPORT_FILE_PATH does not exist."
  return 1
fi

# Retrieve the filename from the path
if [ "$IMPORT_FILE_PATH" != "" ]; then
  export IMPORT_FILE=$(basename "$IMPORT_FILE_PATH")
else
  export IMPORT_FILE=""
fi