# Pipeline

The OSM2VDV462 pipeline consists of multiple steps:

1. (optionally) import an `*.osm.pbf` file to be used for the [Per Pedes Routing](https://motis-project.de/docs/api/endpoint/ppr.html) (PPR) preprocessing and osm2pgsql
2. (optionally) run the PPR preprocessing
3. start the docker-compose services
4. prepare the PGSQL database and create tables that are used in the later steps
5. import organisations data from wikidata into the database
6. (optionally) import the osm file into the database with osm2pgsql
7. get the footpaths between all relevant places from PPR and insert them into the database
8. export the final .xml file

## File structure:

**setup:**
- `setup.sh`: configure database and create tables to be used in the later steps

**organisations:**
- `organisations.sh`: download and import the public transport operator list from Wikidata into the database
- `wikidata_query.rq`: SPARQL Wikidata query used to get the data from operators (transport companies) in germany

**stop_places:**
- `*.lua`: lua scripts used by osm2pgsql to analyse the `*.osm.pbf` file and create tables for the elements of stop places

**routing:**
- `ppr.py`: load relevant data from the database, make requests to PPR and save the paths into the database
- `config/config_ppr.ini`: config file used to configure the PPR backend
- `config/profiles/*.json`: json profiles used to make the request to PPR (see [PPR GitHub](https://github.com/motis-project/ppr/tree/master/profiles))

**export:**
- `*.sql*`: SQL scripts used to extract relevant elements from the database and combine them into views that are used by PPR and to make the final export