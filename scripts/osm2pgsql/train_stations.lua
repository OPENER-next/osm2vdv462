require 'utils'

local extract_conditions = {
    {
        ['building'] = {
            'train_station'
        }
    }
}

-- Create table that contains all train_stations
local train_station_table = osm2pgsql.define_table({
    name = "train_stations",
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


function extract_train_stations(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, train_station_table)
end
