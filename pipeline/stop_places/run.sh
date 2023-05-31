# Run stop_places sql script via psql
cat \
  ./pipeline/stop_places/sql/stop_places.sql \
| docker exec -i osm2vdv462_postgis \
  psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction