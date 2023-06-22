/*******************************************
 * Create tables to be used in later steps *
 *******************************************/
 
/* 
 * Create organisations table:
 * Table for the public transport operator list from Wikidata
 * This table will be filled in the "organisations" step of the pipeline.
 */
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


/* 
 * Create paths table:
 * Table for the paths generated by PPR
 * This table will be filled in the "routing" step of the pipeline.
 */
CREATE TABLE paths (
  id SERIAL PRIMARY KEY,
  stop_area_relation_id INT,
  "from" TEXT,
  "to" TEXT,
  geom GEOMETRY
);


/* 
 * Create paths_elements_ref table:
 * Reference table for paths to osm elements (id and type)
 * A path is likely composed of multiple OSM elements and an OSM element can be used in multiple paths.
 * This table will be filled in the "routing" step of the pipeline.
 */
CREATE TABLE paths_elements_ref (
  path_id INT,
  osm_type CHAR(1),
  osm_id INT
);


/* Create path_links table:
 * Table for the elemental path links between nodes.
 * Nodes can be stop_area_elements (IFOPT from OSM) and access_spaces (IFOPT generated in the "routing" step).
 * This table will be filled in the "routing" step of the pipeline.
 */
CREATE TABLE path_links (
  path_id INT,
  smaller_node_id TEXT,
  bigger_node_id TEXT,
  geom GEOMETRY,
  CONSTRAINT PK_node PRIMARY KEY (smaller_node_id,bigger_node_id),
  CONSTRAINT ids_check CHECK (smaller_node_id < bigger_node_id)
);


/* 
 * Create category type:
 * Enum type named "category" to account for the different types of stop place elements.
 * Used in the "routing" and the "export" step of the pipeline.
 */
CREATE TYPE category AS ENUM ('QUAY', 'ENTRANCE', 'PARKING', 'ACCESS_SPACE', 'SITE_PATH_LINK');


/* 
 * Create access_spaces table:
 * Table for the access spaces that will be generated from the paths.
 * This table will be filled in the "routing" step of the pipeline.
 * The osm_ids of the nodes have to be stored as BIGINT because the OSM ids are too big for INT.
 * The constraint PK_id is used to make sure, that there is only one access space per node and level.
 */
CREATE TABLE access_spaces (
  osm_id BIGINT NOT NULL,
  "level" TEXT NOT NULL,
  "IFOPT" TEXT NOT NULL,
  tags jsonb,
  geom GEOMETRY,
  CONSTRAINT PK_id PRIMARY KEY (osm_id,"level")
);