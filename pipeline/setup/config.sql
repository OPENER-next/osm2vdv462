/***************************************
 * Setup the database for the pipeline *
 ***************************************/

-- Set the default language of the export to german
ALTER DATABASE osm2vdv462 SET export.LANGUAGE TO 'de';
-- Set the default projectionof the export to WGS84
ALTER DATABASE osm2vdv462 SET export.PROJECTION TO 4326;
-- Set the default timezone to Europe/Berlin
ALTER DATABASE osm2vdv462 SET TIMEZONE TO 'Europe/Berlin';


-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;
-- Enable Topology
CREATE EXTENSION IF NOT EXISTS postgis_topology;