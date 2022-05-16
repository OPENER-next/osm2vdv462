require 'utils'

-- Define the table columns
-- The column names should be equal to the OSM tag/key they are supposed to store, because we reuse this table later

local paths_columns = {
    { column = 'highway', type = 'text' },
}


-- Create tables

local tables = {
    -- Create table that contains all ways and connections
    -- TODO: Investigate highways of type node with value elevator or crossing (https://wiki.openstreetmap.org/wiki/DE%3ATag%3Ahighway%3Dcrossing)
    -- See all highway values for nodes: https://taginfo.openstreetmap.org/keys/?key=highway&filter=nodes#values
    paths = osm2pgsql.define_way_table("paths", {
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring' },
        -- note: unpack needs to be put at the end in order to work correctly
        table.unpack(paths_columns)
    })
}


function extract_paths(object)
    local is_path = object.tags.highway ~= nil
    if is_path then
        local row = build_row(object, paths_columns)
        tables.paths:add_row(row)
    end
    return is_path
end
