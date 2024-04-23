# Import osm data file with osm2pgsql
if [ "$RUN_IMPORT" = "y" ] || [ "$RUN_IMPORT" = "Y" ] || [ "$RUN_AUTOMATICALLY" = "true" ]; then
  # Run osm2pgsql import scripts
  docker compose --profile osm2pgsql up -d --force-recreate
  # -T disables pseudo-tty allocation to prevent "The input device is not a TTY"
  # see: https://stackoverflow.com/questions/43099116/error-the-input-device-is-not-a-tty
  docker compose exec -T osm2vdv462_osm2pgsql osm2pgsql \
    --slim \
    --drop \
    --cache 2048 \
    --output flex \
    --style "/scripts/osm2pgsql/main.lua" \
    /input/$IMPORT_FILE
fi

# Run stop_places sql script via psql
cat \
  ./pipeline/stop_places/sql/stop_places.sql \
  ./pipeline/stop_places/sql/parkings.sql \
| docker exec -i osm2vdv462_postgis \
  psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction