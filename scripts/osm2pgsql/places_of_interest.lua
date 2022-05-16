require 'utils'

-- Define the table columns
-- The column names should be equal to the OSM tag/key they are supposed to store, because we reuse this table later

local places_of_interest_columns = {
    { column = 'building', type = 'text' },
    { column = 'amenity', type = 'text' },
    { column = 'shop', type = 'text' },
    { column = 'leisure', type = 'text' },
    { column = 'office', type = 'text' },
    { column = 'area', type = 'text' },
    { column = 'barrier', type = 'text' },
    { column = 'tourism', type = 'text' },
    { column = 'landuse', type = 'text' },
    { column = 'entrance', type = 'text' },
    { column = 'door', type = 'text' },
}


-- Create tables

local tables = {
    -- Create table that contains places of interest (pois, buildings, areas, ..)
    places_of_interest = osm2pgsql.define_table({
        name = "places_of_interest",
        ids = {
            type = 'any',
            id_column = 'osm_id',
            type_column = 'osm_type'
        },
        columns = {
            { column = 'tags', type = 'jsonb' },
            { column = 'geom', type = 'geometry' },
            -- note: unpack needs to be put at the end in order to work correctly
            table.unpack(places_of_interest_columns)
        }
    })
}


function extract_places_of_interest(object, osm_type)
    local is_ploi = contains_tag_from_columns(object.tags, places_of_interest_columns)
    if is_ploi then
        local row = build_row(object, places_of_interest_columns, osm_type)
        tables.places_of_interest:add_row(row)
    end
    return is_ploi
end
