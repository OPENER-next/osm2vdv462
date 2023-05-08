# Download and import public transport operator list from Wikidata

# Download latest public transport operator list from Wikidata
echo "Download latest public transport operator list from Wikidata:"
csv=$(
  curl 'https://query.wikidata.org/sparql' \
    --data-urlencode query@"$(pwd)/pipeline/organisations/wikidata_query.rq" \
    --header 'Accept: text/csv' \
    --progress-bar
)

# Import operator list into the database
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "COPY organisations FROM STDIN DELIMITER ',' CSV HEADER;" <<< "$csv"

echo "Imported operator list into the database."