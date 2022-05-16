-- Create a centroid element from any geometry
-- Returns null when any argument is null

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


-- Create a single key value pair element
-- Returns null when any argument is nul^

CREATE OR REPLACE FUNCTION create_key_value_xml(a anyelement, b anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "KeyValue",
  xmlelement(name "Key", $1),
  xmlelement(name "Value", $2)
)
$$
LANGUAGE SQL IMMUTABLE STRICT;


-- returns a StopPlaceType value based on the columns/tags train, subway, coach and bus
-- unused types: "airport" | "harbourPort" | "ferrytPort" | "ferryStop" | "onStreetBus" | "onStreetTram" | "skiLift"
-- from: https://laidig.github.io/siri-20-java/doc/schemas/ifopt_stop-v0_3_xsd/simpleTypes/StopPlaceTypeEnumeration.html

CREATE OR REPLACE FUNCTION row_to_stop_place_type(p_row public_transport_areas) RETURNS text AS
$$
SELECT CASE
  WHEN $1.train = 'yes' THEN 'railStation'
  WHEN $1.subway = 'yes' THEN 'metroStation'
  WHEN $1.coach = 'yes' THEN 'coachStation'
  WHEN $1.bus = 'yes' THEN 'busStation'
  ELSE 'other'
END
$$
LANGUAGE SQL IMMUTABLE;



-- Build final export data table
-- Join all stops to their stop areas
-- Pre joining tables is way faster than using nested selects later, even though it contains duplicated data

CREATE TEMP TABLE export_data AS
SELECT
  ptr.relation_id,
  pta.name AS area_name, pta."ref:IFOPT" AS area_dhid,
  row_to_stop_place_type(pta) AS area_type,
  pts.name AS stop_name, pts."ref:IFOPT" AS stop_dhid, pts.geom AS stop_geom
FROM public_transport_areas_members_ref ptr
INNER JOIN public_transport_areas pta
  ON pta.relation_id = ptr.relation_id
INNER JOIN public_transport_stops pts
  ON pts.osm_id = ptr.member_id AND pts.osm_type = ptr.osm_type;


-- Final export to XML

SELECT
-- <StopPlace>
xmlelement(name "StopPlace", xmlattributes(gs.area_dhid as id),
  -- <Name>
	xmlelement(name "Name", gs.area_name),
  -- <Centroid>
	geom_to_centroid_xml(NULL),
  -- <StopPlaceType>
  xmlelement(name "StopPlaceType", gs.area_type),
  -- <keyList>
  xmlelement(name "keyList", xmlconcat(
    create_key_value_xml('GlobalID', gs.area_dhid)
  )),
  -- <quays>
  xmlelement(name "quays", (
    xmlagg(
      -- <Quay>
      xmlelement(name "Quay", gs.stop_dhid,
        -- <Name>
        xmlelement(name "Name", gs.stop_name),
        -- <Centroid>
        geom_to_centroid_xml(gs.stop_geom),
        -- <keyList>
        xmlelement(name "keyList", xmlconcat(
          create_key_value_xml('GlobalID', gs.stop_dhid)
        ))
      )
    )
  ))
)
FROM export_data gs
-- area_dhid and area_name will be identical for the same relation_id since they are just duplicates from prvious joins
GROUP BY gs.relation_id, gs.area_dhid, gs.area_name, gs.area_type


