require 'utils'

-- Define the table columns
-- The column names should be equal to the OSM tag/key they are supposed to store, because we reuse this table later

local stop_areas_columns = {
    { column = 'name', type = 'text' },
    { column = 'ref', type = 'text' },
    { column = 'ref:IFOPT', type = 'text' },
    { column = 'operator', type = 'text' },
    { column = 'version', type = 'int' }
}

-- Create tables

local tables = {
    -- Create table that contains all public_transport area relations
    stop_area = osm2pgsql.define_relation_table("stop_areas", {
        { column = 'tags', type = 'jsonb' },
        -- note: unpack needs to be put at the end in order to work correctly
        table.unpack(stop_areas_columns)
    }),

    -- Create table that contains the mapping of the public_transport area to its members
    stop_areas_members_ref = osm2pgsql.define_relation_table("stop_areas_members_ref", {
        { column = 'member_id', type = 'BIGINT' },
        { column = 'osm_type', type = 'text', sql_type = 'CHAR(1)' },
    }),
}


function extract_stop_areas(object)
    local is_area = object.tags.public_transport == 'stop_area'
    if is_area then
        local row = build_row(object, stop_areas_columns)
        tables.stop_area:add_row(row)

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
