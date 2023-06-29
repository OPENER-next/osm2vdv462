import psycopg2
from psycopg2.extras import DictCursor
import requests
import json
import os

def truncateTables(conn, cur):
    cur.execute('TRUNCATE TABLE paths')
    cur.execute('TRUNCATE TABLE paths_elements_ref')
    cur.execute('TRUNCATE TABLE path_links')
    cur.execute('TRUNCATE TABLE access_spaces')
    conn.commit()


def insertPath(cur, relation_id, dhid_from, dhid_to, path):
    stepList = [f"{step[0]} {step[1]}" for step in path]
    linestring = "LINESTRING(" + ",".join(stepList) + ")"
    cur.execute(
        'INSERT INTO paths (stop_area_relation_id, "from", "to", geom) VALUES (%s, %s, %s, ST_GeomFromText(%s, 4326))',
        (relation_id, dhid_from, dhid_to, linestring)
    )


def insertPathsElementsRef(cur, edges, path_counter):
    # ways with id == 0 are additional edges generated from PPR, that are part of the path
    # those are not inserted into the paths_elements_ref database, because they won't add additional tags to the path
    # crossed ways (negative osm way id) are included, but only the absolute value (the crossed way) is inserted
    for edge in edges:
        osm_way_id = abs(edge["osm_way_id"])
        if osm_way_id != 0:
            cur.execute(
                "INSERT INTO paths_elements_ref (path_id, osm_type, osm_id) VALUES (%s, %s, %s)",
                (path_counter, 'W', osm_way_id)
            )


def insertPathLink(cur, pathLink, id_from, id_to):
    edgeList = [f"{edge[0]} {edge[1]}" for edge in pathLink]
    linestring = "LINESTRING(" + ",".join(edgeList) + ")"
    
    if id_from < id_to:
        smaller_node_id = id_from
        bigger_node_id = id_to
    else:
        smaller_node_id = id_to
        bigger_node_id = id_from
        
    # use INSERT INTO ... ON CONFLICT DO NOTHING to avoid duplicate entries
    cur.execute(
        'INSERT INTO path_links (path_id, smaller_node_id, bigger_node_id, geom) VALUES (%s, %s, %s, ST_GeomFromText(%s, 4326)) ON CONFLICT DO NOTHING',
        (1, smaller_node_id, bigger_node_id, linestring)
    )
    

def insertAccessSpaces(cur, osm_id, level, DHID, tags, geom):
    geomString = "POINT(" + str(geom[0]) + " " + str(geom[1]) + ")"
    try:
        # use INSERT INTO ... ON CONFLICT DO NOTHING to avoid duplicate entries
        cur.execute(
            'INSERT INTO access_spaces (osm_id, "level", "IFOPT", tags, geom) VALUES (%s, %s, %s, %s, ST_GeomFromText(%s, 4326)) ON CONFLICT DO NOTHING',
            (osm_id, level, DHID, tags, geomString)
        )
    except Exception as e:
        exit(e)
    return 1


def requiresAccessSpace(currentEdge, previousEdge):
    # access spaces are required, when there is:
    #   - 1) a transition from a edge_type to another (e.g. from 'footway' to 'elevator')
    #   - 2) a transition from a street_type to another (e.g. from a 'footway' to 'stairs')
    
    # Logical structure of the id generation for access spaces:
    # level:                       0                   1                     0                   -1                     0
    # OSM:            (id_1) ---Footway--- (id_2) ---Stairs--- (id_3) ---Elevator--- (id_3) ---Footway--- (id_4) ---Escalator--- (id_5)
    # access spaces:  ----------- [X] --------------- [X] ----------------- [X] ---------------- [X] ----------------- [X] ------------
    # id(id,level):   ----------------- (id_2,NULL) --------- (id_3,1) ----------- (id_3,-1) --------- (id_4,NULL) --------------------
    
    
    # Special cases:
    
    # Elevators:
    # Their 'osm_way_id', 'from_node_osm_id' and 'to_node_osm_id' are the same. One elevator can have multiple levels, and therefore multiple access spaces.
    # So the elevators access spaces are identified by the level of the previous edge when stepping into the elevator,
    # and the level of the current edge when stepping out of the elevator.
    
    # Escalators:
    # Their level is dependent on the direction of the path. So the access spaces are identified by the level of the previous edge when going into the escalator,
    # and the level of the current edge when going out of the escalator.
    
    # Stairs:
    # They always have the same level, regardless of the direction. So the access spaces are identified by the level of the previous edge when going into the stairs,
    # and the level of the current edge when going out of the stairs.
    
    special_edge_types = ["elevator"]
    special_street_types = ["stairs", "escalator", "moving_walkway"]
    
    edge_type = currentEdge["edge_type"]
    previousEdge_type = previousEdge["edge_type"]
    street_type = currentEdge["street_type"]
    previous_street_type = previousEdge["street_type"]
    
    if( # 1) transition from one edge_type to another
        edge_type != previousEdge_type and
        (edge_type in special_edge_types or previousEdge_type in special_edge_types)
        )\
        or( # 2) transition from one street_type to another
            street_type != previous_street_type and
            (street_type in special_street_types or previous_street_type in special_street_types)
        ):
        return True
    return False
        

def createAccessSpace(cur, currentEdge, previousEdge, relation_id):
    edge_type = currentEdge["edge_type"]
    street_type = currentEdge["street_type"]
    
    if edge_type == "elevator" or street_type == "stairs" or street_type == "escalator":
        # going into the elevator/stairs/escalator: use level from the previous edge
        # this might fail if two special cases are directly connected (e.g. escalator to stairs)
        current_level = previousEdge["level"]
    else:
        # normal case: use current level
        current_level = currentEdge["level"]
    
    # create unique id for the access space, that will be filled into the 'IFOPT' column
    # 'STOP_PLACE'_'OSM_NODE_ID':'LEVEL_IF_EXISTS'
    newDHID = str(relation_id) + "_" + str(currentEdge["from_node_osm_id"]) + ":" + (str(current_level) if current_level != None else "")
    
    insertAccessSpaces(cur, currentEdge["from_node_osm_id"], current_level, newDHID, None, currentEdge["path"][0])
    
    return newDHID


