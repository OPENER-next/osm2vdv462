require 'utils'

local extract_conditions = {
    {
        ['entrance'] = {
            'yes', 'main', 'secondary', 'emergency', 'exit', 'entrance'
        },
        ['access'] = {
            false, 'customers', 'yes'
        }
    },
    {
        ['railway'] = {
            'train_station_entrance', 'subway_entrance'
        },
        ['access'] = {
            false, 'customers', 'yes'
        }
    },
}

-- Create table that contains all entrances
local entrances_table = osm2pgsql.define_node_table("entrances", {
    { column = 'tags', type = 'jsonb' },
    { column = 'geom', type = 'point' },
    { column = 'version', type = 'int' }
})


function extract_entrances(object, osm_type)
    return extract_by_conditions_to_table(object, 'node', extract_conditions, entrances_table)
end