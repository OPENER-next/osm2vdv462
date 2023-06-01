# This script is meant to be run from the root of the project
# Run the steps of the pipeline after each other

# source the script to be able to use the environment variables in the following steps
source pipeline/setup/run.sh

pipeline/organisations/run.sh

# Start Docker Compose project:
echo "Starting Docker Compose project ..."

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

read -p "Do you want to run the export? (y/n) " RUN_EXPORT
# Export to VDV462 xml file
if [ "$RUN_EXPORT" = "y" ] || [ "$RUN_EXPORT" = "Y" ]; then
  echo "Exporting..."

  pipeline/stop_places/run.sh

  pipeline/routing/run.sh

  pipeline/export/run.sh

  echo "Done. Export has been saved to $(pwd)/$EXPORT_FILE"
fi

read -p "Press Enter to exit"
