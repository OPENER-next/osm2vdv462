/****************
 * SETUP EXPORT *
 ****************/

-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;
-- Enable Topology
CREATE EXTENSION IF NOT EXISTS postgis_topology;


SET export.PROJECTION TO 4326;

SET export.LANGUAGE TO 'de';

SET TIMEZONE TO 'Europe/Berlin';
