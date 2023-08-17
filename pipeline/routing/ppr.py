import psycopg2
from psycopg2.extras import DictCursor
import requests
import json
import os

def truncateTables(conn, cur):
    cur.execute('TRUNCATE TABLE paths_elements_ref')
    cur.execute('TRUNCATE TABLE path_links')
    cur.execute('TRUNCATE TABLE access_spaces')
    conn.commit()


def insertPathsElementsRefSQL(cur, pathId, osm_type, osm_id):
    cur.execute(
        "INSERT INTO paths_elements_ref (path_id, osm_type, osm_id) VALUES (%s, %s, %s) ON CONFLICT DO NOTHING",
        (pathId, osm_type, osm_id)
    )

def insertPathsElementsRef(cur, pathId, edges):
    # ways with id == 0 are additional edges generated from PPR, that are part of the path
    # those are not inserted into the paths_elements_ref database, because they won't add additional tags to the path
    # crossed ways (negative osm way id) are included, but only the absolute value (the crossed way) is inserted

    for edge in edges:
        if edge["edge_type"] == "crossing":
            # insert the osm way id of the crossing
            # include the nodes coming from and going to the crossing
            if edge["crossing_type"] == "generated":
                # crossing, that is not part of the OSM data, generated by PPR
                # from and to node are the same, except when one of the nodes is zero
                # (e.g. when the path starts or ends at a connection generated by PPR)
                if edge["from_node_osm_id"] != 0:
                    insertPathsElementsRefSQL(cur, pathId, 'N', edge["from_node_osm_id"])
                else:
                    insertPathsElementsRefSQL(cur, pathId, 'N', edge["to_node_osm_id"])
                insertPathsElementsRefSQL(cur, pathId, 'W', abs(edge["osm_way_id"]))
            else:
                # crossing, that is part of the OSM data
                if edge["from_node_osm_id"] != edge["to_node_osm_id"]:
                    # from and to node are different, so the crossing is a way
                    insertPathsElementsRefSQL(cur, pathId, 'N', edge["from_node_osm_id"])
                    insertPathsElementsRefSQL(cur, pathId, 'N', edge["to_node_osm_id"])
                else:
                    # from and to node are the same, so the crossing is a node
                    # negative value of osm_way_id is the id of the node
                    insertPathsElementsRefSQL(cur, pathId, 'N', edge["from_node_osm_id"])
                insertPathsElementsRefSQL(cur, pathId, 'W', abs(edge["osm_way_id"]))
        elif edge["edge_type"] == "elevator":
            # insert the osm node id of the elevator
            # negative value of osm_way_id is the id of the node
            insertPathsElementsRefSQL(cur, pathId, 'N', abs(edge["osm_way_id"]))
        else:
            # "normal" case (footpath and street): insert the osm way id of the edge
            if edge["osm_way_id"] != 0:
                insertPathsElementsRefSQL(cur, pathId, 'W', abs(edge["osm_way_id"]))


def insertPathLink(cur, relation_id, pathLink, id_from, id_to, level):
    edgeList = [f"{edge[0]} {edge[1]}" for edge in pathLink]
    linestring = "LINESTRING(" + ",".join(edgeList) + ")"
        
    # use 'INSERT INTO ... ON CONFLICT DO NOTHING' to avoid duplicate entries
    # 'RETURNING path_id' returns the generated path_id
    cur.execute(
        'INSERT INTO path_links (stop_area_relation_id, start_node_id, end_node_id, geom, level) VALUES (%s, %s, %s, ST_GeomFromText(%s, 4326), %s) ON CONFLICT DO NOTHING RETURNING path_id',
        (relation_id, id_from, id_to, linestring, level)
    )
    
    path_id = cur.fetchone()
    if path_id:
        return path_id[0] # return the path_id generated by the database
    else:
        return None
    

def insertAccessSpaces(cur, currentEdge, previousEdge, relation_id):
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
    geomString = "POINT(" + str(currentEdge["path"][0][0]) + " " + str(currentEdge["path"][0][1]) + ")"
    
    try:
        # use INSERT INTO ... ON CONFLICT DO NOTHING to avoid duplicate entries
        cur.execute(
            'INSERT INTO access_spaces (osm_id, relation_id, "level", "IFOPT", tags, geom) VALUES (%s, %s, trim_scale(%s), %s, %s, ST_GeomFromText(%s, 4326)) ON CONFLICT DO NOTHING',
            (currentEdge["from_node_osm_id"], relation_id, current_level, newDHID, None, geomString)
        )
    except Exception as e:
        exit(e)

    return newDHID, current_level


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
        

def createPathNetwork(cur, edges, relation_id, dhid_from, dhid_to):
    edgeIter = iter(edges)
    firstEdge = next(edgeIter)
    previousEdge = firstEdge
    previousDHID = dhid_from
    fromLevel = firstEdge["level"]
    toLevel = firstEdge["level"]
    
    # create 'pathLink' that will be inserted into the database
    # - a pathLink is a list of two nodes (stop_area_element and/or access_space), that are connected by one or multiple edges
    # - an edge can consist multiple nodes (polyline)
    pathLink = firstEdge["path"]
    pathLinkEdges = [firstEdge] # all edges that are part of the pathLink
    
    for edge in edgeIter:
        if requiresAccessSpace(previousEdge, edge): # checks whether the given parameters need the creation of an access space
            newDHID, toLevel = insertAccessSpaces(cur, edge, previousEdge, relation_id) # returns a newly created DHID for the access space and the level of the access space
            pathId = insertPathLink(cur, relation_id, pathLink, previousDHID, newDHID, toLevel - fromLevel)
            if pathId:
                insertPathsElementsRef(cur, pathId, pathLinkEdges)
            pathLink = edge["path"] # create a new pathLink consisting of the current edge
            pathLinkEdges = [edge]
            previousDHID = newDHID
            fromLevel = toLevel
        else:
            # append all but the first node of the edge, because the first node is the same as the last node of the previous edge
            # use extend, because there can be multiple nodes in the edge (polyline)
            pathLink.extend(edge["path"][1:])
            pathLinkEdges.append(edge)
            toLevel = edge["level"]

        previousEdge = edge
    
    # the last part of the path is not inserted yet (between the last access space and the stop_area_element 'dhid_to')
    pathId = insertPathLink(cur, relation_id, pathLink, previousDHID, dhid_to, toLevel - fromLevel)
        
    if pathId:
        insertPathsElementsRef(cur, pathId, pathLinkEdges)
    

def insertPGSQL(cur, insertRoutes, start, stop):
    # PPR can return multiple possible paths for one connection:
    for route in insertRoutes:
        edges = route["edges"]
        # distance = route["distance"]
        relation_id = stop["relation_id"]

        createPathNetwork(cur, edges, relation_id, start["IFOPT"], stop["IFOPT"])


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
    
    # Truncate tables (delete all rows from previous runs)
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

    # Iterate through all stop areas to get the path between the elements of this area.
    # 'entry' is the relation_id of the stop_area
    for entry in stop_area_elements:
        elements = stop_area_elements[entry]
        
        for i in range(len(elements) - 1):
            for ii in range(i + 1 , len(elements)):
                
                if elements[i]["IFOPT"] == elements[ii]["IFOPT"]:
                    # skip if two entries with the same DHID are in the same stop_area
                    # this should not happen after the platform merging in the stop_places step of the pipeline
                    print(f"WARNING: Two entries with the same DHID ({elements[i]['IFOPT']})! Ignoring ...")
                    continue
                
                json_data = makeRequest(url,payload,elements[i],elements[ii])
                insertPGSQL(cur,json_data["routes"],elements[i],elements[ii])
                
                # generate bidirectional paths:
                # It is questionable if special cases exist, where paths between stops/quays are different
                # and whether it justifies double the path computation with PPR.
                # see the github discussion: https://github.com/OPENER-next/osm2vdv462/pull/1#discussion_r1156836297
                json_data = makeRequest(url,payload,elements[ii],elements[i])
                insertPGSQL(cur,json_data["routes"],elements[ii],elements[i])

        conn.commit()
        
    print("Finished receiving paths from PPR!")

    conn.close()


if __name__ == "__main__":
    main()