/*****************
 * VDV462 EXPORT *
 *****************/

SELECT xmlserialize(DOCUMENT
  xmlroot(
    xmlelement(name "PublicationDelivery", xmlattributes('http://www.netex.org.uk/netex' AS "xmlns", 'ntx:1.1' AS "version"),
      xmlelement(name "PublicationTimestamp", LOCALTIMESTAMP(0)),
      xmlelement(name "ParticipantRef", 'OPENER-next'),
      xmlelement(name "dataObjects",
        -- for version "any" see VDV 462 - 6.1 Objektversionen
        xmlelement(name "CompositeFrame", xmlattributes('CompositeFrame_1' AS "id", 'any' AS "version"),
          xmlelement(name "ValidBetween",
            xmlelement(name "FromDate", LOCALTIMESTAMP(0))
          ),
          xmlelement(name "FrameDefaults",
            xmlelement(name "DefaultLocale",
              xmlelement(name "TimeZone", current_setting('TIMEZONE')),
              xmlelement(name "DefaultLanguage", current_setting('export.LANGUAGE'))
            ),
            xmlelement(name "DefaultLocationSystem", current_setting('export.PROJECTION'))
          ),
          xmlelement(name "frames",
            xmlelement(name "SiteFrame", xmlattributes('SiteFrame_1' AS "id", 'any' AS "version"),
              -- use xmlforest to remove/avoid empty elements to validate NeTEx
              -- https://stackoverflow.com/questions/36340104/how-can-i-get-rid-of-unwanted-empty-xml-tags
              xmlforest(
                ( SELECT xmlagg(xmlelement) FROM xml_stopPlaces ) AS "stopPlaces",
                ( SELECT xmlagg(xmlelement) FROM xml_parkings ) AS "parkings"
              )
            ),
            xmlelement(name "ResourceFrame", xmlattributes('ResourceFrame_1' AS "id", 'any' AS "version"),
              xmlforest(
                ( SELECT xmlagg(xmlelement) FROM xml_organisations ) AS "organisations"
              )
            )
          )
        )
      )
    ),
    version '1.0', standalone no
  )
  AS TEXT INDENT
);
