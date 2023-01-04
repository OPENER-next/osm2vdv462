/*********************
 * UTILITY FUNCTIONS *
 *********************/

/*
 * Aggregate functions for getting the first or last value
 * Below functions are taken from: https://wiki.postgresql.org/wiki/First/last_(aggregate)
 */

-- Create a function that always returns the first non-NULL value:
CREATE OR REPLACE FUNCTION public.first_agg (anyelement, anyelement)
  RETURNS anyelement
  LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
'SELECT $1';

-- Then wrap an aggregate around it:
CREATE OR REPLACE AGGREGATE public.first (anyelement) (
  SFUNC    = public.first_agg
, STYPE    = anyelement
, PARALLEL = safe
);

-- Create a function that always returns the last non-NULL value:
CREATE OR REPLACE FUNCTION public.last_agg (anyelement, anyelement)
  RETURNS anyelement
  LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
'SELECT $2';

-- Then wrap an aggregate around it:
CREATE OR REPLACE AGGREGATE public.last (anyelement) (
  SFUNC    = public.last_agg
, STYPE    = anyelement
, PARALLEL = safe
);


/********************
 * EXPORT FUNCTIONS *
 ********************/

/*
 * Create a centroid element from any geography
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_Centroid(a geometry) RETURNS xml AS
$$
SELECT xmlelement(name "Centroid",
  xmlelement(name "Location",
    -- cast to geometry required because ST_X/ST_Y can only handle geometries
    xmlelement(name "Longitude", ST_X(ST_Centroid($1)::geometry)),
    xmlelement(name "Latitude", ST_Y(ST_Centroid($1)::geometry))
  )
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a LineString element from a line string geography and its id
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_LineString(a geometry, b anyelement) RETURNS xml AS
$$
-- see https://postgis.net/docs/ST_AsGML.html
SELECT xmlelement(
  name "LineString",
  xmlattributes(
    'http://www.opengis.net/gml/3.2' AS "xmlns",
    'http://www.opengis.net/gml/3.2' AS "xmlns:n0",
    concat('LineString_', $2) AS "n0:id"
  ),
  (xpath(
    '//posList',
    xml( ST_AsGML(3, $1, 8, 22, '') )
  ))[1]
);
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a Distance element from a line string
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_Distance(a geometry) RETURNS xml AS
$$
SELECT xmlelement(name "Distance", ST_Length(
  ST_Transform($1, current_setting('export.PROJECTION')::int)::geography
))
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Creates the From and To element based on given ids
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_FromTo(a text, b text) RETURNS xml AS
$$
SELECT xmlconcat(
  xmlelement(name "From",
    xmlelement(name "PlaceRef", xmlattributes($1 AS "ref", 'any' AS "version"))
  ),
  xmlelement(name "To",
    xmlelement(name "PlaceRef", xmlattributes($2 AS "ref", 'any' AS "version"))
  )
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a single key value pair element
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION create_KeyValue(a anyelement, b anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "KeyValue",
  xmlelement(name "Key", $1),
  xmlelement(name "Value", $2)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a single key value pair element where value is empty if the given tag value equals "yes"
 * Else returns null
 */
CREATE OR REPLACE FUNCTION delfi_attribute_on_yes_xml(delfiid text, val text) RETURNS xml AS
$$
SELECT CASE
  WHEN $2 = 'yes' THEN create_KeyValue($1, '')
END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a keyList element based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
DECLARE
  result xml;
BEGIN
  result := xmlconcat(
    additionalPairs,
    delfi_attribute_on_yes_xml('1120', tags->>'bench'),
    delfi_attribute_on_yes_xml('1140', tags->>'passenger_information_display'),
    delfi_attribute_on_yes_xml('1141', tags->>'passenger_information_display:speech_output')
  );

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "keyList", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE;


/*
 * Create a QuayType element based on the tags: train, subway, tram, coach, bus, monorail and light_rail
 * Note: this function also takes the geography of the object to distinguish between a tramPlatform and tramStop
 * Unused types: "airlineGate" | "busBay" | "boatQuay" | "ferryLanding" | "telecabinePlatform" | "taxiStand" | "setDownPlace" | "vehicleLoadingPlace"
 * If no match is found this will always return NULL
 */
