/*
 * Create path geometries from the PPR steps.
 */
DROP TABLE IF EXISTS paths_ppr;
CREATE TEMPORARY TABLE paths_ppr AS (
  SELECT relation_id, path_id, path_id_individual, ST_MakeLine(step) as path
  FROM steps_ppr
  GROUP BY relation_id, path_id, path_id_individual
);


/*
 * Contains all path links by relation id.
 * - join the start and end DHIDs to the table
 * - join the tags to the table
 */
DROP TABLE IF EXISTS final_site_path_links;
CREATE TABLE final_site_path_links AS (
  -- include relation id to prevent collisions
  -- include from & to DHID in order to prevent collisions between identical paths (normal and inverted)
  -- that only consist of one way/edge, because they have the same path id
  -- md5 is required to make the id NeTEx compliant
  SELECT paths_ppr.relation_id, md5(concat_ws('_', paths_ppr.relation_id, "from", "to", paths_ppr.path_id_individual)) as id, jsonb_merge_agg(tags) AS tags, paths_ppr.path as geom, "from", "to"
  FROM paths_ppr
  JOIN paths_dhid ON paths_ppr.path_id = paths_dhid.path_id
	JOIN (
	  SELECT paths_osm_id.path_id, tags
		FROM paths_osm_id
		JOIN stop_ways ON paths_osm_id.osm_id = stop_ways.osm_id
		GROUP BY paths_osm_id.path_id, tags
	  ) t ON t.path_id = paths_ppr.path_id
	GROUP BY paths_ppr.relation_id, paths_dhid.from, paths_dhid.to, paths_ppr.path_id_individual, paths_ppr.path
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
