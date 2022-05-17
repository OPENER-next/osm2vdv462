require 'utils'

-- Define the table columns
-- The column names should be equal to the OSM tag/key they are supposed to store, because we reuse this table later

local public_transport_areas_columns = {
    { column = 'name', type = 'text' },
    { column = 'ref', type = 'text' },
    { column = 'ref:IFOPT', type = 'text' },
    { column = 'operator', type = 'text' }
}

local public_transport_stops_columns = {
    { column = 'name', type = 'text' },
    { column = 'ref', type = 'text' },
    { column = 'ref:IFOPT', type = 'text' },
    { column = 'operator', type = 'text' }
}


-- Create tables

local tables = {
    -- Create table that contains all public_transport area relations
    public_transport_area = osm2pgsql.define_relation_table("public_transport_areas", {
        { column = 'tags', type = 'jsonb' },
        -- note: unpack needs to be put at the end in order to work correctly
        table.unpack(public_transport_areas_columns)
    }),

    -- Create table that contains the mapping of the public_transport area to its members
    public_transport_areas_members_ref = osm2pgsql.define_relation_table("public_transport_areas_members_ref", {
        { column = 'member_id', type = 'BIGINT' },
        { column = 'osm_type', type = 'text', sql_type = 'CHAR(1)' },
    }),

    -- Create table that contains all public_transport relevant elements
    public_transport_stops = osm2pgsql.define_table({
        name = "public_transport_stops",
        ids = {
            type = 'any',
            id_column = 'osm_id',
            type_column = 'osm_type'
        },
        columns = {
            { column = 'tags', type = 'jsonb' },
            { column = 'geom', type = 'geometry' },
            -- note: unpack needs to be put at the end in order to work correctly
            table.unpack(public_transport_stops_columns)
        }
    })
}


function extract_public_transport_areas(object)
    local is_area = object.tags.public_transport == 'stop_area'
    if is_area then
        local row = build_row(object, public_transport_areas_columns)
        tables.public_transport_area:add_row(row)

        -- Go through all members and store them in a separate reference table
        for _, member in ipairs(object.members) do
            tables.public_transport_areas_members_ref:add_row({
                member_id = member.ref,
                osm_type = member.type:upper()
            })
        end
    end
    return is_area
end


function extract_public_transport_stops(object, osm_type)
    local is_stop = object.tags.public_transport == 'platform'
    if is_stop then
        local row = build_row(object, public_transport_stops_columns, osm_type)
        tables.public_transport_stops:add_row(row)
    end
    return is_stop
end
