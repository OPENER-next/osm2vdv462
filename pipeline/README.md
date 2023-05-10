# Pipeline

The OSM2VDV462 pipeline consists of multiple steps:

1. (optionally) import an `*.osm.pbf` file to be used for the [Per Pedes Routing](https://motis-project.de/docs/api/endpoint/ppr.html) (PPR) preprocessing and osm2pgsql
2. (optionally) run the PPR preprocessing
3. start the docker-compose services
4. prepare the PGSQL database and create tables that are used in the later steps
5. import organisations data from wikidata into the database
6. (optionally) import the osm file into the database with osm2pgsql
7. extract all relevant elements of stop places and create combined views
8. get the footpaths between all relevant places from PPR and insert them into the database
9. export the final .xml file

## File structure:

**setup:**

- `sql/*.sql`: SQL files to configure the database and create some tables that are filled in the later steps. These files are mounted to the postgis docker container and are executed in alphabetical order once when the container is started (see "Initialization scripts": [Docker postgres](https://hub.docker.com/_/postgres)).
- `pgadmin_servers.json`: Config file for pgAdmin, mounted as a bind mount to the `osm2vdv462_pgadmin4` docker container.

**organisations:**

- `organisations.sh`: Download and import the public transport operator list from Wikidata into the database.
- `wikidata_query.rq`: SPARQL Wikidata query used to get the data from operators (transport companies) in germany.

**stop_places:**

- `*.lua`: Lua scripts used by osm2pgsql to analyse the `*.osm.pbf` file and create tables for the elements of stop places.

**routing:**

- `Dockerfile`: Dockerfile used in the `docker-compose.yaml` to build the `osm2vdv462_python` image.
- `ppr.py`: Load relevant data from the database, make requests to PPR and save the paths into the database. This script runs inside the `osm2vdv462_python` docker container.
- `config/config_ppr.ini`: Config file used to configure the PPR backend, mounted as a bind mount to the `osm2vdv462_ppr_backend` docker container.
- `config/profiles/*.json`: Json profiles used to make the request to PPR (see [PPR GitHub](https://github.com/motis-project/ppr/tree/master/profiles)).

**export:**

- `*.sql*`: SQL scripts used to extract relevant elements from the database and combine them into views that are used by PPR and to make the final export.