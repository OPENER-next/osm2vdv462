# OSM to VDV462 export pipeline

This repository offers a shell script to convert OpenStreetMap data (public transport stops and related elements) to the [VDV462](https://www.vdv.de/vdv-462-netex-schrift-v00-26d.pdfx) format. This is done by first pre-processing and extracting relevant OSM data into a PostgreSQL database in which then the data will by further processed, combined and ultimately exported as VDV462 compliant XML.

## Installation:

The export pipeline requires [docker](https://www.docker.com/) and [osm2pgsql](https://osm2pgsql.org/) to be installed.
You can find the respective installation instructions here:
- [How to install docker](https://docs.docker.com/engine/install/)
- [How to install osm2pgsql](https://osm2pgsql.org/doc/install.html)

The OSM data to be used can be downloaded from [geofabrik](https://download.geofabrik.de/). There you can find OSM extracts for all sorts of countries and regions. It has to be in the *.osm.pbf format. Please have in mind that there are high memory and RAM requirements for bigger regions as e.g. germany. On smaller machines you should use smaller extracts for testing.

```
cd osm2vdv462
mkdir data
curl -L -o data/germany-latest.osm.pbf https://download.geofabrik.de/europe/germany-latest.osm.pbf
```

For generating the paths between stop places, the [Per Pedes Routing](https://motis-project.de/docs/api/endpoint/ppr.html) submodule from the [MOTIS project](http://motis-project.de/) is used. Run the following lines to start the PPR preprocessing inside a docker container (this has only to be done once):

```
docker pull ghcr.io/motis-project/ppr:edge
docker run --rm -it -v $(pwd)/data:/data ghcr.io/motis-project/ppr:edge /ppr/ppr-preprocess --osm /data/germany-latest.osm.pbf --graph /data/germany.ppr
```

Alternatively, if [elevation data](https://github.com/motis-project/ppr/wiki/Elevation-Data-(DEM)) is used:

```
docker run --rm -it -v $(pwd)/data:/data -v /path/to/srtm:/srtm ghcr.io/motis-project/ppr:edge /ppr/ppr-preprocess --osm /data/germany-latest.osm.pbf --graph /data/germany.ppr --dem /srtm
```

If you want to update the OSM data to the newest version just again download the  desired *.osm.pbf and run the PPR preprocessing step described above.

## How to use:

0. Run the `start.sh`, which will guide you through the conversion process step by step.

1. On the first run docker will download and create the necessary postgis container as well as a volume where the database will be stored.

   Optionally you can choose to run pgAdmin, which provides a graphical user interface to view, manage and edit the PostgreSQL database.
If you do so you can access it via `localhost` using the following credentials: email=`admin@mail.com`, password=`admin`

2. Once the PostgreSQL database is running you get prompted to import your OSM data.
The data should be supplied as a `.osm`, `.osm.pbf` or `.o5m` file.

   If you decide not to import any data the export will use the data from the last imported file.

3. After importing the OSM data into the database is completed you can now finally choose to export it.
This step should be relatively fast in comparison to the data import.
Ultimately a single `export.xml` file will be stored in the root directory of the project.

## Troubleshooting:

`Error response from daemon: Ports are not available: exposing port TCP 0.0.0.0:5432 -> 0.0.0.0:0: listen tcp 0.0.0.0:5432: bind: address already in use`

- This means, that postgresql is already running on your machine locally. To kill this process type `sudo lsof -i :5432`. The PID of the postgresql process is shown. Type `sudo kill -9 <pid>` to kill it.