-- Helper functions


-- Returns a table that represents a row
function build_row(object, columns, osm_type)
    local row = {}
    set_row_tags_by_columns(row, object, columns)
    if osm_type ~= nil then
        set_row_geom_by_type(row, object, osm_type)
    end
    row.tags = object.tags
    return row
end


function set_row_tags_by_columns(row, object, columns)
    for key, entry in ipairs(columns) do
        row[entry.column] = object:grab_tag(entry.column)
    end
end


function set_row_geom_by_type(row, object, osm_type)
    -- define fallback type as area
    row.geom = {create = 'area'}

    if (osm_type == 'node') then
        row.geom.create = 'point'
    elseif (osm_type == 'way') then
        if object.is_closed and has_area_tags(object.tags) then
            row.geom.create = 'area'
        else
            row.geom.create = 'line'
        end
    elseif (osm_type == 'relation') then
        local relation_type = object:grab_tag('type')
        if relation_type == 'boundary' then
            row.geom.create = 'line'
        end
        if relation_type == 'multipolygon' then
            row.geom.create = 'area'
        end
    end
end


-- Helper function that looks at the tags and decides if this is possibly an area.
function has_area_tags(tags)
    if tags.area == 'yes' then
        return true
    end
    if tags.area == 'no' then
        return false
    end

    return tags.aeroway
        or tags.amenity
        or tags.building
        or tags.harbour
        or tags.historic
        or tags.landuse
        or tags.leisure
        or tags.man_made
        or tags.military
        or tags.natural
        or tags.office
        or tags.place
        or tags.power
        or tags.public_transport
        or tags.shop
        or tags.sport
        or tags.tourism
        or tags.water
        or tags.waterway
        or tags.wetland
        or tags['abandoned:aeroway']
        or tags['abandoned:amenity']
        or tags['abandoned:building']
        or tags['abandoned:landuse']
        or tags['abandoned:power']
        or tags['area:highway']
end


-- Check whether the given tags match any condition from the list
function matches(tags, condition_list)
    for _, condition in ipairs(condition_list) do
        if (condition_matches_tags(condition, tags)) then
            return true
        end
    end
    return false
end


function condition_matches_tags(condition, tags)
    for key, values in pairs(condition) do
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


-- Helper function to check whether a list contains a given value or not.
function list_has_value(list, val)
    for index, value in ipairs(list) do
        if value == val then
            return true
        end
    end
    return false
end
