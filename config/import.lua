-- Define the table columns
-- The column names should be equal to the OSM tag/key they are supposed to store, because we reuse this table later

local public_transport_columns = {
    { column = 'name', type = 'text' },
    { column = 'ref', type = 'text' },
    { column = 'public_transport', type = 'text' },
    { column = 'ref:IFOPT', type = 'text' },
    { column = 'operator', type = 'text' },
}

local paths_columns = {
    { column = 'highway', type = 'text' },
}

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


-- Create tables and store references
local tables = {}

-- Create table that contains all public_transport relevant elements
tables.public_transport = osm2pgsql.define_table({
    name = "public_transport",
    ids = {
        type = 'any',
        id_column = 'osm_id',
        type_column = 'osm_type'
    },
    columns = {
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry' },
        -- note: unpack needs to be put at the end in order to work correctly
        table.unpack(public_transport_columns)
    }
})

-- Create table that contains all ways and connections
-- TODO: Investigate highways of type node with value elevator or crossing (https://wiki.openstreetmap.org/wiki/DE%3ATag%3Ahighway%3Dcrossing)
-- See all highway values for nodes: https://taginfo.openstreetmap.org/keys/?key=highway&filter=nodes#values
tables.paths = osm2pgsql.define_way_table("paths", {
    { column = 'tags', type = 'jsonb' },
    { column = 'geom', type = 'linestring' },
    -- note: unpack needs to be put at the end in order to work correctly
    table.unpack(paths_columns)
})

-- Create table that contains places of interest (pois, buildings, areas, ..)
tables.places_of_interest = osm2pgsql.define_table({
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

-- Process and add osm elements to tables

function extract_public_transport(object, osm_type)
    local is_public_transport = object.tags.public_transport ~= nil
    if is_public_transport then
        local row = build_row(object, public_transport_columns, osm_type)
        row.geom = { create = 'point' }
        tables.public_transport:add_row(row)
    end
    return is_public_transport
end

function extract_paths(object)
    local is_path = object.tags.highway ~= nil
    if is_path then
        local row = build_row(object, paths_columns)
        tables.paths:add_row(row)
    end
    return is_path
end

function extract_places_of_interest(object, osm_type)
    local is_ploi = contains_tag_from_columns(object.tags, places_of_interest_columns)
    if is_ploi then
        local row = build_row(object, places_of_interest_columns, osm_type)
        tables.places_of_interest:add_row(row)
    end
    return is_ploi
end


-- Fill previously created tables

function osm2pgsql.process_node(object)
    if extract_public_transport(object, 'node') then return end
    extract_places_of_interest(object, 'node')
end

function osm2pgsql.process_way(object)
    if extract_public_transport(object, 'way') then return end
    if extract_paths(object) then return end
    extract_places_of_interest(object, 'way')
end

function osm2pgsql.process_relation(object)
    if extract_public_transport(object, 'relation') then return end
    extract_places_of_interest(object, 'relation')
end


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


-- Check whether a given tag table contains at least one column from a given columns table
function contains_tag_from_columns(tags, columns)
    for _, entry in pairs(columns) do
        if tags[entry.column] ~= nil then
            return true
        end
    end
    return false
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