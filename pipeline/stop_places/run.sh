# Import osm data file with osm2pgsql
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

# Run stop_places sql script via psql
cat \
  ./pipeline/stop_places/sql/stop_places.sql \
| docker exec -i osm2vdv462_postgis \
  psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction