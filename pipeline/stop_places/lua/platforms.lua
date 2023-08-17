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

-- Create tables

local tables = {
-- Create table that contains all platforms
    platforms_table = osm2pgsql.define_table({
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
    }),

    -- Create table that contains the mapping of the public_transport area to its members
    platforms_members_ref = osm2pgsql.define_relation_table("platforms_members_ref", {
        { column = 'member_id', type = 'BIGINT' },
        { column = 'osm_type', type = 'text', sql_type = 'CHAR(1)' }
    })
}


function extract_platforms(object, osm_type)
    local is_platform = extract_by_conditions_to_table(object, osm_type, extract_conditions, tables.platforms_table)
    if is_platform and osm_type == 'relation' then
        -- Go through all members and store them in a separate reference table
        for _, member in ipairs(object.members) do
            tables.platforms_members_ref:add_row({
                member_id = member.ref,
                osm_type = member.type:upper()
            })
        end
    end
    return is_platform
end