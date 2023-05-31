# Run export sql script via psql
cat \
  ./pipeline/export/export.sql \
| docker exec -i osm2vdv462_postgis \
  psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction \
> $EXPORT_FILE