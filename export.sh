# This script is meant to be run from the root of the project
# Run the steps of the pipeline after each other

# Print help in case parameter values are wrong or parameters are not existing
helpFunction()
{
   echo ""
   echo "Usage: $0 -p <True/False> -i <path_to_file/False> -e <True/False> -r <True/False>"
   echo "\t-p <True/False> Use pgadmin4 for web-based database management."
   echo "\t-i <True/False> Import a new *.osm.pbf file to use for the export."
   echo "\t-f <path_to_file> Path to the *.osm.pbf file to use for the export and/or the routing preprocessing."
   echo "\t-e <True/False> Run the export."
   echo "\t-r <True/False> Run the routing preprocessing."
   echo "If a parameter is not passed, the script will ask for it interactively."
   exit 1 # Exit script after printing help
}

# create a regex pattern to check if the parameter is either True or False
parameter_pattern='^(True|False|true|false)$'

# Allow passing variables to the script:
while getopts "p:i:f:e:r:" opt
do
   case "$opt" in
      p ) 
        if [[ "$OPTARG" =~ $parameter_pattern ]]; then # Check if the input matches the regex pattern
          export PARAMETER_PGADMIN="$OPTARG"
        else
          helpFunction
        fi
      ;;
      i ) 
        if [[ "$OPTARG" =~ $parameter_pattern ]]; then
          export PARAMETER_IMPORT="$OPTARG"
        else
          helpFunction
        fi
      ;;
      f ) 
        export PARAMETER_IMPORT_FILE_PATH="$OPTARG"
      ;;
      e ) 
        if [[ "$OPTARG" =~ $parameter_pattern ]]; then
          export PARAMETER_EXPORT="$OPTARG"
        else
          helpFunction
        fi
      ;;
      r ) 
        if [[ "$OPTARG" =~ $parameter_pattern ]]; then
          export PARAMETER_PREPROCESSING="$OPTARG"
        else
          helpFunction
        fi
      ;;
      ? ) helpFunction ;; # Print helpFunction in case parameter is non-existent
   esac
done

# source the script to be able to use the environment variables in the following steps
source pipeline/setup/run.sh
if [ $? != 0 ]; then
  echo "Error while setting up the environment. Quitting ..."
  exit 1
fi

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

pipeline/organisations/run.sh
if [ $? != 0 ]; then
  echo "Error while importing organisations. Quitting ..."
  exit 1
fi

if ! [ "$PARAMETER_EXPORT" ]; then
  read -p "Do you want to run the export? (y/n) " RUN_EXPORT
fi

# Export to VDV462 xml file
if [ "$RUN_EXPORT" = "y" ] ||
   [ "$RUN_EXPORT" = "Y" ] ||
   [ "$PARAMETER_EXPORT" = "True" ] ||
   [ "$PARAMETER_EXPORT" = "true" ]; then
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

  echo "$EXPORT_FILE"

  echo "Done. Export has been saved to $(pwd)/$EXPORT_FILE"
fi

read -p "Press Enter to exit"
