package.path = package.path .. ';scripts/osm2pgsql/?.lua'

require 'public_transport'
require 'paths'
require 'places_of_interest'

function osm2pgsql.process_node(object)
    if extract_public_transport_stops(object, 'node') then return end
    extract_places_of_interest(object, 'node')
end

function osm2pgsql.process_way(object)
    if extract_public_transport_stops(object, 'way') then return end
    if extract_paths(object) then return end
    extract_places_of_interest(object, 'way')
end

function osm2pgsql.process_relation(object)
    if extract_public_transport_areas(object) then return end
    extract_places_of_interest(object, 'relation')
end
