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
 * Create paths_elements_ref table:
 * Reference table for path links to osm elements. A path link is likely composed of multiple OSM elements.
 * Nodes, ways and areas are stored in separate arrays to be able to query them separately.
 * This table will be filled in the "routing" step of the pipeline.
 */
CREATE TABLE paths_elements_ref (
  path_id INT,
  osm_type CHAR(1),
  osm_id BIGINT,
  -- constraint used to filter potential duplicated entries inside the same path
  CONSTRAINT check_unique UNIQUE (path_id, osm_type, osm_id)
);


/* Create path_links table:
 * Table for the elemental path links between nodes.
 * Nodes can be stop_area_elements (IFOPT from OSM) and access_spaces (IFOPT generated in the "routing" step).
 * The level column is used to store the number of passed levels between the start and end node.
 * This table will be filled in the "routing" step of the pipeline.
 * Note that the path_id will be incremented even if the CONSTRAINT check_unique_2 is violated.
 * So there will be gaps in the path_id sequence.
 * See: https://stackoverflow.com/questions/37204749/serial-in-postgres-is-being-increased-even-though-i-added-on-conflict-do-nothing
 */
CREATE TABLE path_links (
  path_id SERIAL PRIMARY KEY,
  stop_area_relation_id INT,
  start_node_id TEXT,
  end_node_id TEXT,
  level NUMERIC, -- positive for upwards link, negative for downwards link
  geom GEOMETRY,
  -- constraint used to filter potential duplicated path links
  -- include geom column because in rare cases the start & end node can be identical for different path links
  -- e.g. when stairs and escelators start and end at the same nodes.
  CONSTRAINT check_unique_2 UNIQUE (start_node_id, end_node_id, geom)
);


/*
 * Create category type:
 * Enum type named "category" to account for the different types of stop place elements.
 * Used in the "routing" and the "export" step of the pipeline.
 * The order is important as it is used to sort/order the different categories later in the export.
 */
CREATE TYPE category AS ENUM ('ENTRANCE', 'QUAY', 'ACCESS_SPACE', 'PARKING', 'SITE_PATH_LINK');


/*
 * Create access_spaces table:
 * Table for the access spaces that will be generated from the paths.
 * This table will be filled in the "routing" step of the pipeline.
 * The node_ids of the nodes have to be stored as BIGINT because the OSM ids are too big for INT.
 * Levels are stored as NUMERIC because they can be e.g. 0.5 or -1.
 * The constraint PK_id is used to make sure, that there is only one access space per node and level.
 */
CREATE TABLE access_spaces (
  node_id BIGINT NOT NULL,
  relation_id INT NOT NULL,
  "level" NUMERIC NOT NULL,
  "IFOPT" TEXT NOT NULL,
  geom GEOMETRY,
  CONSTRAINT PK_id PRIMARY KEY (node_id,"level")
);