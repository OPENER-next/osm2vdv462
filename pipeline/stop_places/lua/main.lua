package.path = package.path .. ';/scripts/osm2pgsql/?.lua'

require 'stop_areas'
require 'platforms'
require 'platforms_edges'
require 'stop_positions'
require 'entrances'
require 'parking'
require 'highways'
require 'pois'

function osm2pgsql.process_node(object)
    if extract_stop_positions(object, 'node') then return end
    if extract_platforms(object, 'node') then return end
    if extract_entrances(object) then return end
    if extract_parking(object, 'node') then return end
    if extract_highways(object, 'node') then return end
    extract_pois(object, 'node')
end

function osm2pgsql.process_way(object)
    if extract_platforms(object, 'way') then return end
    if extract_platforms_edges(object, 'way') then return end
    if extract_parking(object, 'way') then return end
    if extract_highways(object, 'way') then return end
    extract_pois(object, 'way')
end

function osm2pgsql.process_relation(object)
    if extract_platforms(object, 'relation') then return end
    if extract_stop_areas(object) then return end
    if extract_parking(object, 'relation') then return end
    if extract_highways(object, 'relation') then return end
    extract_pois(object, 'relation')
end
