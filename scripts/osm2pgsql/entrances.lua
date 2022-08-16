require 'utils'

local extract_conditions = {
    {
        ['entrance'] = {
            'yes', 'main', 'secondary', 'emergency', 'exit', 'entrance'
        }
    },
    {
        ['railway'] = {
            'train_station_entrance', 'subway_entrance'
        }
    },
}

-- Create table that contains all entrances
local entrances_table = osm2pgsql.define_node_table("entrances", {
    { column = 'IFOPT', type = 'text', not_null = true },
    { column = 'tags', type = 'jsonb', not_null = true },
    { column = 'geom', type = 'point', not_null = true, projection = 4326 },
    { column = 'version', type = 'int', not_null = true }
})


function extract_entrances(object, osm_type)
    return extract_by_conditions_to_table(object, 'node', extract_conditions, entrances_table)
end