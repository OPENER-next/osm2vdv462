# Download and import public transport operator list from Wikidata

# Download latest public transport operator list from Wikidata
echo "Download latest public transport operator list from Wikidata:"
csv=$(
  curl 'https://query.wikidata.org/sparql' \
    --data-urlencode query@"$(pwd)/pipeline/organisations/wikidata_query.rq" \
    --header 'Accept: text/csv' \
    --progress-bar
)

# Truncate organisations table (delete all rows from previous runs) and import operator list into the database
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "TRUNCATE TABLE organisations;" \
  -c "COPY organisations FROM STDIN DELIMITER ',' CSV HEADER;" <<< "$csv"

echo "Imported operator list into the database."

# Run organisations sql script via psql
  cat \
    ./pipeline/organisations/sql/organisations.sql \
  | docker exec -i osm2vdv462_postgis \
    psql -U $PGUSER -d $PGDATABASE --tuples-only --quiet --no-align --field-separator="" --single-transaction