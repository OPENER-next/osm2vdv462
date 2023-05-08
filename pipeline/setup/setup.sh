# Setup tables for the pipeline

# Create organisations table:
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "
    DROP TABLE IF EXISTS organisations CASCADE;
    CREATE TABLE organisations (
      id varchar(255) NOT NULL,
      label Text NOT NULL,
      alternatives Text,
      official_name Text,
      short_name varchar(255),
      website varchar(255),
      email varchar(255),
      phone varchar(255),
      address Text,
      type varchar(255)
    );
  "

# Create paths table:
#   Contains all paths between stop place elements
#   This table will be filled in the "routing" step of the pipeline.
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c '
    DROP TABLE IF EXISTS paths CASCADE;
    CREATE TABLE paths (
      id SERIAL PRIMARY KEY,
      stop_area_relation_id INT,
      "from" TEXT,
      "to" TEXT,
      geom GEOMETRY
    );
  '

# Create paths_elements_ref table:
#   Reference table for paths to osm elements (id and type)
#   A path is likely composed of multiple OSM elements and an OSM element can be used in multiple paths.
#   This table wil be filled in the "routing" step of the pipeline.
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "
    DROP TABLE IF EXISTS paths_elements_ref CASCADE;
    CREATE TABLE paths_elements_ref (
      path_id INT,
      osm_type CHAR(1),
      osm_id INT
    );
  "

# Create category type:
docker exec -i osm2vdv462_postgis psql \
  -U $PGUSER \
  -d $PGDATABASE \
  -q \
  -c "
    DROP TYPE IF EXISTS category CASCADE;
    CREATE TYPE category AS ENUM ('QUAY', 'ENTRANCE', 'PARKING', 'ACCESS_SPACE', 'SITE_PATH_LINK');
  "