require 'utils'

local extract_conditions = {
    {
        ['amenity'] = {
            'parking', 'motorcycle_parking', 'bicycle_parking', 'taxi'
        }
    },
    {
        ['parking:lane:both'] = {
            'yes', 'parallel', 'diagonal', 'perpendicular'
        }
    },
    {
        ['parking:lane:left'] = {
            'yes', 'parallel', 'diagonal', 'perpendicular'
        }
    },
    {
        ['parking:lane:right'] = {
            'yes', 'parallel', 'diagonal', 'perpendicular'
        }
    }
}

-- Create table that contains all parking
local parking_table = osm2pgsql.define_table({
    name = "parking",
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


function extract_parking(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, parking_table)
end