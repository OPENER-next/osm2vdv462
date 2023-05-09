# Setup tables for the pipeline

cat \
  ./pipeline/setup/config.sql \
  ./pipeline/setup/setup.sql \
  | docker exec -i osm2vdv462_postgis \
  psql -U $PGUSER -d $PGDATABASE --quiet