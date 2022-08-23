/************************
 * ORGANISATIONS EXPORT *
 ************************/

/*
 * Create Name element
 * Returns null when the given argument is null
 */
CREATE OR REPLACE FUNCTION ex_Name(name anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "Name", $1)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create ShortName element
 * Returns null when the given argument is null
 */
CREATE OR REPLACE FUNCTION ex_ShortName(short_name anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "ShortName", $1)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create LegalName element
 * Returns null when the given argument is null
 */
CREATE OR REPLACE FUNCTION ex_LegalName(legal_name anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "LegalName", $1)
$$
LANGUAGE SQL IMMUTABLE STRICT;


/*
 * Create ContactDetails element with appropriate child elements
 * Returns an empty ContactDetails when all given arguments are null
 */
CREATE OR REPLACE FUNCTION ex_ContactDetails(phone anyelement, mail anyelement, website anyelement) RETURNS xml AS
$$
SELECT xmlelement(name "ContactDetails",
  CASE WHEN $2 IS NOT NULL THEN
    xmlelement(name "Email", $2)
  END,
  CASE WHEN $1 IS NOT NULL THEN
    xmlelement(name "Phone", $1)
  END,
  CASE WHEN $3 IS NOT NULL THEN
    xmlelement(name "Url", $3)
  END
)
$$
LANGUAGE SQL IMMUTABLE;


/*
 * The wikidata query result can contain multiple rows with the same id,
 * because some fields might have multiple values (e.g. multiple phone numbers).
 * Therefore we remove any duplicated rows here and only take the first row values.
 */
CREATE OR REPLACE TEMPORARY VIEW export_organisations_data AS (
  SELECT DISTINCT ON (id) *
  FROM organisations
);

-- Final export to XML

CREATE OR REPLACE TEMPORARY VIEW xml_organisations AS (
  SELECT CASE
    WHEN "type" = 'operator' THEN xmlelement(name "Operator",
      xmlattributes(id AS "id", 'any' AS "version"),
      ex_Name("label"),
      ex_ShortName("short_name"),
      ex_LegalName("official_name"),
      ex_ContactDetails("phone", "email", "website"),
      xmlelement(name "OrganisationType", 'operator')
    )
    ELSE xmlelement(name "Authority",
      xmlattributes(id AS "id", 'any' AS "version"),
      ex_Name("label"),
      ex_ShortName("short_name"),
      ex_LegalName("official_name"),
      ex_ContactDetails("phone", "email", "website"),
      xmlelement(name "OrganisationType", 'authority')
    )
  END
  FROM export_organisations_data
  ORDER BY "type"
);
