require 'utils'

-- More info regarding named spots: https://wiki.openstreetmap.org/wiki/Named_spots_instead_of_street_names

local extract_conditions = {
    {
        ['indoor'] = {
            'area', 'corridor', 'room'
        }
    },
    {
        ['highway'] = {
            'footway', 'pedestrian', 'path', 'corridor'
        }
    },
    {
        ['place'] = {
            'square', 'locality'
        }
    },
    {
        ['junction'] = {
            'yes'
        }
    },
    {
        ['reference_point'] = {
            'yes'
        }
    }
}

-- Create table that contains all access spaces
local access_spaces_table = osm2pgsql.define_table({
    name = "access_spaces",
    ids = {
        type = 'any',
        id_column = 'osm_id',
        type_column = 'osm_type'
    },
    columns = {
        { column = 'IFOPT', type = 'text', not_null = true },
        { column = 'tags', type = 'jsonb', not_null = true },
        { column = 'geom', type = 'geometry', not_null = true },
        { column = 'version', type = 'int', not_null = true }
    }
})


function extract_access_spaces(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, access_spaces_table)
end
