# This script is meant to be run from the root of the project
# Run the steps of the pipeline after each other

# source the scripts to be able to use the variables in the folllowing steps
source pipeline/setup/run.sh

source pipeline/organisations/run.sh

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
