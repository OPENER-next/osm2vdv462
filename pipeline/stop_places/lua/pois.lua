require 'utils'

local extract_conditions = {
    {
        ['amenity'] = {
            'car_sharing',
            'bench',
            'shelter',
            'toilets',
            'telephone',
            'parking_entrance'
        }
    },
    {
        ['amenity'] = {
            'vending_machine'
        },
        ['vending'] = {
            'public_transport_tickets'
        }
    },
    {
        ['shop'] = {
            'ticket'
        }
    },
    {
        ['tourism'] = {
            'information'
        },
        ['information'] = {
            'office'
        }
    },
    {
        ['barrier'] = {
            'cycle_barrier'
        }
    },
    {
        ['indoor'] = {
            'door'
        }
    }
}

-- Create table that contains all pois
local pois_table = osm2pgsql.define_table({
    name = "pois",
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


function extract_pois(object, osm_type)
    return extract_by_conditions_to_table(object, osm_type, extract_conditions, pois_table)
end
