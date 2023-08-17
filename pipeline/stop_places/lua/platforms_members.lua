require 'utils'

local extract_conditions = {
    {
        ['railway'] = {
            'platform_edge'
        }
    }
}

-- Create table that contains members of platforms
local platforms_members_table = osm2pgsql.define_table({
    name = "platforms_members",
    ids = {
        type = 'any',
        id_column = 'osm_id',
        type_column = 'osm_type'
    },
    columns = {
        { column = 'tags', type = 'jsonb', not_null = true },
        { column = 'geom', type = 'geometry', not_null = true, projection = 4326 }
    }
})


function extract_platforms_members(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, platforms_members_table)
end