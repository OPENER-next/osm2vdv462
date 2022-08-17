/************************
 * ORGANISATIONS EXPORT *
 ************************/

-- Final export to XML

CREATE OR REPLACE TEMPORARY VIEW xml_organisations AS (
  SELECT NULL::xml AS xmlelement LIMIT 0
);
