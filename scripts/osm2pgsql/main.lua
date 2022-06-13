package.path = package.path .. ';scripts/osm2pgsql/?.lua'

require 'public_transport'
require 'train_stations'
require 'paths'
require 'entrances'
require 'parking'
require 'pois'

function osm2pgsql.process_node(object)
    if extract_public_transport_stops(object, 'node') then return end
    if extract_entrances(object) then return end
    if extract_parking(object, 'node') then return end
    extract_pois(object, 'node')
end

function osm2pgsql.process_way(object)
    if extract_public_transport_stops(object, 'way') then return end
    if extract_train_stations(object, 'way') then return end
    if extract_parking(object, 'way') then return end
    if extract_paths(object) then return end
    extract_pois(object, 'way')
end

function osm2pgsql.process_relation(object)
    if extract_public_transport_stops(object, 'relation') then return end
    if extract_public_transport_areas(object) then return end
    if extract_train_stations(object, 'relation') then return end
    if extract_parking(object, 'relation') then return end
    extract_pois(object, 'relation')
end
