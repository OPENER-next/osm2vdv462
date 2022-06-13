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


-- Create tables

local tables = {
    -- Create table that contains all entrances
    entrances = osm2pgsql.define_node_table("entrances", {
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'point' },
    })
}


function extract_entrances(object)
    local is_entrance = matches(object.tags, extract_conditions)
    if is_entrance then
        local row = {
            tags = object.tags
        }
        set_row_geom_by_type(row, object, 'node')

        tables.entrances:add_row(row)
    end
    return is_entrance
end
