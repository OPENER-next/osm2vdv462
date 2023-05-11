require 'utils'

local extract_conditions = {
    {
        ['public_transport'] = {
            'platform'
        }
    },
    {
        ['highway'] = {
            'platform'
        }
    },
    {
        ['railway'] = {
            'platform'
        }
    }
}

-- Create table that contains all platforms
local platforms_table = osm2pgsql.define_table({
    name = "platforms",
    ids = {
        type = 'any',
        id_column = 'osm_id',
        type_column = 'osm_type'
    },
    columns = {
        { column = 'IFOPT', type = 'text', not_null = true },
        { column = 'tags', type = 'jsonb', not_null = true },
        { column = 'geom', type = 'geometry', not_null = true, projection = 4326 }
    }
})


function extract_platforms(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, platforms_table)
end