CREATE OR REPLACE FUNCTION ex_QuayType(tags jsonb, geom geography) RETURNS xml AS
$$
DECLARE
  result text;
BEGIN
  IF tags->>'train' = 'yes'
    THEN result := 'railPlatform';
  ELSEIF tags->>'subway' = 'yes'
    THEN result := 'metroPlatform';
  ELSEIF tags->>'tram' = 'yes' THEN
    IF ST_GeometryType(geom) = 'ST_Point'
      THEN result := 'tramStop';
      ELSE result := 'tramPlatform';
    END IF;
  ELSEIF tags->>'coach' = 'yes'
    THEN result := 'coachStop';
  ELSEIF tags->>'bus' = 'yes'
    THEN result := 'busStop';
  ELSEIF tags->>'light_rail' = 'yes' OR
         tags->>'monorail' = 'yes' OR
         tags->>'funicular' = 'yes'
    THEN result := 'other';
  END IF;

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "QuayType", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a single AlternativeName element with a NameType "translation" from a given language code and name.
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION create_AlternativeTranslationName(a text, b text) RETURNS xml AS
$$
SELECT xmlelement(name "AlternativeName",
  xmlelement(name "NameType", 'translation'),
  xmlelement(name "Name", xmlattributes($1 AS "lang"), $2)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a single AlternativeName element with a NameType "alias" from a given name.
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION create_AlternativeAliasName(a text) RETURNS xml AS
$$
SELECT xmlelement(name "AlternativeName",
  xmlelement(name "NameType", 'alias'),
  xmlelement(name "Name", $1)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create an AlternativeName element based on name:LANG_CODE and alt_name tags
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_alternativeNames(tags jsonb) RETURNS xml AS
$$
DECLARE
  result xml;
BEGIN
  result := xmlconcat(
    create_AlternativeTranslationName('en', tags->>'name:en'),
    create_AlternativeTranslationName('de', tags->>'name:de'),
    create_AlternativeTranslationName('fr', tags->>'name:fr'),
    create_AlternativeTranslationName('cs', tags->>'name:cs'),
    create_AlternativeTranslationName('pl', tags->>'name:pl'),
    create_AlternativeTranslationName('da', tags->>'name:da'),
    create_AlternativeTranslationName('nl', tags->>'name:nl'),
    create_AlternativeTranslationName('lb', tags->>'name:lb'),
    (
      SELECT xmlagg(
        create_AlternativeAliasName(string_to_table)
      )
      FROM string_to_table(tags->>'alt_name', ';')
    )
  );

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "alternativeNames", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a Name element based on name, official_name, description tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION ex_Name(tags jsonb) RETURNS xml AS
$$
DECLARE
  result text;
BEGIN
  result := COALESCE(
    tags->>'name',
    tags->>'name:de',
    tags->>'official_name',
    tags->>'uic_name',
    tags->>'ref',
    tags->>'ref:IFOPT:description',
    tags->>'description'
  );

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "Name", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a ShortName element based on short_name tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION ex_ShortName(tags jsonb) RETURNS xml AS
$$
DECLARE
  result text;
BEGIN
  result := COALESCE(tags->>'short_name', tags->>'short_name:de');

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "ShortName", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a Description element based on description tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION ex_Description(tags jsonb) RETURNS xml AS
$$
SELECT
  CASE
    WHEN $1->>'description' IS NOT NULL THEN xmlelement(
      name "Description",
      $1->>'description'
    )
    ELSE NULL
  END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a AuthorityRef element based on the given id.
 * Returns null if no id is provided
 */
CREATE OR REPLACE FUNCTION ex_AuthorityRef(id text) RETURNS xml AS
$$
  SELECT xmlelement(
    name "AuthorityRef",
    xmlattributes($1 AS "ref", 'any' AS "version")
  );
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a EntranceType element based on the tags: door, automatic_door
 * Unused types: "openDoor" | "ticketBarrier" | "gate"
 * If no match is found this will always return a EntranceType of "other"
 */
CREATE OR REPLACE FUNCTION ex_EntranceType(tags jsonb) RETURNS xml AS
$$
SELECT xmlelement(name "EntranceType",
  CASE
    WHEN $1->>'door' = 'yes' THEN 'door'
    WHEN $1->>'door' = 'no' THEN 'opening'
    WHEN $1->>'door' = 'swinging' THEN 'swingDoor'
    WHEN $1->>'door' = 'revolving' THEN 'revolvingDoor'
    WHEN $1->>'automatic_door' IN ('yes', 'button', 'motion') THEN 'automaticDoor'
    ELSE 'other'
  END
)
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a ParkingType element based on the tags: park_ride
 * Unused types: "liftShareParking" | "urbanParking" | "airportParking" | "trainStationParking" | "exhibitionCentreParking" |
 * "rentalCarParking" | "shoppingCentreParking" | "motorwayParking" | "roadside" | "parkingZone" | "cycleRental" | "other"
 * If no match is found this will always return a ParkingType of "undefined"
 */
CREATE OR REPLACE FUNCTION ex_ParkingType(tags jsonb) RETURNS xml AS
$$
SELECT xmlelement(name "ParkingType",
  CASE
    WHEN $1->>'park_ride' IN ('yes', 'bus', 'ferry', 'metro', 'train', 'tram') THEN 'parkAndRide'
    ELSE 'undefined'
  END
)
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a ParkingLayout element based on the tags: parking and covered
 * Unused types: "cycleHire"
 * If no match is found this will always return a ParkingLayout of "other"
 */
CREATE OR REPLACE FUNCTION ex_ParkingLayout(tags jsonb) RETURNS xml AS
$$
SELECT xmlelement(name "ParkingLayout",
  CASE
    WHEN $1->>'parking' IS NULL THEN 'undefined'
    WHEN $1->>'parking' = 'multi-storey' THEN 'multistorey '
    WHEN $1->>'parking' = 'underground' THEN 'underground'
    WHEN $1->>'parking' = 'street_side' THEN 'roadside'
    WHEN $1->>'parking' = 'surface' AND $1->>'covered' = 'yes' THEN 'covered'
    WHEN $1->>'parking' = 'surface' THEN 'openSpace'
    ELSE 'other'
  END
)
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a TotalCapacity element based on capacity tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION ex_TotalCapacity(tags jsonb) RETURNS xml AS
$$
SELECT
  CASE
    WHEN $1->>'capacity' IS NOT NULL THEN xmlelement(
      name "TotalCapacity",
      $1->>'capacity'
    )
    ELSE NULL
  END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create an AccessSpaceType element based on a variety of tags.
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_AccessSpaceType(tags jsonb) RETURNS xml AS
$$
DECLARE
  result xml;
BEGIN
  IF tags->>'indoor' = 'area' OR
     tags->>'highway' = 'pedestrian' AND tags->>'area' = 'yes' OR
     tags->>'place' = 'square' OR
     tags->>'room' = 'entrance'
    THEN result := 'concourse';
  ELSEIF tags->>'bridge' = 'yes'
    THEN result := 'overpass';
  ELSEIF tags->>'tunnel' = 'yes'
    THEN result := 'underpass';
  ELSEIF tags->>'highway' = 'elevator'
    THEN result := 'lift';
  ELSEIF tags->>'indoor' = 'corridor' OR
         tags->>'highway' IN ('footway', 'pedestrian', 'path', 'corridor') OR
         tags->>'room' = 'corridor'
    THEN result := 'passage';
  ELSEIF tags->>'stairs' = 'yes' OR
         tags->>'room' = 'stairs'
    THEN result := 'staircase';
  ELSEIF tags->>'room' = 'waiting'
    THEN result := 'waitingRoom';
  END IF;

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "AccessSpaceType", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;

/***************
 * STOP_PLACES *
 ***************/

/*
 * Create view that contains all stop areas with the wikidata id of their respective operator and network.
 * Ids will be NULL if no matching operator/newtwork can be found.
 */
CREATE OR REPLACE TEMPORARY VIEW stop_places_with_organisations AS (
  SELECT stop_areas.*, op.id AS operator_id, net.id AS network_id
  FROM stop_areas
  LEFT JOIN organisations op
  ON
    tags->>'operator:wikidata' = op.id OR
    -- ensure that if an wikidata id is present it will not be matched by name
    tags->>'operator:wikidata' IS NULL AND (
      tags->>'operator' = op.label OR
      tags->>'operator' = official_name OR
      tags->>'operator' = ANY (string_to_array(op.alternatives, ', ')) OR
      tags->>'operator:short' = op.short_name OR
      tags->>'operator:short' = ANY (string_to_array(op.alternatives, ', '))
    )
  LEFT JOIN organisations net
  ON
    tags->>'network:wikidata' = net.id OR
    -- ensure that if an wikidata id is present it will not be matched by name
    tags->>'network:wikidata' IS NULL AND (
      tags->>'network' = net.label OR
      tags->>'network' = net.official_name OR
      tags->>'network' = ANY (string_to_array(net.alternatives, ', ')) OR
      tags->>'network:short' = net.short_name OR
      tags->>'network:short' = ANY (string_to_array(net.alternatives, ', '))
    )
);


/*
 * Create view that contains all stop areas with a geometry column derived from their members
 *
 * Aggregate member stop geometries to stop areas
 * Split JOINs because GROUP BY doesn't allow grouping by all columns of a specific table
 */
CREATE OR REPLACE TEMPORARY VIEW final_stop_places AS (
  WITH
    stops_clustered_by_relation_id AS (
      SELECT ptr.relation_id, ST_Collect(geom) AS geom
      FROM stop_areas_members_ref ptr
      INNER JOIN platforms pts
        ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
      GROUP BY ptr.relation_id
    )
  SELECT pta.*, geom
  FROM stop_places_with_organisations pta
  INNER JOIN stops_clustered_by_relation_id sc
    ON pta.relation_id = sc.relation_id
);


/*
 * Create view that contains all stop areas with hull enclosing all stops.
 * The hull is padded by 100 meters
 */
CREATE OR REPLACE TEMPORARY VIEW stop_areas_with_padded_hull AS (
  SELECT
    relation_id,
    -- Expand the hull geometry
    ST_Buffer(
      -- Create a single hull geometry based on the collection
      ST_ConvexHull(geom),
      100
    ) AS geom
  FROM final_stop_places
);


/*********
 * QUAYS *
 *********/

/*
 * Create view that matches all platforms/quays to public transport areas by the reference table.
 */
CREATE OR REPLACE TEMPORARY VIEW final_quays AS (
  SELECT ptr.relation_id, pts.*
  FROM platforms pts
  JOIN stop_areas_members_ref ptr
    ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
);


/*************
 * ENTRANCES *
 *************/

/*
 * Create view that matches all entrances to public transport areas by the reference table.
 */
CREATE OR REPLACE TEMPORARY VIEW final_entrances AS (
  SELECT ptr.relation_id, ent.*
  FROM entrances ent
  JOIN stop_areas_members_ref ptr
    ON ent.node_id = ptr.member_id AND ptr.osm_type = 'N'
);


/*****************
 * ACCESS_SPACES *
 *****************/

/*
 * Create view that matches all access spaces to public transport areas by the reference table.
 */
CREATE OR REPLACE TEMPORARY VIEW final_access_spaces AS (
  SELECT ptr.relation_id, acc.*
  FROM access_spaces acc
  JOIN stop_areas_members_ref ptr
    ON acc.osm_id = ptr.member_id AND acc.osm_type = ptr.osm_type
);


/************
 * PARKINGS *
 ************/

/*
 * Create view that matches all parking spaces to public transport areas by the reference table.
 */
CREATE OR REPLACE TEMPORARY VIEW final_parkings AS (
  SELECT ptr.relation_id, par.*
  FROM parking par
  JOIN stop_areas_members_ref ptr
    ON par.osm_id = ptr.member_id AND par.osm_type = ptr.osm_type
);


/**************
 * PATH LINKS *
 **************/

/*
 * Combine all stop places in order to find paths/connections between them.
 */
CREATE OR REPLACE TEMPORARY VIEW relevant_stop_places AS (
  SELECT qua.relation_id, qua."IFOPT", qua.osm_id AS osm_id, qua.osm_type AS osm_type, qua.geom
  FROM final_quays qua
    UNION ALL
  SELECT ent.relation_id, ent."IFOPT", ent.node_id AS osm_id, 'N' AS osm_type, ent.geom
  FROM final_entrances ent
    UNION ALL
  SELECT acc.relation_id, acc."IFOPT", acc.osm_id AS osm_id, acc.osm_type AS osm_type, acc.geom
  FROM final_access_spaces acc
    UNION ALL
  SELECT par.relation_id, par."IFOPT", par.osm_id AS osm_id, par.osm_type AS osm_type, par.geom
  FROM final_parkings par
);


/*
 * Create a table that contains all potentially relevant ways.
 * This basically filters all ways that are not near/inside a stop area.
 */
DROP TABLE IF EXISTS stop_ways CASCADE;
CREATE TABLE stop_ways AS (
  SELECT pta.relation_id, highways.*
  FROM highways
  JOIN stop_areas_with_padded_hull AS pta
    ON ST_Intersects(pta.geom, highways.geom)
);

-- Build way topology --

DO $$
BEGIN
  -- perform discards the return value (in costrast to select)
  PERFORM topology.DropTopology('ways_topo')
  WHERE EXISTS (
    SELECT * FROM topology.topology WHERE name = 'ways_topo'
  );
  PERFORM topology.CreateTopology('ways_topo', current_setting('export.PROJECTION')::int);

  PERFORM topology.AddTopoGeometryColumn('ways_topo', 'public', 'stop_ways', 'topo_geom', 'LINESTRING');

  UPDATE stop_ways
  SET topo_geom = topology.toTopoGeom(geom, 'ways_topo', 1)
  -- Filter other geometries because they cannot be converted and would otherwise throw an error
  WHERE ST_GeometryType(geom) = 'ST_LineString';
END $$;

-- Improve way topolo --

DO $$
DECLARE r record;
DECLARE new_node_id INT;
BEGIN

-- Replace all assigned stop place nodes with one merged node that gets the centroid of the osm element/stop place as geometry
-- Without this step we would also get paths between the same element/feature.
  FOR r IN
    -- First get/assign all nodes that belong to the same stop place.
    WITH tmp_topology_nodes_of_elements AS (
      SELECT relation_id, array_agg(node_id) AS node_ids, osm_id, osm_type, sp.geom
      FROM relevant_stop_places sp
      JOIN ways_topo.node ed
      ON ST_Touches(sp.geom, ed.geom)
      GROUP BY relation_id, osm_id, osm_type, sp.geom
    )
    SELECT * FROM tmp_topology_nodes_of_elements
  LOOP
    -- first add new nodes
    INSERT INTO ways_topo.node(geom) VALUES (ST_Centroid(r.geom)) RETURNING node_id INTO new_node_id;
    -- update all edges with previous node id to new node id
    UPDATE ways_topo.edge_data
    SET start_node = new_node_id
    WHERE start_node = ANY(r.node_ids);

    UPDATE ways_topo.edge_data
    SET end_node = new_node_id
    WHERE end_node = ANY(r.node_ids);
    -- remove previous node
    DELETE FROM ways_topo.node
    WHERE node_id = ANY(r.node_ids);
  END LOOP;

  -- Edge topology may not be split at a point like a bus stop.
  -- This happens when there is no junction or connection to more than one edges.
  -- Therefore these points wouldn't be reachable, so every stop place of type point is addeed here.
  PERFORM TopoGeo_AddPoint('ways_topo', geom)
  FROM relevant_stop_places
  WHERE ST_GeometryType(geom) = 'ST_Point';
END $$;

--------------------------

-- Path finding functions --

/*
 * This function finds all paths between a given list of target nodes.
 * Returns a table of edges with 3 columns.
 * Two columns contain the node ids that describe the edge.
 * The thrid column contains the path id the edge belongs to.
 */
CREATE OR REPLACE FUNCTION get_paths_connecting_nodes(target_nodes INT[]) RETURNS TABLE (path_id INT, node_1 INT, node_2 INT) AS
$$
DECLARE
  visited_target_nodes INT[];
  -- holds all target nodes that haven't been used as a starting point yet
  unvisited_target_nodes INT[];

  current_node INT;

  touching_nodes INT[];

  nodes_path INT[];

  loop_count INT;
  path_counter INT := 0;
BEGIN
    unvisited_target_nodes := target_nodes;
    -- Loop as long as we have at least two unvisited target nodes
    -- Because when we are at the last node we already found all ways to this node
    -- From the previous searches of the other nodes
    WHILE array_length(unvisited_target_nodes, 1) > 1 LOOP
      -- init nodes path with current target node
      nodes_path := ARRAY[ unvisited_target_nodes[1] ];
      -- add current target node to visited nodes
      visited_target_nodes := array_append(visited_target_nodes, unvisited_target_nodes[1]);
      -- remove first element from the array
      unvisited_target_nodes := unvisited_target_nodes[2:];
      -- get all initial touching nodes from the target node
      touching_nodes := get_touching_nodes_by_path(nodes_path);

      -- Loop through nodes till all have been visited
      WHILE array_length(touching_nodes, 1) > 0 LOOP
        -- get first array element
        current_node := touching_nodes[1];
        IF current_node IS NULL THEN
          -- the two lines below basically remove the first array element
          nodes_path := nodes_path[2:];
          touching_nodes := touching_nodes[2:];
          CONTINUE;
        END IF;
        -- set first/current touching edge to NULL indicating that it has been visited/consumed
        touching_nodes[1] := NULL;
        -- add the popped element to the current nodes path
        nodes_path := array_prepend(current_node, nodes_path);
        -- check whether the current node is any of the already visited target nodes
        -- this is required to prevent passing over a target node in order to get to another target node
        IF current_node = ANY(visited_target_nodes) THEN
          -- go to next touching node instead
          CONTINUE;
        -- check whether the current node is any of the unvisited target nodes
        ELSIF current_node = ANY(unvisited_target_nodes) THEN
          -- return current path (note that it is inversed)
          FOR loop_count IN 2 .. array_length(nodes_path, 1) LOOP
            RETURN QUERY SELECT path_counter, nodes_path[loop_count - 1], nodes_path[loop_count];
          END LOOP;
          path_counter := path_counter + 1;
        ELSE
          -- get all nodes that touch the end of the current path
          -- and that are not part of the nodes path (prevents circles)
          -- add them to the start of touching_nodes if any
          touching_nodes := get_touching_nodes_by_path(nodes_path) || touching_nodes;
        END IF;
      END LOOP;
    END LOOP;

    RETURN;
END
$$
LANGUAGE plpgsql IMMUTABLE;


/*
 * Get all nodes that touch the end of the given path and that are not part of the path (prevents circles).
 * A path is an array of nodes where the first array element resembles the end of the path,
 * while the last node resembles the start.
 */
CREATE OR REPLACE FUNCTION get_touching_nodes_by_path(path INT[]) RETURNS INT[] AS
$$
  SELECT ARRAY(
    SELECT start_node
    FROM ways_topo.edge_data
    WHERE end_node = path[1] AND start_node != ALL(path)

    UNION

    SELECT end_node
    FROM ways_topo.edge_data
    WHERE start_node = path[1] AND end_node != ALL(path)
  )
$$
LANGUAGE SQL IMMUTABLE;

----------------------------

/*
 * Create an assignment table of osm elements to topology node ids
 * This already includes the stop area relation id.
 * Temporary table is used to improve performance.
 */
DROP TABLE IF EXISTS topology_node_to_osm_element CASCADE;
CREATE TEMPORARY TABLE topology_node_to_osm_element AS (
  SELECT sp.*, ed.node_id
  FROM relevant_stop_places sp
  JOIN ways_topo.node ed
  ON ST_Equals(ST_Centroid(sp.geom), ed.geom)
);


/*
 * Get all connecting paths via get_paths_connecting_nodes()
 * Assign them to a stop area relation id.
 * Add nr column so it can be sorted/ordered later, because order might be lost on joins.
 */
CREATE OR REPLACE TEMPORARY VIEW stop_area_paths AS (
  SELECT relation_id, path_id, node_1, node_2, row_number() OVER() AS nr
  FROM (
    -- first group by / merge all node ids to an array
    SELECT relation_id, array_agg(node_id) AS node_ids
    FROM topology_node_to_osm_element
    GROUP BY relation_id
    ) tne,
    -- get connecting paths by passing array of each row
    LATERAL get_paths_connecting_nodes(tne.node_ids) pa
);


/*
 * stop_area_paths ever only returns undirected paths between stop places
 * Therefore for every path we need to create a respective reversed path
 */
CREATE OR REPLACE TEMPORARY VIEW stop_area_paths_bidirectional AS (
  WITH max_ids (max_path_id, max_nr) AS (
    SELECT MAX(path_id), MAX(nr)
    FROM stop_area_paths
  )
  SELECT *
  FROM stop_area_paths
  UNION ALL
    SELECT relation_id,
           -- increase path ids
           max_path_id + path_id + 1,
           -- swap start/end nodes
           sap.node_2, sap.node_1,
           -- inverse edge order and increase nr
           max_nr + row_number() OVER( ORDER BY nr DESC )
    FROM stop_area_paths sap, max_ids
);


/*
 * This aggregate function combines all osm element tags that form a path link.
 * TODO: Currently this only merges the tags together.
 */
CREATE OR REPLACE AGGREGATE jsonb_merge_agg(jsonb) (
  SFUNC = 'jsonb_concat',
  STYPE = jsonb,
  INITCOND = '{}'
);


/*
 * Aggregates all path segments from stop_area_paths to a single path
 * Aggregate all element ids and types into an MD5 hash to get a deterministic and somewhat unique id
 * Get start and end point id of the path
 * Aggregate all tags of the path into one tag map
 * Create path geometry from all edge geometries
 */
CREATE OR REPLACE TEMPORARY VIEW stop_area_paths_agg AS (
  SELECT relation_id,
    md5( STRING_AGG(osm_type || osm_id, '_' ORDER BY path_id, nr) ) AS path_id,
    first(node_1), last(node_2),
    jsonb_merge_agg(tags) AS tags,
    ST_LineMerge( ST_Union(geom) ) AS geom
  FROM
  -- use nested select because we first need to order them correctly before grouping
  (
    SELECT sap.relation_id, path_id, node_1, node_2, nr, osm_type, osm_id, tags, ed.geom
    FROM stop_area_paths_bidirectional sap
    -- join edge table to get geometries and edge ids
    JOIN ways_topo.edge_data AS ed
      ON (ed.start_node = sap.node_1 AND ed.end_node = sap.node_2)
      OR (ed.start_node = sap.node_2 AND ed.end_node = sap.node_1)
    JOIN ways_topo.relation rel
      ON rel.element_id = ed.edge_id AND rel.element_type = 2
    JOIN stop_ways ele
      ON rel.topogeo_id = (ele.topo_geom).id
    ORDER BY path_id, sap.nr
  ) t
  GROUP BY path_id, relation_id
);


/*
 * Contains all path links by relation id.
 * This only joins the start and ende DHIDs to the table.
 */
CREATE OR REPLACE TEMPORARY VIEW final_site_path_links AS (
  -- include relation id to prevent collisions
  -- include from & to DHID in order to prevent collisions between identical paths (normal and inverted)
  -- that only consist of one way/edge, because they have the same path id
  -- md5 is required to make the id NeTEx compliant
  SELECT paths.relation_id,
         concat_ws('_', paths.relation_id, md5(tnoe1."IFOPT" || tnoe2."IFOPT"), path_id) AS id,
         paths.tags, paths.geom,
         tnoe1."IFOPT" AS "from", tnoe2."IFOPT" AS "to"
  FROM stop_area_paths_agg paths
  JOIN topology_node_to_osm_element tnoe1
    ON tnoe1.node_id = paths.first
  JOIN topology_node_to_osm_element tnoe2
    ON tnoe2.node_id = paths.last
);


/**********************
 * STOP PLACES EXPORT *
 **********************/

DROP TYPE IF EXISTS category CASCADE;
CREATE TYPE category AS ENUM ('QUAY', 'ENTRANCE', 'PARKING', 'ACCESS_SPACE', 'SITE_PATH_LINK');

-- Build final export data table
-- Join all stops to their stop areas
-- Pre joining tables is way faster than using nested selects later, even though it contains duplicated data
CREATE OR REPLACE TEMPORARY VIEW export_data AS (
  SELECT
    pta."IFOPT" AS area_id, pta.tags AS area_tags, pta.geom AS area_geom, pta.operator_id, pta.network_id,
    stop_elements.*
  FROM (
    SELECT
      'QUAY'::category AS category, relation_id,
      qua."IFOPT" AS "id", qua.tags AS tags, qua.geom AS geom, NULL AS "from", NULL AS "to"
    FROM final_quays qua
    -- Append all Entrances to the table
    UNION ALL
      SELECT
        'ENTRANCE'::category AS category, relation_id,
        ent."IFOPT" AS "id", ent.tags AS tags, ent.geom AS geom, NULL AS "from", NULL AS "to"
      FROM final_entrances ent
    -- Append all AccessSpaces to the table
    UNION ALL
      SELECT
        'ACCESS_SPACE'::category AS category, relation_id,
        acc."IFOPT" AS "id", acc.tags AS tags, acc.geom AS geom, NULL AS "from", NULL AS "to"
      FROM final_access_spaces acc
    -- Append all Parking Spaces to the table
    UNION ALL
      SELECT
        'PARKING'::category AS category, relation_id,
        par."IFOPT" AS "id", par.tags AS tags, par.geom AS geom, NULL AS "from", NULL AS "to"
      FROM final_parkings par
    -- Append all Path Links to the table
    UNION ALL
      SELECT
        'SITE_PATH_LINK'::category AS category, relation_id,
        pat.id AS "id", pat.tags AS tags, pat.geom AS geom, pat.from AS "from", pat.to AS "to"
      FROM final_site_path_links pat
  ) stop_elements
  INNER JOIN final_stop_places pta
    ON stop_elements.relation_id = pta.relation_id
  ORDER BY pta.relation_id
);

-- Final export to XML

CREATE OR REPLACE TEMPORARY VIEW xml_stopPlaces AS (
  SELECT
  -- <StopPlace>
  xmlelement(name "StopPlace", xmlattributes(ex.area_id AS "id", 'any' AS "version"),
    -- <keyList>
    ex_keyList(ex.area_tags),
    -- <Name>
    ex_Name(ex.area_tags),
    -- <ShortName>
    ex_ShortName(ex.area_tags),
    -- <alternativeNames>
    ex_alternativeNames(ex.area_tags),
    -- <Description>
    ex_Description(ex.area_tags),
    -- <Centroid>
    ex_Centroid(area_geom),
    -- <AuthorityRef>
    ex_AuthorityRef(ex.network_id),
    xmlagg(ex.xml_children)
  )
  FROM (
    SELECT ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id,
    CASE
      -- <quays>
      WHEN ex.category = 'QUAY' THEN xmlelement(name "quays", (
        xmlagg(
          -- <Quay>
          xmlelement(name "Quay", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Name>
            ex_Name(ex.tags),
            -- <ShortName>
            ex_ShortName(ex.tags),
            -- <Centroid>
            ex_Centroid(ex.geom),
            -- <QuayType>
            ex_QuayType(ex.tags, ex.geom)
          )
        )
      ))
      -- <entrances>
      WHEN ex.category = 'ENTRANCE' THEN xmlelement(name "entrances", (
        xmlagg(
          -- <Entrance>
          xmlelement(name "Entrance", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Name>
            ex_Name(ex.tags),
            -- <Centroid>
            ex_Centroid(ex.geom),
            -- <EntranceType>
            ex_EntranceType(ex.tags)
          )
        )
      ))
      WHEN ex.category = 'ACCESS_SPACE' THEN xmlelement(name "accessSpaces", (
        xmlagg(
          -- <Parking>
          xmlelement(name "AccessSpace", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Name>
            ex_Name(ex.tags),
            -- <Centroid>
            ex_Centroid(ex.geom),
            -- <AccessSpaceType>
            ex_AccessSpaceType(ex.tags)
          )
        )
      ))
      -- <parkings>
      WHEN ex.category = 'PARKING' THEN xmlelement(name "parkings", (
        xmlagg(
          -- <Parking>
          xmlelement(name "Parking", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Name>
            ex_Name(ex.tags),
            -- <Centroid>
            ex_Centroid(ex.geom),
            -- <ParkingType>
            ex_ParkingType(ex.tags),
            -- <ParkingLayout>
            ex_ParkingLayout(ex.tags),
            -- <TotalCapacity>
            ex_TotalCapacity(ex.tags)
          )
        )
      ))
      WHEN ex.category = 'SITE_PATH_LINK' THEN xmlelement(name "pathLinks", (
        xmlagg(
          -- <SitePathLink>
          xmlelement(name "SitePathLink", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Distance>
            ex_Distance(ex.geom),
            -- <LineString>
            ex_LineString(ex.geom, ex.id),
            -- <From> <To>
            ex_FromTo(ex.from, ex.to)
          )
        )
      ))
    END AS xml_children
    FROM export_data ex
    GROUP BY ex.category, ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id
  ) AS ex
  GROUP BY ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id
);
