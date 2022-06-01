require 'utils'

local poi_mappings = {
    {
        label = 'car_sharing',
        tags = {
            amenity = {
                'car_sharing'
            }
        },
    },
    {
        label = 'bench',
        tags = {
            amenity = {
                'bench'
            }
        },
    },
    {
        label = 'shelter',
        tags = {
            amenity = {
                'shelter'
            }
        },
    },
    {
        label = 'toilets',
        tags = {
            amenity = {
                'toilets'
            },
            access = {
                false,
                'customers',
                'yes'
            }
        },
    },
    {
        label = 'telephone',
        tags = {
            amenity = {
                'telephone'
            }
        },
    },
    {
        label = 'taxi',
        tags = {
            amenity = {
                'taxi'
            }
        },
    },
    {
        label = 'parking_entrance',
        tags = {
            amenity = {
                'parking_entrance'
            }
        },
    },
    {
        label = 'parking',
        tags = {
            amenity = {
                'parking'
            },
            access = {
                false,
                'customers',
                'yes'
            }
        },
    },
    {
        label = 'bicycle_parking',
        tags = {
            amenity = {
                'bicycle_parking'
            },
            access = {
                false,
                'customers',
                'yes'
            }
        },
    },
    {
        label = 'ticket_vending_machine',
        tags = {
            amenity = {
                'vending_machine'
            },
            vending = {
                'public_transport_tickets'
            }
        },
    },
    {
        label = 'subway_entrance',
        tags = {
            railway = {
                'subway_entrance'
            }
        },
    },
    {
        label = 'door',
        tags = {
            door = true,
            access = {
                false,
                'customers',
                'yes'
            }
        },
    },
    {
        label = 'entrance',
        tags = {
            entrance = true,
            access = {
                false,
                'customers',
                'yes'
            }
        },
    },
    {
        label = 'ticket_shop',
        tags = {
            shop = {
                'ticket'
            }
        },
    },
    {
        label = 'information_office',
        tags = {
            tourism = {
                'information'
            },
            information = {
                'office'
            }
        },
    },
}


-- Create tables

local tables = {
    -- Create table that contains points of interest
    pois = osm2pgsql.define_table({
        name = "pois",
        ids = {
            type = 'any',
            id_column = 'osm_id',
            type_column = 'osm_type'
        },
        columns = {
            { column = 'poi_type', type = 'text' },
            { column = 'tags', type = 'jsonb' },
            { column = 'geom', type = 'geometry' }
        }
    })
}


function extract_pois(object, osm_type)
    local label = get_label_from_mapping(object.tags, poi_mappings)
    local is_poi = label ~= nil
    if is_poi then
        local row = build_mapping_row(object, label, osm_type)
        tables.pois:add_row(row)
    end
    return is_poi
end


-- Returns a table that represents a row
function build_mapping_row(object, label, osm_type)
    local row = {
        poi_type = label,
        tags = object.tags
    }
    if osm_type ~= nil then
        set_row_geom_by_type(row, object, osm_type)
    end
    return row
end


-- Grab the first key value pair of an element and return it
-- If none matches key, value will be nil
function get_label_from_mapping(tags, mapping)
    for _, entry in ipairs(mapping) do
        if (conditions_match_tags(entry.tags, tags)) then
            return entry.label
        end
    end
    return nil
end


function conditions_match_tags(conditions, tags)
    for key, values in pairs(conditions) do
        local tagValue = tags[key]

        if tagValue == nil then
            if values == true or not list_has_value(values, false) then
                return false
            end
        elseif values ~= true and not list_has_value(values, tagValue) then
            return false
        end
    end
    return true
end