def createPathNetwork(cur, path, edges, relation_id, dhid_from, dhid_to):
    accessSpaceCreated = False
    edgeIter = iter(edges)
    firstEdge = next(edgeIter)
    previousEdge = firstEdge
    previousDHID = dhid_from
    
    # create 'pathLink' that will be inserted into the database
    # - a pathLink is a list of two nodes (stop_area_element and/or access_space), that are connected by one or multiple edges
    # - an edge can consist multiple nodes (polyline)
    pathLink = firstEdge["path"]
    
    for i in range(len(edges) - 1): # the first edge is already handled
        edge = next(edgeIter)
        
        if requiresAccessSpace(previousEdge, edge): # checks whether the given parameters need the creation of an access space
            newDHID = createAccessSpace(cur, edge, previousEdge, relation_id) # returns a newly created DHID for the access space
            insertPathLink(cur, pathLink, previousDHID, newDHID)
            pathLink = edge["path"] # create a new pathLink consisting of the current edge
            previousDHID = newDHID
            accessSpaceCreated = True
        else:
            # append all but the first node of the edge, because the first node is the same as the last node of the previous edge
            # use extend, because there can be multiple nodes in the edge (polyline)
            pathLink.extend(edge["path"][1:])

        previousEdge = edge
        
    if not accessSpaceCreated:
        # no access space was created, so insert the full PPR path between the two stop_area_elements
        insertPathLink(cur, path, dhid_from, dhid_to)
    

def insertPGSQL(cur, insertRoutes, start, stop, path_counter):
    # PPR can return multiple possible paths for one connection:
    for route in insertRoutes:
        path = route["path"]
        edges = route["edges"]
        # distance = route["distance"]
        relation_id = stop["relation_id"]

        insertPathsElementsRef(cur, edges, path_counter)
        insertPath(cur, relation_id, start["IFOPT"], stop["IFOPT"], path)
        
        createPathNetwork(cur, path, edges, relation_id, start["IFOPT"], stop["IFOPT"])


def makeRequest(url, payload, start, stop):
    payload["start"]["lat"] = start["lat"]
    payload["start"]["lng"] = start["lng"]
    payload["destination"]["lat"] = stop["lat"]
    payload["destination"]["lng"] = stop["lng"]

    try:
        response = requests.post(url, json=payload)
    except Exception as e:
        exit(e)

    if response.status_code != 200:
        exit(f'Request failed with status code {response.status_code}: {response.text}')

    return response.json()


def main():
    # Connect to PostgreSQL database
    conn = psycopg2.connect(
        host = os.environ['host_postgis'],
        port = os.environ['port_postgis'],
        database = os.environ['db_postgis'],
        user = os.environ['user_postgis'],
        password = os.environ['password_postgis']
    )

    # Open a cursor to perform database operations
    cur = conn.cursor(cursor_factory=DictCursor)
    
    # Truncate paths and paths_elements_ref table (delete all rows from previous runs)
    truncateTables(conn, cur)

    url = 'http://' + os.environ['host_ppr'] + ':8000/api/route'
    payload = {
        "start": {
        },
        "destination": {
        },
        "include_infos": True,
        "include_full_path": True,
        "include_steps": True,
        "include_steps_path": False,
        "include_edges": True,
        "include_statistics": True
    }

    try:
        with open("profiles/include_accessible.json", "r") as f:
            payload["profile"] = json.load(f)
    except Exception as e:
        conn.close()
        exit(e)
    
    stop_area_elements = {}

    try:
        # get all relevant stop areas
        # SRID in POSTGIS is default set to 4326 --> x = lng, Y = lat
        cur.execute(
            'SELECT stop_area_osm_id as relation_id, category, id as "IFOPT", ST_X(geom) as lng, ST_Y(geom) as lat FROM stop_area_elements'
        )
        result = cur.fetchall()
        for entry in result:
            # create a dictionary where the keys are the relation_ids of the stop_areas
            # and the values are a list of dictionaries containing all elements of that area
            if entry["relation_id"] not in stop_area_elements:
                stop_area_elements[entry["relation_id"]] = [dict(entry)]
            else:
                stop_area_elements[entry["relation_id"]].append(dict(entry))

    except Exception as e:
        conn.close()
        exit(e)

    path_counter = 1

    # Iterate through all stop areas to get the path between the elements of this area.
    # 'entry' is the relation_id of the stop_area
    for entry in stop_area_elements:
        elements = stop_area_elements[entry]
        
        for i in range(len(elements) - 1):
            for ii in range(i + 1 , len(elements)):
                
                json_data = makeRequest(url,payload,elements[i],elements[ii])
                insertPGSQL(cur,json_data["routes"],elements[i],elements[ii],path_counter)
                path_counter = path_counter + 1
                
                # generate bidirectional paths:
                # It is questionable if special cases exist, where paths between stops/quays are different
                # and whether it justifies double the path computation with PPR.
                # see the github discussion: https://github.com/OPENER-next/osm2vdv462/pull/1#discussion_r1156836297
                json_data = makeRequest(url,payload,elements[ii],elements[i])
                insertPGSQL(cur,json_data["routes"],elements[ii],elements[i],path_counter)
                path_counter = path_counter + 1

        conn.commit()
        
    print("Finished receiving paths from PPR!")

    conn.close()


if __name__ == "__main__":
    main()