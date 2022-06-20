/********************
 * EXPORT FUNCTIONS *
 ********************/

/*
 * Create a centroid element from any geometry
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION geom_to_centroid_xml(a geometry) RETURNS xml AS
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
 * Create a single key value pair element
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION create_key_value_xml(a anyelement, b anyelement) RETURNS xml AS
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
  WHEN $2 = 'yes' THEN create_key_value_xml($1, '')
END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a keyList element based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION extract_key_list_xml(tags jsonb, additionalPairs xml) RETURNS xml AS
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
 * Create a StopPlaceType element based on the tags: train, subway, coach and bus
 * Unused types: "airport" | "harbourPort" | "ferrytPort" | "ferryStop" | "onStreetBus" | "onStreetTram" | "skiLift"
 * From: https://laidig.github.io/siri-20-java/doc/schemas/ifopt_stop-v0_3_xsd/simpleTypes/StopPlaceTypeEnumeration.html
 * If no match is found this will always return a StopPlaceType of "other"
 */
CREATE OR REPLACE FUNCTION extract_stop_place_type_xml(tags jsonb) RETURNS xml AS
$$
SELECT xmlelement(name "StopPlaceType",
  CASE
    WHEN $1->>'train' = 'yes' THEN 'railStation'
    WHEN $1->>'subway' = 'yes' THEN 'metroStation'
    WHEN $1->>'coach' = 'yes' THEN 'coachStation'
    WHEN $1->>'bus' = 'yes' THEN 'busStation'
    ELSE 'other'
  END
)
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a single Lang Name pair element
 * Returns null when any argument is null
 */
