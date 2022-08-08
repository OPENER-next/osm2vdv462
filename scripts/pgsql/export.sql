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
 * Create a centroid element from any geometry
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_Centroid(a geometry) RETURNS xml AS
$$
SELECT xmlelement(name "Centroid",
  xmlelement(name "Location",
    xmlelement(name "Longitude", ST_X(ST_Transform(ST_Centroid($1), 4326))),
    xmlelement(name "Latitude", ST_Y(ST_Transform(ST_Centroid($1), 4326)))
  )
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a LineString element from a line string geometry
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_LineString(a geometry) RETURNS xml AS
$$
-- see https://postgis.net/docs/ST_AsGML.html
SELECT xml( ST_AsGML(3, $1, 15, 22, '') );
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a Distance element from a line string
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_Distance(a geometry) RETURNS xml AS
$$
SELECT xmlelement(name "Distance", ST_Length($1))
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Creates the From and To element based on given ids and version
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION ex_FromTo(a text, b text, c int) RETURNS xml AS
$$
SELECT xmlconcat(
  xmlelement(name "From",
    xmlelement(name "PlaceRef", xmlattributes($1 AS "ref", $3 AS "version"))
  ),
  xmlelement(name "To",
    xmlelement(name "PlaceRef", xmlattributes($2 AS "ref", $3 AS "version"))
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
 * Note: this function also takes the geometry of the object to distinguish between a tramPlatform and tramStop
 * Unused types: "airlineGate" | "busBay" | "boatQuay" | "ferryLanding" | "telecabinePlatform" | "taxiStand" | "setDownPlace" | "vehicleLoadingPlace"
 * If no match is found this will always return NULL
 */
CREATE OR REPLACE FUNCTION ex_QuayType(tags jsonb, geom geometry) RETURNS xml AS
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
  result := COALESCE(tags->>'name', tags->>'name:de', tags->>'official_name', tags->>'description');

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


/****************
 * PATH FINDING *
 ****************/

/*
 * This function finds all paths between a given list of target nodes.
 * Returns a table of arrays, while each array is a list of node ids.
 */
CREATE OR REPLACE FUNCTION get_paths_connecting_nodes(target_nodes INT[]) RETURNS TABLE (nodes_path INT[]) AS
$$
DECLARE
    -- holds all target nodes that haven't been used as a starting point yet
    unvisited_target_nodes INT[];

    current_node INT;

    touching_nodes INT[];

    nodes_path INT[];
BEGIN
    unvisited_target_nodes := target_nodes;
    -- Loop as long as we have at least two unvisited target nodes
    -- Because when we are at the last node we already found all ways to this node
    -- From the previous searches of the other nodes
    WHILE array_length(unvisited_target_nodes, 1) > 1 LOOP
      -- init nodes path with current target node
      nodes_path := ARRAY[ unvisited_target_nodes[1] ];
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
        -- check whether the current node is any of the unvisited target nodes
        IF current_node = ANY(unvisited_target_nodes) THEN
          -- return current edge path (note that it is inversed)
          RETURN QUERY SELECT nodes_path;
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


/***************
 * STOP_PLACES *
 ***************/

/*
 * Create view that contains all stop areas with a geometry column derived from their members
 *
 * Aggregate member stop geometries to stop areas
 * Split JOINs because GROUP BY doesn't allow grouping by all columns of a specific table
 */
CREATE OR REPLACE VIEW stop_areas_with_geom AS (
  WITH
    stops_clustered_by_relation_id AS (
      SELECT ptr.relation_id, ST_Collect(geom) AS geom
      FROM stop_areas_members_ref ptr
      INNER JOIN platforms pts
        ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
      GROUP BY ptr.relation_id
    )
  SELECT pta.*, geom
  FROM stop_areas pta
  INNER JOIN stops_clustered_by_relation_id sc
    ON pta.relation_id = sc.relation_id
);


/*
 * Create view that contains all stop areas with hull enclosing all stops.
 * The hull is padded by 100 meters
 */
CREATE OR REPLACE VIEW stop_areas_with_padded_hull AS (
  SELECT
    relation_id,
    -- Expand the hull geometry
    ST_Buffer(
      -- Create a single hull geometry based on the collection
      ST_ConvexHull(geom),
      100
    ) AS geom
  FROM stop_areas_with_geom
);


/*********
 * QUAYS *
 *********/

/*
 * Create view that matches all platforms/quays to public transport areas by the reference table.
 */
CREATE OR REPLACE VIEW final_quays AS (
  SELECT ptr.relation_id, pts.*
  FROM stop_areas_members_ref ptr
  INNER JOIN platforms pts
    ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
);


/*************
 * ENTRANCES *
 *************/

/*
 * Create view that matches all entrances geographically to public transport areas.
 * This uses the padded hull of stop areas and matches/joins every entrance that is contained.
 */
CREATE OR REPLACE VIEW final_entrances AS (
  SELECT pta.relation_id, entrances.*
  FROM entrances
  JOIN stop_areas_with_padded_hull AS pta
    ON ST_Covers(pta.geom, entrances.geom)
);


/*****************
 * ACCESS_SPACES *
 *****************/

/*
 * Create view that matches all access spaces geographically to public transport areas.
 * This uses the padded hull of stop areas and matches/joins every access space that intersects it.
 */
CREATE OR REPLACE VIEW final_access_spaces AS (
  SELECT pta.relation_id, access_spaces.*
  FROM access_spaces
  JOIN stop_areas_with_padded_hull AS pta
    ON ST_Intersects(pta.geom, access_spaces.geom)
);


/************
 * PARKINGS *
 ************/

/*
 * Create view that matches all parking spaces geographically to public transport areas.
 * This uses the padded hull of stop areas and matches/joins every parking space that intersects it.
 */
CREATE OR REPLACE VIEW final_parkings AS (
  SELECT pta.relation_id, parking.*
  FROM parking
  JOIN stop_areas_with_padded_hull AS pta
    ON ST_Intersects(parking.geom, pta.geom)
);


/**********
 * EXPORT *
 **********/

DROP TYPE IF EXISTS category CASCADE;
CREATE TYPE category AS ENUM ('QUAY', 'ENTRANCE', 'PARKING', 'ACCESS_SPACE', 'PATH_LINK');

-- Build final export data table
-- Join all stops to their stop areas
-- Pre joining tables is way faster than using nested selects later, even though it contains duplicated data
CREATE OR REPLACE VIEW export_data AS (
  SELECT
    'QUAY'::category AS category,
    pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom, pta.version AS area_version,
    qua."IFOPT" AS "IFOPT", qua.tags AS tags, qua.geom AS geom, qua.version AS version
  FROM final_quays qua
  INNER JOIN stop_areas_with_geom pta
    ON qua.relation_id = pta.relation_id
  -- Append all Entrances to the table
  UNION ALL
    SELECT
      'ENTRANCE'::category AS category,
      pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom, pta.version AS area_version,
      ent."IFOPT" AS "IFOPT", ent.tags AS tags, ent.geom AS geom, ent.version AS version
    FROM final_entrances ent
    INNER JOIN stop_areas_with_geom pta
      ON ent.relation_id = pta.relation_id
  -- Append all AccessSpaces to the table
  UNION ALL
    SELECT
      'ACCESS_SPACE'::category AS category,
      pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom, pta.version AS area_version,
      acc."IFOPT" AS "IFOPT", acc.tags AS tags, acc.geom AS geom, acc.version AS version
    FROM final_access_spaces acc
    INNER JOIN stop_areas_with_geom pta
      ON acc.relation_id = pta.relation_id
  -- Append all Parking Spaces to the table
  UNION ALL
    SELECT
      'PARKING'::category AS category,
      pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom, pta.version AS area_version,
      par."IFOPT" AS "IFOPT", par.tags AS tags, par.geom AS geom, par.version AS version
    FROM final_parkings par
    INNER JOIN stop_areas_with_geom pta
      ON par.relation_id = pta.relation_id
  ORDER BY relation_id
);

-- Final export to XML

SELECT
-- <StopPlace>
xmlelement(name "StopPlace", xmlattributes(ex.area_dhid AS "id", ex.area_version AS "version"),
  -- <Name>
  xmlelement(name "Name", ex.area_name),
  -- <ShortName>
  ex_ShortName(ex.area_tags),
  -- <alternativeNames>
  ex_alternativeNames(ex.area_tags),
  -- <Description>
  ex_Description(ex.area_tags),
  -- <Centroid>
  ex_Centroid(area_geom),
  -- <keyList>
  ex_keyList(
    ex.area_tags,
    create_KeyValue('GlobalID', ex.area_dhid)
  ),
  xmlagg(ex.xml_children)
)
FROM (
  SELECT ex.relation_id, ex.area_dhid, ex.area_name, ex.area_tags, ex.area_geom, ex.area_version,
  CASE
    -- <quays>
    WHEN ex.category = 'QUAY' THEN xmlelement(name "quays", (
      xmlagg(
        -- <Quay>
        xmlelement(name "Quay", xmlattributes(ex."IFOPT" AS "id", ex.version AS "version"),
          -- <Name>
          ex_Name(ex.tags),
          -- <ShortName>
          ex_ShortName(ex.tags),
          -- <Centroid>
          ex_Centroid(ex.geom),
          -- <QuayType>
          ex_QuayType(ex.tags, ex.geom),
          -- <keyList>
          ex_keyList(
            ex.tags,
            create_KeyValue('GlobalID', ex.tags ->> 'ref:IFOPT')
          )
        )
      )
    ))
    -- <entrances>
    WHEN ex.category = 'ENTRANCE' THEN xmlelement(name "entrances", (
      xmlagg(
        -- <Entrance>
        xmlelement(name "Entrance", xmlattributes(ex."IFOPT" AS "id", ex.version AS "version"),
          -- <Name>
          ex_Name(ex.tags),
          -- <Centroid>
          ex_Centroid(ex.geom),
          -- <EntranceType>
          ex_EntranceType(ex.tags),
          -- <keyList>
          ex_keyList(
            ex.tags
          )
        )
      )
    ))
    WHEN ex.category = 'ACCESS_SPACE' THEN xmlelement(name "accessSpaces", (
      xmlagg(
        -- <Parking>
        xmlelement(name "AccessSpace", xmlattributes(ex."IFOPT" AS "id", ex.version AS "version"),
          -- <Name>
          ex_Name(ex.tags),
          -- <Centroid>
          ex_Centroid(ex.geom),
          -- <AccessSpaceType>
          ex_AccessSpaceType(ex.tags),
          -- <keyList>
          ex_keyList(
            ex.tags
          )
        )
      )
    ))
    -- <parkings>
    WHEN ex.category = 'PARKING' THEN xmlelement(name "parkings", (
      xmlagg(
        -- <Parking>
        xmlelement(name "Parking", xmlattributes(ex."IFOPT" AS "id", ex.version AS "version"),
          -- <Name>
          ex_Name(ex.tags),
          -- <Centroid>
          ex_Centroid(ex.geom),
          -- <ParkingType>
          ex_ParkingType(ex.tags),
          -- <ParkingLayout>
          ex_ParkingLayout(ex.tags),
          -- <TotalCapacity>
          ex_TotalCapacity(ex.tags),
          -- <keyList>
          ex_keyList(
            ex.tags
          )
        )
      )
    ))
    WHEN ex.category = 'PATH_LINK' THEN xmlelement(name "pathLinks", (
      xmlagg(
        -- ....
        xmlelement(name "Dummy")
      )
    ))
  END AS xml_children
  FROM export_data ex
  GROUP BY ex.relation_id, ex.area_dhid, ex.area_name, ex.area_tags, ex.area_geom, ex.area_version, ex.category
) AS ex
GROUP BY ex.relation_id, ex.area_dhid, ex.area_name, ex.area_tags, ex.area_geom, ex.area_version
