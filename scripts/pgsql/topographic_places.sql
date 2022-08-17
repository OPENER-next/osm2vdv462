/*****************************
 * TOPOGRAPHIC PLACES EXPORT *
 *****************************/

-- Final export to XML

CREATE OR REPLACE TEMPORARY VIEW xml_topographicPlaces AS (
  SELECT NULL::xml AS xmlelement LIMIT 0
);