CREATE OR REPLACE FUNCTION create_alternative_name_xml(a text, b text) RETURNS xml AS
$$
SELECT xmlelement(name "AlternativeName",
  xmlelement(name "Lang", $1),
  xmlelement(name "Name", $2)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create an AlternativeName element based on name:LANG_CODE tags
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION extract_alternative_names_xml(tags jsonb) RETURNS xml AS
$$
DECLARE
  result xml;
BEGIN
  result := xmlconcat(
    create_alternative_name_xml('en', tags->>'name:en'),
    create_alternative_name_xml('de', tags->>'name:de'),
    create_alternative_name_xml('fr', tags->>'name:fr'),
    create_alternative_name_xml('cs', tags->>'name:cs'),
    create_alternative_name_xml('pl', tags->>'name:pl'),
    create_alternative_name_xml('da', tags->>'name:da'),
    create_alternative_name_xml('nl', tags->>'name:nl'),
    create_alternative_name_xml('lb', tags->>'name:lb')
  );

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "alternativeNames", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create an ShortName element based on short_name tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION extract_short_name_xml(tags jsonb) RETURNS xml AS
$$
SELECT
  CASE
    WHEN $1->>'short_name' IS NOT NULL THEN xmlelement(
      name "ShortName",
      $1->>'short_name'
    )
    ELSE NULL
  END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a Description element based on description tag
 * Returns null otherwise
 */
CREATE OR REPLACE FUNCTION extract_description_xml(tags jsonb) RETURNS xml AS
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


/***************
 * STOP_PLACES *
 ***************/

/*
 * Create view that contains all stop areas with a geometry column derived from their members
 *
 * Aggregate member stop geometries to stop areas
 * Split JOINs because GROUP BY doesn't allow grouping by all columns of a specific table
 */
CREATE OR REPLACE VIEW public_transport_areas_with_geom AS (
  WITH
    stops_clustered_by_relation_id AS (
      SELECT ptr.relation_id, ST_Collect(geom) AS geom
      FROM public_transport_areas_members_ref ptr
      INNER JOIN public_transport_stops pts
        ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
      GROUP BY ptr.relation_id
    )
  SELECT pta.*, geom
  FROM public_transport_areas pta
  INNER JOIN stops_clustered_by_relation_id sc
    ON pta.relation_id = sc.relation_id
);


/*
 * Create view that contains all stop areas with hull enclosing all stops.
 * The hull is padded by 100 meters
 */
CREATE OR REPLACE VIEW public_transport_areas_with_padded_hull AS (
  SELECT
    relation_id,
    -- Expand the hull geometry
    ST_Buffer(
      -- Create a single hull geometry based on the collection
      ST_ConvexHull(geom),
      100
    ) AS geom
  FROM public_transport_areas_with_geom
);


/*********
 * QUAYS *
 *********/

/*
 * All quays.
 */
CREATE OR REPLACE VIEW final_quays AS (
  SELECT ptr.relation_id, pts.*
  FROM public_transport_areas_members_ref ptr
  INNER JOIN public_transport_stops pts
    ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type
);


/*************
 * ENTRANCES *
 *************/

/*
 * Create view that matches all entrances to public transport areas.
 * This uses the padded hull of stop areas and matches/joins every entrance that is contained.
 */
CREATE OR REPLACE VIEW entrances_to_public_transport_areas AS (
  SELECT pta.relation_id, entrances.*
  FROM entrances
  JOIN public_transport_areas_with_padded_hull AS pta
  ON ST_Intersects(pta.geom, entrances.geom)
);


/*
 * Create view that returns all entrances of train stations.
 * This returns all entrances from the entrance table that lie on the border of OR inside a train station building.
 */
CREATE OR REPLACE VIEW entrances_of_train_stations AS (
  SELECT ts.tags -> 'name' AS train_station_name, ent.*
  FROM train_stations ts
  JOIN entrances_to_public_transport_areas AS ent
  ON ST_Covers(ts.geom, ent.geom)
);


/*
 * Add all railway entrances to all entrances that are part of a train station
 * This view will contain all entrances that are relevant for public transport
 */
CREATE OR REPLACE VIEW final_entrances AS (
  SELECT *
  FROM entrances_of_train_stations
  UNION
    SELECT NULL AS "name", *
    FROM entrances_to_public_transport_areas ent
    WHERE ent.tags -> 'railway' IS NOT NULL
);


/*****************
 * ACCESS_SPACES *
 *****************/


/******************
 * PARKING_SPACES *
 ******************/

/*
 * Create view that matches all parking spaces to public transport areas.
 * This uses the padded hull of stop areas and matches/joins every parking space that intersects it.
 */
CREATE OR REPLACE VIEW parking_spaces_to_public_transport_areas AS (
  SELECT pta.relation_id, parking.*
  FROM parking
  JOIN public_transport_areas_with_padded_hull AS pta
  ON ST_Intersects(parking.geom, pta.geom)
);

/*
 * All relevant parking spaces.
 */
CREATE OR REPLACE VIEW final_parking_spaces AS (
  SELECT * FROM parking_spaces_to_public_transport_areas
);


/**********
 * EXPORT *
 **********/

DROP TYPE IF EXISTS category CASCADE;
CREATE TYPE category AS ENUM ('QUAY', 'ENTRANCE', 'PARKING_SPACE');

-- Build final export data table
-- Join all stops to their stop areas
-- Pre joining tables is way faster than using nested selects later, even though it contains duplicated data
CREATE OR REPLACE VIEW export_data AS (
  SELECT
    'QUAY'::category AS category,
    pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom,
    qua.tags AS tags, qua.geom AS geom
  FROM final_quays qua
  INNER JOIN public_transport_areas_with_geom pta
    ON qua.relation_id = pta.relation_id
  -- Append all Parking Spaces to the table
  UNION ALL
    SELECT
    'PARKING_SPACE'::category AS category,
    pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom,
    par.tags AS tags, par.geom AS geom
    FROM final_parking_spaces par
    INNER JOIN public_transport_areas_with_geom pta
      ON par.relation_id = pta.relation_id
  -- Append all Entrances to the table
  UNION ALL
    SELECT
    'ENTRANCE'::category AS category,
    pta.relation_id, pta.name AS area_name, pta."ref:IFOPT" AS area_dhid, pta.tags AS area_tags, pta.geom AS area_geom,
    ent.tags AS tags, ent.geom AS geom
    FROM final_entrances ent
    INNER JOIN public_transport_areas_with_geom pta
      ON ent.relation_id = pta.relation_id
  ORDER BY relation_id
);

-- Final export to XML

SELECT
-- <StopPlace>
xmlelement(name "StopPlace", xmlattributes(ex.area_dhid as id),
  -- <Name>
  xmlelement(name "Name", ex.area_name),
  -- <ShortName>
  extract_short_name_xml(ex.area_tags),
  -- <AlternativeName>
  extract_alternative_names_xml(ex.area_tags),
  -- <Description>
  extract_description_xml(ex.area_tags),
  -- <StopPlaceType>
  extract_stop_place_type_xml(ex.area_tags),
  -- <Centroid>
  geom_to_centroid_xml(area_geom),
  -- <keyList>
  extract_key_list_xml(
    ex.area_tags,
    create_key_value_xml('GlobalID', ex.area_dhid)
  ),
  CASE
    -- <quays>
    WHEN TRUE THEN xmlelement(name "quays", (
      xmlagg(
        -- <Quay>
        xmlelement(name "Quay", ex.stop_dhid,
          -- <Name>
          xmlelement(name "Name", ex.stop_name),
          -- <ShortName>
          extract_short_name_xml(ex.area_tags),
          -- <AlternativeName>
          extract_alternative_names_xml(ex.stop_tags),
          -- <Centroid>
          geom_to_centroid_xml(ex.stop_geom),
          -- <keyList>
          extract_key_list_xml(
            ex.stop_tags,
            create_key_value_xml('GlobalID', ex.stop_dhid)
          )
        )
      )
    ))
    WHEN FALSE THEN xmlelement(name "accessSpaces", (
      xmlagg(
        -- ....
        xmlelement(name "Dummy")
      )
    ))
    WHEN FALSE THEN xmlelement(name "pathLinks", (
      xmlagg(
        -- ....
        xmlelement(name "Dummy")
      )
    ))
  END
)
FROM export_data ex
-- area_dhid and area_name will be identical for the same relation_id since they are just duplicates from previous joins
GROUP BY ex.relation_id, ex.area_dhid, ex.area_name, ex.area_tags, ex.area_geom
