require 'utils'

local extract_conditions = {
    {
        ['public_transport'] = {
            'stop_area'
        }
    }
}

-- Create tables

local tables = {
    -- Create table that contains all public_transport area relations
    stop_area = osm2pgsql.define_relation_table("stop_areas", {
        { column = 'IFOPT', type = 'text', not_null = true },
        { column = 'tags', type = 'jsonb', not_null = true }
    }),

    -- Create table that contains the mapping of the public_transport area to its members
    stop_areas_members_ref = osm2pgsql.define_relation_table("stop_areas_members_ref", {
        { column = 'member_id', type = 'BIGINT' },
        { column = 'osm_type', type = 'text', sql_type = 'CHAR(1)' }
    })
}


function extract_stop_areas(object)
    local is_area = extract_by_conditions_to_table(object, 'relation', extract_conditions, tables.stop_area)
    if is_area then
        -- Go through all members and store them in a separate reference table
        for _, member in ipairs(object.members) do
            tables.stop_areas_members_ref:add_row({
                member_id = member.ref,
                osm_type = member.type:upper()
            })
        end
    end
    return is_area
end
