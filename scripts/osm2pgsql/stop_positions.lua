require 'utils'

local extract_conditions = {
    {
        ['public_transport'] = {
            'stop_position'
        }
    }
}

-- Create table that contains all stop_positions
local stop_positions_table = osm2pgsql.define_node_table("stop_positions", {
    { column = 'IFOPT', type = 'text', not_null = true },
    { column = 'tags', type = 'jsonb', not_null = true },
    { column = 'geom', type = 'point', not_null = true },
    { column = 'version', type = 'int', not_null = true }
})


function extract_stop_positions(object, osm_type)
    return extract_by_conditions_to_table(object, 'node', extract_conditions, stop_positions_table)
end