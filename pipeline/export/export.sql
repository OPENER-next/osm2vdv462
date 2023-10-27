/*****************
 * VDV462 EXPORT *
 *****************/

SELECT xmlroot(
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
            xmlelement(name "stopPlaces",
              ( SELECT xmlagg(xmlelement) FROM xml_stopPlaces )
            ),
            -- if element is empty remove it, to validate NeTEx
            -- https://stackoverflow.com/questions/77374040
            NULLIF(
              xmlelement(name "parkings",
                ( SELECT xmlagg(xmlelement) FROM xml_parkings )
              )::text,
              '<parkings/>'::text
            )
          ),
          xmlelement(name "ResourceFrame", xmlattributes('ResourceFrame_1' AS "id", 'any' AS "version"),
            xmlelement(name "organisations",
              ( SELECT xmlagg(xmlelement) FROM xml_organisations )
            )
          )
        )
      )
    )
  ),
  version '1.0', standalone no
);
