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
    { column = 'tags', type = 'jsonb' },
    { column = 'geom', type = 'point' },
    { column = 'version', type = 'int' }
})


function extract_stop_positions(object, osm_type)
    return extract_by_conditions_to_table(object, 'node', extract_conditions, stop_positions_table)
end