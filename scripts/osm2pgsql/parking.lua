require 'utils'

local extract_conditions = {
    {
        ['amenity'] = {
            'parking', 'motorcycle_parking', 'bicycle_parking', 'taxi'
        },
        ['access'] = { false, 'customers', 'yes' }
    },
    {
        ['parking:lane:both'] = { 'yes', 'parallel', 'diagonal', 'perpendicular' }
    },
    {
        ['parking:lane:left'] = { 'yes', 'parallel', 'diagonal', 'perpendicular' }
    },
    {
        ['parking:lane:right'] = { 'yes', 'parallel', 'diagonal', 'perpendicular' }
    },
}


-- Create tables

local tables = {
    -- Create table that contains all parking
    parking = osm2pgsql.define_table({
        name = "parking",
        ids = {
            type = 'any',
            id_column = 'osm_id',
            type_column = 'osm_type'
        },
        columns = {
            { column = 'tags', type = 'jsonb' },
            { column = 'geom', type = 'geometry' }
        }
    })
}


function extract_parking(object, osm_type)
    local is_parking = matches(object.tags, extract_conditions)
    if is_parking then
        local row = {
            tags = object.tags
        }
        set_row_geom_by_type(row, object, osm_type)

        tables.parking:add_row(row)
    end
    return is_parking
end
