/********************
 * EXPORT FUNCTIONS *
 ********************/

/*
 * Return the distance of a given geometry in meters, rounded to 6 decimal places
 */
CREATE OR REPLACE FUNCTION calculate_Distance(geo geometry) RETURNS real AS
$$
SELECT ST_Length(
  ST_Transform($1, current_setting('export.PROJECTION')::INT)::geography
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Convert the input to centimeters
 * Returns null when the conversion fails or the input is null
 */
CREATE OR REPLACE FUNCTION parse_length(value TEXT) RETURNS NUMERIC AS
$$
DECLARE
  value_split TEXT[];
BEGIN
  -- split the input string into an array if it contains a space
  value_split := string_to_array(value, ' ');
  -- try casting/parsing to NUMERIC and catch in case of failure
  BEGIN
    -- check, if the unit is 'm', or has no unit defined
    IF value_split[2] = 'm' OR value_split[2] IS NULL THEN
      RETURN value_split[1]::NUMERIC * 100;
    ELSEIF value_split[2] = 'cm' THEN
      RETURN value_split[1]::NUMERIC;
    ELSE
      RAISE NOTICE 'Unknown length unit detected: "%".  Returning NULL.', value;
      RETURN NULL;
    END IF;
  -- catch casting exceptions
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid length value: "%".  Returning NULL.', value;
    RETURN NULL;
  END;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a function, that converts a duration string to the xsd:duration format.
 * The output format is globally set to iso_8601 in the setup pipeline step.
 * Returns null when no duration can be parsed
 */
CREATE OR REPLACE FUNCTION parse_duration(duration text) RETURNS INTERVAL AS
$$
BEGIN
  -- check if the duration text only consists of numbers --> special case for minutes
  IF duration ~ '^[0-9]+$' THEN
    RETURN (duration || ' minutes')::INTERVAL;
  ELSE
    BEGIN
      RETURN duration::INTERVAL;
    EXCEPTION
      WHEN invalid_datetime_format THEN
        -- conversion failed
        RETURN NULL;
    END;
  END IF;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Convert the input to kilograms
 * Returns null when the conversion fails or the input is null
 */
CREATE OR REPLACE FUNCTION parse_weight(value text) RETURNS NUMERIC AS
$$
DECLARE
  value_split TEXT[];
BEGIN
  -- split the input string into an array if it contains a space
  value_split := string_to_array(value, ' ');
  -- try casting/parsing to NUMERIC and catch in case of failure
  BEGIN
    -- check, if the unit is 't', or has no unit defined
    IF value_split[2] = 't' OR value_split[2] IS NULL THEN
      RETURN value_split[1]::NUMERIC * 1000;
    ELSEIF value_split[2] = 'kg' THEN
      RETURN value_split[1]::NUMERIC;
    ELSEIF value_split[2] = 'g' THEN
      RETURN value_split[1]::NUMERIC / 1000;
    ELSE
      RAISE NOTICE 'Unknown weight unit detected: "%".  Returning NULL.', value;
      RETURN NULL;
    END IF;
  -- catch casting exceptions
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid weight value: "%".  Returning NULL.', value;
    RETURN NULL;
  END;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Convert the input to degrees
 * Returns null when the conversion fails or the input is null
 */
CREATE OR REPLACE FUNCTION parse_incline(value text) RETURNS NUMERIC AS
$$
DECLARE
  unit char;
BEGIN
  IF value IN ('up', 'down') THEN
    RETURN NULL;
  END IF;
  -- get the unit of the string
  unit := RIGHT(value, 1);
  -- try casting/parsing to NUMERIC and catch in case of failure
  BEGIN
    IF unit = '%' THEN
      RETURN LEFT(value, -1)::NUMERIC;
    ELSEIF unit = '°' THEN
      RETURN TAN(RADIANS(LEFT(value, -1)::NUMERIC)) * 100;
    ELSE
      RAISE NOTICE 'Unknown incline unit detected: "%".  Returning NULL.', value;
      RETURN NULL;
    END IF;
  -- catch casting exceptions
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Invalid incline value: "%".  Returning NULL.', value;
    RETURN NULL;
  END;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a function, that estimates the duration in seconds based on the length of the path link.
 * Returns the seconds as integer (rounded up to the next integer).
 * Special case elevator: the duration is estimated based on the number of levels that are passed.
 */
CREATE OR REPLACE FUNCTION estimate_duration(tags jsonb, geo geometry, level NUMERIC, walking_speed NUMERIC) RETURNS INTERVAL AS
$$
SELECT
  CASE
    WHEN tags->>'highway' = 'elevator' THEN
      CASE
        WHEN level = 0 THEN make_interval(secs => 60) -- return 60 seconds as a fallback
        ELSE make_interval(secs => 30 + ABS(level) * 10) -- estimation: 10 seconds per level plus 30 seconds for entering and leaving the elevator
      END
    ELSE
      make_interval(secs => (calculate_Distance(geo) / walking_speed))
  END
$$
LANGUAGE SQL IMMUTABLE STRICT;


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
CREATE OR REPLACE FUNCTION ex_Distance(geo geometry) RETURNS xml AS
$$
SELECT xmlelement(name "Distance", calculate_Distance($1))
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
CREATE OR REPLACE FUNCTION create_KeyValue(a text, b anynonarray) RETURNS xml AS
$$
SELECT xmlelement(name "KeyValue",
  xmlelement(name "Key", $1),
  xmlelement(name "Value", $2)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a single key value pair element where the value is empty if the given tag value equals to one of the given values
 * Else returns null
 */
CREATE OR REPLACE FUNCTION delfi_attribute_check_values_xml(delfiid text, val text, VARIADIC vals text[] DEFAULT ARRAY['yes']) RETURNS xml AS
$$
BEGIN
  IF val = ANY (vals) THEN
    RETURN create_KeyValue(delfiid, ''::text);
  END IF;
  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a keyList element based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION create_keyList(keys xml) RETURNS xml AS
$$
SELECT xmlelement(name "keyList", $1);
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a keyList element for stop places based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_StopPlace(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList(xmlconcat(
  $2
));
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a keyList element for quays based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_Quay(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList(xmlconcat(
  additionalPairs,
  -- 1120: waiting area with seat
  delfi_attribute_check_values_xml('1120', tags->>'bench'),
  -- 1140: dynamic visual passenger information display
  delfi_attribute_check_values_xml('1140', tags->>'passenger_information_display'),
  -- 1141: with acoustic output
  delfi_attribute_check_values_xml('1141', tags->>'passenger_information_display:speech_output'),
  -- 1150: automatic announcements
  delfi_attribute_check_values_xml('1150', tags->>'announcement'),
  -- 1170: height difference between the platform and the road respectively the top edge of the rail
  create_KeyValue('1170', parse_length(tags->>'height')),
  -- 1180: platform width
  -- "est_width" is a valid OSM tag, however the view "platforms_with_width" also writes this tag for polygons
  create_KeyValue('1180', parse_length(COALESCE(tags->>'width', tags->>'est_width'))),
  (SELECT CASE
    WHEN tags->>'kerb' IN ('yes', 'raised') AND tags->>'kerb:approach_aid' = 'yes' THEN
      -- 1200: high curb with track guidance
      create_KeyValue('1200', ''::text)
    WHEN tags->>'kerb' IN ('yes', 'raised') THEN
      -- 1202: high curb without track guidance
      create_KeyValue('1202', ''::text)
  END),
  -- 1210: portable ramp exists
  delfi_attribute_check_values_xml('1210', tags->>'ramp:portable'),
  -- 1210: portable ramp total length
  create_KeyValue('1211', parse_length(tags->>'ramp:length')),
  -- 1210: portable ramp weight limit
  create_KeyValue('1212', parse_weight(tags->>'ramp:maxweight')),
  -- 1220: portable platform lift exists
  delfi_attribute_check_values_xml('1220', tags->>'platform_lift'),
  -- 1221: portable platform lift length of the platform lift's usable space
  create_KeyValue('1221', parse_length(tags->>'platform_lift:maxlength:physical')),
  -- 1222: portable platform lift weight limit
  create_KeyValue('1222', parse_weight(tags->>'platform_lift:maxweight')),
  -- 2071: tactile/visual floor indicators in the entrance area with locating strips
  delfi_attribute_check_values_xml('2071', tags->>'tactile_paving', 'yes', 'contrasted')

  -- Missing:
  -- 1190: distance between platform edge and center of track
  -- 1201: high curb with track guidance and double cove
  -- 1203: 'combiboard' with track guidance
  -- 2140: entry in the middle of the road
));
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a keyList element for site path links based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_SitePathLink(tags jsonb, geo geometry, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList(xmlconcat(
  additionalPairs,
  -- 2072: tactile/visual floor indicators as guide strips
  delfi_attribute_check_values_xml('2072', tags->>'tactile_paving', 'yes', 'contrasted'),
  -- NOTE: only ONE of the below cases will return
  (SELECT CASE
    -- elevator:
    WHEN tags->>'highway' = 'elevator' THEN
      xmlconcat(
        -- 2090: lift
        create_KeyValue('2090', ''::text),
        -- 2092: footprint area of the lift
        create_KeyValue(
          '2092',
          -- if one value is null this will evaluate to null
          parse_length(tags->>'length') * parse_length(tags->>'width') / 100
        ),
        -- 2093: footprint length of the lift
        create_KeyValue('2093',  parse_length(tags->>'length')),
        -- 2094: footprint width of the lift
        create_KeyValue('2094',  parse_length(tags->>'width'))
      )
    -- stairs:
    WHEN tags->>'highway' = 'steps' AND tags->>'conveying' IS NULL THEN
      xmlconcat(
        -- 2110: stairs
        create_KeyValue('2110', ''::text),
        -- 2112: step height
        create_KeyValue('2112', parse_length(tags->>'step:height')),
        -- 2113: number of steps
        create_KeyValue('2113', tags->>'step_count')
      )
    -- escalator:
    WHEN tags->>'highway' = 'steps' AND tags->>'conveying' IN ('yes', 'forward', 'backward', 'reversible') THEN
      xmlconcat(
        -- 2130: escalator
        create_KeyValue('2130', ''::text),
        -- 2132: escalator direction
        create_KeyValue('2132', (
          SELECT CASE
            WHEN tags->>'conveying' = 'forward' AND tags->>'incline' = 'up' THEN 'aufwärts'::text
            WHEN tags->>'conveying' = 'forward' AND tags->>'incline' = 'down' THEN 'abwärts'::text
            WHEN tags->>'conveying' = 'backward' AND tags->>'incline' = 'up' THEN 'abwärts'::text
            WHEN tags->>'conveying' = 'backward' AND tags->>'incline' = 'down' THEN 'aufwärts'::text
          END
        )),
        -- 2133: escalator changing direction
        delfi_attribute_check_values_xml('2133', tags->>'conveying', 'reversible'),
        -- 2134: escalator duration in seconds
        create_KeyValue(
          '2134',
          TRUNC(EXTRACT(epoch FROM parse_duration(tags->>'duration')))
        )
      )
    -- ramp/slope:
    WHEN tags->>'highway' IN ('path', 'footway', 'cycleway') AND tags->>'incline' IS NOT NULL AND parse_incline(tags->>'incline') <> 0 THEN
      xmlconcat(
        -- 2120: ramp or slope
        create_KeyValue('2120', ''::text),
        -- 2122: ramp length in centimeter
        create_KeyValue('2122', TRUNC(calculate_Distance(geo) * 100)),
        -- 2123: ramp width
        create_KeyValue('2123', parse_length(tags->>'width')),
        -- 2124: ramp slope
        create_KeyValue('2124', parse_incline(tags->>'incline'))
      )
    ELSE
      xmlconcat(
        -- 2020: length of the same level way in centimeter
        create_KeyValue('2020', TRUNC(calculate_Distance(geo) * 100)),
        -- 2021: width of the same level way
        create_KeyValue('2021', parse_length(tags->>'width')),
        -- 2040: track crossing required (level platform access)
        delfi_attribute_check_values_xml('2040', tags->>'railway', 'crossing', 'tram_crossing'),
        -- 2050: unpaved ground
        delfi_attribute_check_values_xml(
          '2050',
          tags->>'surface',
          'unpaved', 'compacted', 'fine_gravel', 'gravel', 'shells', 'rock', 'ground', 'dirt', 'earth', 'grass', 'sand', 'woodchips'
        ),
        -- 2100: step
        COALESCE(
          delfi_attribute_check_values_xml('2100', tags->>'barrier', 'kerb', 'step'),
          delfi_attribute_check_values_xml('2100', tags->>'kerb', 'raised', 'rolled', 'yes')
        ),
        -- 2101: step height
        create_KeyValue('2101', parse_length(
          COALESCE(tags->>'kerb:height', tags->>'step:height')
        ))
      )
  END)
));
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a keyList element for access spaces based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_AccessSpace(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList(xmlconcat(
  additionalPairs,
  -- 2080: bicycle barrier
  COALESCE(
    delfi_attribute_check_values_xml('2080', tags->>'barrier', 'cycle_barrier'),
    delfi_attribute_check_values_xml('2080', tags->>'crossing:chicane')
  ),
  -- 2081: movement area into, through and out of the narrow section
  -- delfi_attribute_check_values_xml('2081', tags->>),
  -- 2091: door width of the elevator
  -- just the entry (door) of the elevator is considered as an access space
  create_KeyValue('2091',
    (SELECT CASE
      WHEN tags->>'door' IS NOT NULL THEN tags->>'width'
    END)
  )
));
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a keyList element for entrances based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_Entrance(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList(xmlconcat(
  additionalPairs,
  -- 2030: entrance
  delfi_attribute_check_values_xml('2030', tags->>'entrance'),
  -- 2031: opening hours
  --delfi_attribute_check_values_xml('2031', tags->>'opening_hours'),
  -- 2032: type of entrance:
  create_KeyValue('2032',
    (SELECT CASE
      WHEN tags->>'door' = 'yes' THEN 'Tür'::text
      WHEN tags->>'door' = 'hinged' THEN 'Anschlagtür'::text
      WHEN tags->>'door' = 'sliding' THEN 'Schiebetür'::text
      WHEN tags->>'door' = 'revolving' THEN 'Drehtür'::text
      WHEN tags->>'door' = 'swinging' THEN 'Pendeltür'::text
    END)
  ),
  -- 2033: type of door opening:
  create_KeyValue('2033',
    (SELECT CASE
      WHEN tags->>'automatic_door' = 'yes' THEN 'automatisch'::text
      WHEN tags->>'automatic_door' = 'button' THEN 'halbautomatisch'::text
      WHEN tags->>'automatic_door' = 'motion' THEN 'automatisch'::text
    END)
  ),
  -- 2034: door width
  create_KeyValue('2034', tags->>'width')
));
$$
LANGUAGE SQL IMMUTABLE;


/*
 * Create a keyList element based on a delfi attribut to osm matching
 * Optionally additional key value pairs can be passed to the function
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_keyList_Parking(tags jsonb, additionalPairs xml DEFAULT NULL) RETURNS xml AS
$$
SELECT create_keyList($2);
$$
LANGUAGE SQL IMMUTABLE;


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
    RETURN 0;
  ELSE
    BEGIN
      RETURN TRIM_SCALE(SPLIT_PART($1->>'level', ';', 1)::NUMERIC);
    EXCEPTION WHEN OTHERS THEN
      RETURN 0;
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


/*
 * Create a AccessFeatureType element based on a variety of tags.
 * The input "tags" should be a single JSONB element (no array).
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_AccessFeatureType(tags jsonb) RETURNS xml AS
$$
DECLARE
  result xml;
BEGIN
    IF tags->>'highway' = 'steps' AND
      tags->>'conveying' IS NULL
      THEN result := 'stairs';
    ELSEIF tags->>'highway' = 'elevator'
      THEN result := 'lift';
    ELSEIF tags->>'highway' = 'steps' AND
          tags->>'conveying' IN ('yes', 'forward', 'backward', 'reversible')
      THEN result := 'escalator';
    ELSEIF tags->>'highway' = 'footway' AND
          tags->>'incline' IS NOT NULL
      THEN result := 'ramp';
    END IF;

  IF result IS NOT NULL THEN
    RETURN xmlelement(name "AccessFeatureType", result);
  END IF;

  RETURN NULL;
END
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create a NumerOfSteps element based on the tags: highway=steps and step_count.
 * The input "tags" should be a single JSONB element (no array).
 * Returns null when no tag matching exists
 */
CREATE OR REPLACE FUNCTION ex_NumberOfSteps(tags jsonb) RETURNS xml AS
$$
SELECT
  CASE
    WHEN $1->>'highway' = 'steps' AND $1->>'step_count' IS NOT NULL THEN xmlelement(
      name "NumberOfSteps",
      $1->>'step_count'
    )
    ELSE NULL
  END
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create a TransferDuration element based on the tags: duration.
 * If no duration tag is present, the duration is calculated from the length of the path link.
 * The duration is saved in the xsd:duration format.
 */
CREATE OR REPLACE FUNCTION ex_TransferDuration(tags jsonb, geo geometry, level NUMERIC) RETURNS xml AS
$$
DECLARE
  duration interval;
BEGIN
  duration := parse_duration($1->>'duration');
  IF duration IS NULL THEN
    duration := estimate_duration($1, $2, $3, 1.4);
  END IF;
  RETURN xmlelement(
    name "TransferDuration",
    xmlelement(
      name "DefaultDuration",
      duration
    )
  );
END;
$$
LANGUAGE plpgsql IMMUTABLE STRICT;


/*
 * Create an aggregate function that combines multiple jsonb objects into one.
 * This is used to combine the tags of multiple elements into one jsonb object.
 * The pgsql function 'jsonb_object_agg' does not allow the input of jsonb objects.
 * 'jsonb_agg' combines the objects into an array, which is not what we want.
 * See: https://stackoverflow.com/questions/57249804/combine-multiple-json-rows-into-one-json-object-in-postgresql
 */
CREATE OR REPLACE AGGREGATE jsonb_combine(jsonb)
(
    SFUNC = jsonb_concat(jsonb, jsonb),
    STYPE = jsonb
);


/*********
 * QUAYS *
 *********/

/* Create view that splits all platforms that have multiple IFOPTs into multiple platforms.
 * Ways that touch a platform and have the corresponding ref tag are added to the platform edges.
 * This is done by using the ST_Touches function.
 * The ST_Touches function is used to find all edges that share a node with a platform.
 * Platform edges can be part of a platform relation or must share some node with a platform.
 * Because of this just using the members of a platform relation is not sufficient.
 */
CREATE OR REPLACE VIEW platforms_split AS (
  SELECT
    -- osm_type and osm_id of the original platform is kept to be able to join stop_areas_members_ref to build the final_quays view
    ps.osm_type as osm_type,
    ps.osm_id as osm_id,
    -- Get the corresponding IFOPT by using the split IFOPT from the subquery 'ps'
    ps."split_IFOPT" as "IFOPT",
    COALESCE(jsonb_concat(ps.tags, pe.tags), ps.tags) as tags,
    COALESCE(pe.geom, ps.geom) as geom
  FROM (
    -- split platforms with multiple IFOPTs and expand into multiple rows
    -- if there is only one IFOPT the original IFOPT is put into 'split_IFOPT'
    -- 'split_ref' will be NULL if thre is no ref tag
    SELECT
      *,
      string_to_table(platforms."IFOPT", ';') AS "split_IFOPT",
      string_to_table(platforms.tags->>'ref', ';') AS "split_ref"
    FROM platforms
  ) ps
  -- Join platform edges if any to the platforms to refine tags and geometry
  LEFT JOIN platforms_edges pe
  -- Check if the platform edge fully overlaps with the platform border
  ON ST_Touches(ps.geom, pe.geom) AND
  -- Only use the platform edges that have the same ref tag as the platform
  ps."split_ref" = pe.tags->>'ref'
);


 /*
  * Sometimes there can be multiple platforms with the same IFOPT that have to be merged into one single platform.
  * See: https://github.com/OPENER-next/osm2vdv462/issues/8
  * Create view that contains all platforms and replaces the splitted platforms with merged ones.
  * This is done by first clustering the platforms by their IFOPT and then merging the geometries and tags.
  * The tags of the elements will be merged.
  * If there is a key that has different values in the platforms, the value of the last platform is kept.
  */
CREATE OR REPLACE VIEW platforms_merged AS (
  SELECT
    -- only keep the first osm_id of the array
    (array_agg(osm_id))[1] AS osm_id,
    -- only keep the first osm_type of the array
    (array_agg(osm_type))[1] AS osm_type,
    "IFOPT",
    ST_Union(p1.geom) AS geom,
    jsonb_combine(p1.tags) AS tags
  FROM (
    SELECT
      *,
      -- only cluster elements that are directly next to each other (distance of 0)
      -- at least two elements are required to create a cluster
      ST_ClusterDBSCAN(geom, 0, 1) OVER() AS cluster_id
    FROM platforms_split
  ) p1
  GROUP BY p1."IFOPT", p1.cluster_id
);


/*
 * This view sub divides the polygon into simple sub-polygons (ST_Subdivide)
 * Wraps rectangles around each sub-polygon (ST_OrientedEnvelope)
 * Takes the rectangle with the longest side - assuming the side is to the road/track (ST_DumpSegments + MAX length)
 * Return the shorter side (width) from the selected rectangle (MIN width)
 * Inspired by https://gis.stackexchange.com/a/364502
 * NOTE: This is implemented as a view, because it turned out to be way slower as an individual function call
 * Other ideas:
 * How to find the maximum-area-rectangle inside a convex polygon?
 * https://gis.stackexchange.com/questions/59215/how-to-find-the-maximum-area-rectangle-inside-a-convex-polygon
 * Calculating average width of polygon?
 * https://gis.stackexchange.com/questions/20279/calculating-average-width-of-polygon
 * Width could also be calculated by using ST_MaximumInscribedCircle. However this would return the largest width and not the "average"
 * https://postgis.net/docs/ST_MaximumInscribedCircle.html
*/
CREATE OR REPLACE VIEW platforms_with_width AS (
  SELECT
    osm_id, osm_type, "IFOPT", q.geom,
    CASE
      -- only write "est_width" for polygons
      WHEN ST_GeometryType(geom) IN ('ST_Polygon', 'ST_MultiPolygon') THEN
        jsonb_set(q.tags, '{est_width}', to_jsonb(width))
      ELSE
        q.tags
    END
  FROM (
    SELECT DISTINCT ON (osm_id, osm_type)
      q.*,
      -- smaller sub-envelope side
      MIN(calculate_Distance(s.geom)) width,
      -- larger sub-envelope side
      MAX(calculate_Distance(s.geom)) length
    FROM (
      SELECT
        platforms_merged.*,
        ST_OrientedEnvelope(
          ST_Subdivide(
            -- remove obsolete points to improve subdivide
            ST_SimplifyPreserveTopology(geom, 0.000001), 5
          )
        ) AS envelope_geom
      FROM platforms_merged
    ) q
    -- split envelopes into individual line segments to measure their length
    -- use left join so source rows will appear in the result even if the LATERAL subquery produces no rows for them
    LEFT JOIN LATERAL ST_DumpSegments(envelope_geom) s ON true
    -- group by envelope geom to get envelope width and length
    GROUP BY osm_id, osm_type, "IFOPT", q.geom, tags, envelope_geom
    -- DISTINCT will only take the first row, therefore sort it by length
    -- so the row with the longest side is used
    ORDER BY osm_id, osm_type, length DESC
  ) q
);


/*
 * Create view that matches all platforms/quays to public transport areas by the reference table.
 */
CREATE OR REPLACE VIEW final_quays AS (
  SELECT ptr.relation_id, pts.*, get_Level(pts.tags) AS "level"
  FROM platforms_with_width pts
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
 * Interconnects all elements per stop area.
 * Example: For each quay A all other quays (B, C) are assigned
 * So the table contains the following rows: AB, AC, BA, CA, (AA is explicitly excluded in the JOIN)
 *
 * Because edges are directional this will contain AB and BA.
 * It is questionable if special cases exist, where paths between stops/quays are different
 * and whether it justifies double the path computation with PPR.
 * see the github discussion: https://github.com/OPENER-next/osm2vdv462/pull/1#discussion_r1156836297
 *
 * This table is used in the "routing" step of the pipeline.
 */
CREATE OR REPLACE VIEW stop_area_edges AS (
  -- permutation of all quays per relation (same as CROSS JOIN with WHERE)
  -- will include both directions since it is a self join
  SELECT q1.relation_id, q1."IFOPT" AS "start_IFOPT", q2."IFOPT" AS "end_IFOPT", ST_Centroid(q1.geom) AS start_geom, ST_Centroid(q2.geom) AS end_geom
  FROM final_quays AS q1
  INNER JOIN final_quays AS q2
  ON q1.relation_id = q2.relation_id AND q1 != q2
  UNION ALL
  -- permutation of all entrances and quays per relation
  -- first direction
  SELECT q.relation_id, q."IFOPT" AS "start_IFOPT", e."IFOPT" AS "end_IFOPT", ST_Centroid(q.geom) AS start_geom, ST_Centroid(e.geom) AS end_geom
  FROM final_quays AS q
  INNER JOIN final_entrances AS e
  ON e.relation_id = q.relation_id
  UNION ALL
  -- reverse direction
  SELECT q.relation_id, e."IFOPT" AS "start_IFOPT", q."IFOPT" AS "end_IFOPT", ST_Centroid(e.geom) AS start_geom, ST_Centroid(q.geom) AS end_geom
  FROM final_quays AS q
  INNER JOIN final_entrances AS e
  ON e.relation_id = q.relation_id
);


/*
 * Final site path link view
 * The tables "paths_elements_ref" and "highways" are joined to create a view that contains all path links with their osm tags.
 * All elements (ways and nodes) of the "paths_elements_ref" table are joined to be able to later generate the xml field "accessFeatureType"
 * and to be able to extract the delfi attributes out of the tags.
 * There should be no case where a path link is composed of multiple access features (stairs, ...) so that a correct assignment to an accessFeatureType can be made.
 */
CREATE OR REPLACE VIEW final_site_path_links AS (
  -- use distinct to filter any duplicated joined paths
  SELECT DISTINCT ON (pl.path_id)
    -- fallback to empty tags if no matching element exists
    stop_area_relation_id AS relation_id, pl.path_id::text as id, COALESCE(hw.tags, '{}'::jsonb) as tags, pl.geom, pl.level, start_node_id as "from", end_node_id as "to"
  FROM path_links pl
  LEFT JOIN (
    SELECT DISTINCT per.path_id, jsonb_combine(highways.tags) as tags
    FROM paths_elements_ref per
    LEFT JOIN highways
      ON highways.osm_id = per.osm_id AND highways.osm_type = per.osm_type
    GROUP BY per.path_id
  ) AS hw
  ON hw.path_id = pl.path_id
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
        pat.id AS "id", pat.tags AS tags, pat.geom AS geom, pat."level" AS "level", pat.from AS "from", pat.to AS "to"
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
    ex_keyList_StopPlace(ex.area_tags),
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
    -- ORDER BY is important for NeTEx validity
    -- Quays, AccessSpaces, Entrances & Parkings should come first while the SitePathLinks should be the last
    xmlagg(ex.xml_children ORDER BY ex.category ASC)
  )
  FROM (
    SELECT ex.category, ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels,
    CASE
      -- <quays>
      WHEN ex.category = 'QUAY' THEN xmlelement(name "quays", (
        xmlagg(
          -- <Quay>
          xmlelement(name "Quay", xmlattributes(ex.id AS "id", 'any' AS "version"),
            -- <keyList>
            ex_keyList_Quay(ex.tags),
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
            ex_keyList_Entrance(ex.tags),
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
            ex_keyList_AccessSpace(ex.tags),
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
            ex_keyList_Parking(ex.tags),
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
            ex_keyList_SitePathLink(ex.tags, ex.geom),
            -- <Distance>
            ex_Distance(ex.geom),
            -- <LineString>
            ex_LineString(ex.geom, ex.id),
            -- <From> <To>
            ex_FromTo(ex.from, ex.to),
            -- <NumberOfSteps>
            ex_NumberOfSteps(ex.tags),
            -- <AccessFeatureType>
            ex_AccessFeatureType(ex.tags),
            -- <TransferDuration>
            ex_TransferDuration(ex.tags, ex.geom, ex.level)
          )
        )
      ))
    END AS xml_children
    FROM export_data ex
    GROUP BY ex.category, ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels
  ) AS ex
  GROUP BY ex.relation_id, ex.area_id, ex.area_tags, ex.area_geom, ex.operator_id, ex.network_id, ex.levels
);
