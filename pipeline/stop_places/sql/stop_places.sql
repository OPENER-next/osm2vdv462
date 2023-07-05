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
    IF ST_GeometryType(geom::geometry) = 'ST_Point'
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
 * Get the numeric level from given tags.
 * Returns 0 if no level could be parsed.
 */
CREATE OR REPLACE FUNCTION get_Level(tags JSONB) RETURNS NUMERIC AS
$$
BEGIN
  IF tags->>'level' IS NULL
  THEN
    RETURN 0.0;
  ELSE
    BEGIN
      RETURN SPLIT_PART($1->>'level', ';', 1)::NUMERIC(4,1);
    EXCEPTION WHEN OTHERS THEN
      RETURN 0.0;
    END;
  END IF;
END;
$$ LANGUAGE plpgsql;


/*
 * Create a unique level id that depends on the stop area relation id and the level.
 * Returns null if no id or level is provided
 */
CREATE OR REPLACE FUNCTION create_LevelId(id BIGINT, "level" NUMERIC) RETURNS TEXT AS
$$
  SELECT id || ':' || "level"
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a LevelRef element based on the given id.
 * Returns null if no id or level is provided
 */
CREATE OR REPLACE FUNCTION ex_LevelRef(id BIGINT, "level" NUMERIC) RETURNS xml AS
$$
  SELECT xmlelement(
    name "LevelRef",
    xmlattributes(create_LevelId($1, $2) AS "ref", 'any' AS "version")
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


/*********
 * QUAYS *
 *********/

/*
 * Create view that matches all platforms/quays to public transport areas by the reference table.
 */
CREATE OR REPLACE VIEW final_quays AS (
  SELECT ptr.relation_id, pts.*, get_Level(pts.tags) AS "level"
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
CREATE OR REPLACE VIEW final_entrances AS (
  SELECT ptr.relation_id, ent.*, get_Level(ent.tags) AS "level"
  FROM entrances ent
  JOIN stop_areas_members_ref ptr
    ON ent.node_id = ptr.member_id AND ptr.osm_type = 'N'
);


/*****************
 * ACCESS_SPACES *
 *****************/

/*
 * Create view that matches all access spaces to public transport areas
 */
CREATE OR REPLACE VIEW final_access_spaces AS (
  SELECT *
  FROM access_spaces
);


/************
 * PARKINGS *
 ************/

/*
 * Create view that matches all parking spaces to public transport areas by the reference table.
 */
CREATE OR REPLACE VIEW final_parkings AS (
  SELECT ptr.relation_id, par.*, get_Level(par.tags) AS "level"
  FROM parking par
  JOIN stop_areas_members_ref ptr
    ON par.osm_id = ptr.member_id AND par.osm_type = ptr.osm_type
);


/**************
 * PATH LINKS *
 **************/

/*
 * Mapping of stop places to elements
 * Create view that matches all elements to corresponding public transport areas.
 * This table is used in the "routing" step of the pipeline.
 */
CREATE OR REPLACE VIEW stop_area_elements AS (
  SELECT
    stop_elements.*
  FROM (
    SELECT
      relation_id AS stop_area_osm_id, 'QUAY'::category AS category,
      qua."IFOPT" AS "id",  ST_Centroid(qua.geom) AS geom
    FROM final_quays qua
    -- Append all Entrances to the table
    UNION ALL
      SELECT
        relation_id AS stop_area_osm_id, 'ENTRANCE'::category AS category,
        ent."IFOPT" AS "id", ST_Centroid(ent.geom) AS geom
      FROM final_entrances ent
    -- Append all Parking Spaces to the table
    UNION ALL
      SELECT
        relation_id AS stop_area_osm_id, 'PARKING'::category AS category,
        par."IFOPT" AS "id", ST_Centroid(par.geom) AS geom
      FROM final_parkings par
  ) stop_elements
  INNER JOIN stop_areas pta
    ON stop_elements.stop_area_osm_id = pta.relation_id
  ORDER BY pta.relation_id
);


/*
 * Final site path link view
 * Currently this is just a wrapper of the "path_links" table.
 * TODO: JOIN "path_links" with "paths_elements_ref" and "highways" GROUP BY "path_id" and somehow aggregate tags
 */
CREATE OR REPLACE VIEW final_site_path_links AS (
  SELECT stop_area_relation_id AS relation_id, path_id::text as id, '{}'::jsonb AS tags, geom, smaller_node_id as "from", bigger_node_id as "to"
  FROM path_links
);


/***************
 * STOP_PLACES *
 ***************/

/*
 * Create view that contains all stop areas with the wikidata id of their respective operator and network.
 * Ids will be NULL if no matching operator/network can be found.
 */
CREATE OR REPLACE VIEW stop_places_with_organisations AS (
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
CREATE OR REPLACE VIEW stop_places_with_geometry AS (
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
 * This view groups all relevant elements of a stop place by their level column
 * The levels are directly written into a json map that looks like this: {-1: A, 0: B, 1: C, 2: null}
 * One could also create a Row per level and then later export them similar to Quays or PathLinks.
 * However they don't really fit into the "Element" category like Quays, Entrances, PathLinks etc.
 */
CREATE OR REPLACE VIEW final_stop_places AS (
  SELECT
    pta.*,
    -- jsonb (not json) is important to remove duplicated keys
    jsonb_object_agg(
      stop_elements.level,
      stop_elements.tags->'level:ref'
    ) AS levels
  FROM (
    SELECT
      relation_id, "level", tags
    FROM final_quays qua
    -- Append all Entrances to the table
    UNION ALL
      SELECT
        relation_id, "level", tags
      FROM final_entrances ent
    -- Append all Parking Spaces to the table
    UNION ALL
      SELECT
        relation_id, "level", tags
      FROM final_parkings par
    -- Append all AccessSpaces to the table
    UNION ALL
      SELECT
        relation_id, "level", tags
      FROM final_access_spaces acc
  ) stop_elements
  INNER JOIN stop_places_with_geometry pta
    ON stop_elements.relation_id = pta.relation_id
  GROUP BY pta.relation_id, pta."IFOPT", pta.tags, pta.geom, pta.operator_id, pta.network_id
);


/**********************
 * STOP PLACES EXPORT *
 **********************/

-- Build final export data table
-- Join all stops to their stop areas
-- Pre joining tables is way faster than using nested selects later, even though it contains duplicated data
CREATE OR REPLACE VIEW export_data AS (
  SELECT
    pta."IFOPT" AS area_id, pta.tags AS area_tags, pta.geom AS area_geom, pta.operator_id, pta.network_id, pta.levels,
    stop_elements.*
  FROM (
    SELECT
      'QUAY'::category AS category, relation_id,
      qua."IFOPT" AS "id", qua.tags AS tags, qua.geom AS geom, qua."level" AS "level", NULL AS "from", NULL AS "to"
    FROM final_quays qua
    -- Append all Entrances to the table
    UNION ALL
      SELECT
        'ENTRANCE'::category AS category, relation_id,
        ent."IFOPT" AS "id", ent.tags AS tags, ent.geom AS geom, ent."level" AS "level", NULL AS "from", NULL AS "to"
      FROM final_entrances ent
    -- Append all AccessSpaces to the table
    UNION ALL
      SELECT
        'ACCESS_SPACE'::category AS category, relation_id,
        acc."IFOPT" AS "id", acc.tags AS tags, acc.geom AS geom, acc."level" AS "level", NULL AS "from", NULL AS "to"
      FROM final_access_spaces acc
    -- Append all Parking Spaces to the table
    UNION ALL
      SELECT
        'PARKING'::category AS category, relation_id,
        par."IFOPT" AS "id", par.tags AS tags, par.geom AS geom, par."level" AS "level", NULL AS "from", NULL AS "to"
      FROM final_parkings par
    -- Append all Path Links to the table
    UNION ALL
      SELECT
        'SITE_PATH_LINK'::category AS category, relation_id,
        pat.id AS "id", pat.tags AS tags, pat.geom AS geom, NULL AS "level", pat.from AS "from", pat.to AS "to"
      FROM final_site_path_links pat
  ) stop_elements
  INNER JOIN final_stop_places pta
    ON stop_elements.relation_id = pta.relation_id
  ORDER BY pta.relation_id
);

-- Final export to XML

CREATE OR REPLACE VIEW xml_stopPlaces AS (
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
    -- <levels>
    xmlelement(name "levels", (
      SELECT xmlagg(
        -- <Level>
        xmlelement(name "Level",
          xmlattributes(create_LevelId(ex.relation_id, key::NUMERIC) AS "id", 'any' AS "version"),
          -- <ShortName>
          xmlelement(name "ShortName", COALESCE(value, key))
        )
      )
      FROM jsonb_each_text(ex.levels)
    )),
    xmlagg(ex.xml_children)
  )
  FROM (
    SELECT ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels,
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
            -- <LevelRef>
            ex_LevelRef(ex.relation_id, ex.level),
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
            -- <LevelRef>
            ex_LevelRef(ex.relation_id, ex.level),
            -- <EntranceType>
            ex_EntranceType(ex.tags)
          )
        )
      ))
      -- <accessSpaces>
      WHEN ex.category = 'ACCESS_SPACE' THEN xmlelement(name "accessSpaces", (
        xmlagg(
          -- <AccessSpace>
          xmlelement(name "AccessSpace", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList(ex.tags),
            -- <Name>
            ex_Name(ex.tags),
            -- <Centroid>
            ex_Centroid(ex.geom),
            -- <LevelRef>
            ex_LevelRef(ex.relation_id, ex.level),
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
            -- <LevelRef>
            ex_LevelRef(ex.relation_id, ex.level),
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
    GROUP BY ex.category, ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels
    -- important for NeTEx validity, Quays should come first while the SitePathLinks should be the last
    ORDER BY ex.category ASC
  ) AS ex
  GROUP BY ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels
);
