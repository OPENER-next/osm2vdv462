require 'utils'

local extract_conditions = {
    {
        ['highway'] = {
            'pedestrian', 'footway', 'steps', 'corridor', 'path', 'crossing', 'elevator'
        },
        ['access'] = {
            false, 'customers', 'yes'
        }
    },
    {
        ['highway'] = true,
        ['sidewalk'] = {
            'yes', 'left', 'right', 'both'
        }
    },
    {
        ['highway'] = true,
        ['sidewalk:left'] = {
            'yes'
        }
    },
    {
        ['highway'] = true,
        ['sidewalk:right'] = {
            'yes'
        }
    },
    {
        ['highway'] = true,
        ['sidewalk:both'] = {
            'yes'
        }
    }
}

-- Create table that contains all highways
local highways_table = osm2pgsql.define_table({
    name = "highways",
    ids = {
        type = 'any',
        id_column = 'osm_id',
        type_column = 'osm_type'
    },
    columns = {
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry' },
        { column = 'version', type = 'int' }
    }
})


function extract_highways(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, highways_table)
end
