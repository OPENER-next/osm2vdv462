/*******************
 * PARKINGS EXPORT *
 *******************/

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
 * Create view that matches all parking spaces to public transport areas by the reference table.
 */
CREATE OR REPLACE VIEW export_parkings_data AS (
  SELECT ptr.relation_id, par.*, get_Level(par.tags) AS "level"
  FROM parking par
  JOIN stop_areas_members_ref ptr
    ON par.osm_id = ptr.member_id AND par.osm_type = ptr.osm_type
);

-- Final export to XML

CREATE OR REPLACE VIEW xml_parkings AS (
  SELECT xmlelement(name "Parking", xmlattributes(osm_type || osm_id AS "id", 'any' AS "version"),
    -- <keyList>
    ex_keyList_Parking(tags),
    -- <Name>
    ex_Name(tags),
    -- <Centroid>
    ex_Centroid(geom),
    -- <LevelRef>
    ex_LevelRef(relation_id, level),
    -- <ParkingType>
    ex_ParkingType(tags),
    -- <ParkingLayout>
    ex_ParkingLayout(tags),
    -- <TotalCapacity>
    ex_TotalCapacity(tags)
  )
  FROM export_parkings_data
);
