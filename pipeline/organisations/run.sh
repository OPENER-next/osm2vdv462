# Run organisations import script
pipeline/organisations/organisations.sh

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