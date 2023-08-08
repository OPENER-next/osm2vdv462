# This script is meant to be run from the root of the project
# Run the steps of the pipeline after each other

# Print help in case parameter values are wrong or parameters are not existing
helpFunction()
{
   echo "Usage: $0 <my-osm-file.osm.pbf>"
   echo "  If no parameter is passed, the script will interactively guide through all steps of the export."
   exit 1 # Exit script after printing help
}

# Allow passing the help variable to the script:
while getopts "h" opt
do
   case "$opt" in
      h ) 
        helpFunction
      ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# get the passed parameter
if [ "$1" != "" ]; then
  export RUN_AUTOMATICALLY="true"
  export IMPORT_FILE_PATH=$1
fi

# source the script to be able to use the environment variables in the following steps
source pipeline/setup/run.sh
if [ $? != 0 ]; then
  echo "Error while setting up the environment. Quitting ..."
  exit 1
fi

# Start Docker Compose project:
echo "Starting Docker Compose project ..."

if [ "$USE_PGADMIN4" = "y" ] || [ "$USE_PGADMIN4" = "Y" ]; then
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

pipeline/organisations/run.sh
if [ $? != 0 ]; then
  echo "Error while importing organisations. Quitting ..."
  exit 1
fi

if ! [ "$RUN_AUTOMATICALLY" = "true" ]; then
  read -p "Do you want to run the export? (y/n) " RUN_EXPORT
fi

# Export to VDV462 xml file
if [ "$RUN_EXPORT" = "y" ] || [ "$RUN_EXPORT" = "Y" ] || [ "$RUN_AUTOMATICALLY" = "true" ]; then
  echo "Exporting..."
  
  pipeline/stop_places/run.sh
  if [ $? != 0 ]; then
    echo "Error while exporting stop places. Quitting ..."
    exit 1
  fi

  pipeline/routing/run.sh
  if [ $? != 0 ]; then
    echo "Error while exporting routing. Quitting ..."
    exit 1
  fi

  pipeline/export/run.sh
  if [ $? != 0 ]; then
    echo "Error while exporting. Quitting ..."
    exit 1
  fi

  echo "Done. Export has been saved to $(pwd)/$EXPORT_FILE"
fi

read -p "Press Enter to exit"
