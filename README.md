# OSM to VDV462 export pipeline

This repository offers a shell script to convert OpenStreetMap data (public transport stops and related elements) to the [VDV462](https://www.vdv.de/vdv-462-netex-schrift-v00-26d.pdfx) format. This is done by first pre-processing and extracting relevant OSM data into a PostgreSQL database in which then the data will by further processed, combined and ultimately exported as VDV462 compliant XML.

## Installation:

The export pipeline requires [docker](https://www.docker.com/) and [osm2pgsql](https://osm2pgsql.org/) to be installed.
You can find the respective installation instructions here:
- [How to install docker](https://docs.docker.com/engine/install/)
- [How to install osm2pgsql](https://osm2pgsql.org/doc/install.html)

## How to use:

0. Run the `start.sh`, which will guide you through the conversion process step by step.

1. On the first run docker will download and create the necessary postgis container as well as a volume where the database will be stored.

   Optionally you can choose to run pgAdmin, which provides a graphical user interface to view, manage and edit the PostgreSQL database.
If you do so you can access it via `localhost` using the following credentials: email=`admin@mail.com`, password=`admin`

2. Once the PostgreSQL database is running you get prompted to import your OSM data.
The data should be supplied as a `.osm`, `.osm.pbf` or `.o5m` file.
You can find and download OSM data for all sorts of countries and regions on [geofabrik](https://download.geofabrik.de/).

   If you decide not to import any data the export will use the data from the last imported file.

3. After importing the OSM data into the database is completed you can now finally choose to export it.
This step should be relatively fast in comparison to the data import.
Ultimately a single `export.xml` file will be stored in the root directory of the project.
