# Pipeline

The OSM2VDV462 pipeline consists of multiple steps:

1. (optionally) input an `*.osm.pbf` file to be used for the [Per Pedes Routing](https://motis-project.de/docs/api/endpoint/ppr.html) (PPR) preprocessing and osm2pgsql
2. start the docker-compose services
3. import organisations data from wikidata into the database
4. (optionally) import the osm file into the database with osm2pgsql
5. extract all relevant elements of stop places and create combined views
6. (optionally) run the PPR preprocessing
7. get the footpaths between all relevant places from PPR and insert them into the database
8. export the final .xml file

## File structure:

**setup:**

- `run.sh`: User interaction and variable initialization.
- `sql/*.sql`: SQL files to configure the database and create some tables that are filled in the later steps. These files are mounted to the postgis docker container and are executed in alphabetical order once when the container is started (see "Initialization scripts": [Docker postgres](https://hub.docker.com/_/postgres)).
- `pgadmin_servers.json`: Config file for pgAdmin, mounted as a bind mount to the `osm2vdv462_pgadmin4` docker container.

**organisations:**

- `run.sh`: Download and import the public transport operator list from Wikidata into the database.
- `wikidata_query.rq`: SPARQL Wikidata query used to get the data from operators (transport companies) in germany.
- `sql/organisations.sql`: SQL script used to extract organisations data from the database that is later used by the exporting step.

**stop_places:**

- `run.sh`: Optionally import the osm file into the database with osm2pgsql. Run sql scripts regarding stop places via psql.
- `lua/*.lua`: Lua scripts used by osm2pgsql to analyse the `*.osm.pbf` file and create tables for the elements of stop places.
- `sql/stop_places.sql`: SQL script used to extract relevant elements from the database and combine them into views that are used by PPR and the exporting step.

**routing:**

- `run.sh`: Optionally run the PPR preprocessing. Start the backend and check, if the routing graph has been loaded successfully. Get the paths between all relevant places from PPR and insert them into the database.
- `Dockerfile`: Dockerfile used in the `docker-compose.yaml` to build the `osm2vdv462_python` image.
- `ppr.py`: Load relevant data from the database, make requests to PPR and save the paths into the database. This script runs inside the `osm2vdv462_python` docker container.
- `config/config_ppr.ini`: Config file used to configure the PPR backend, mounted as a bind mount to the `osm2vdv462_ppr_backend` docker container.
- `config/profiles/*.json`: Json profiles used to make the request to PPR (see [PPR GitHub](https://github.com/motis-project/ppr/tree/master/profiles)).

**export:**

- `run.sh`: Run the `export.sql*` script via psql.
- `export.sql*`: SQL script used to make the final export.