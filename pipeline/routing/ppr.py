import psycopg2
from psycopg2.extras import DictCursor
import requests
import json
import os


# Describes a node (e.g. a Quay or Entrance) from the edges table
class MainNode:
  def __init__(self, relation_id, IFOPT, lat, lng, type):
    self.relation_id = relation_id
    self.IFOPT = IFOPT
    self.lat = lat
    self.lng = lng
    self.type = type



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

    *_, lastEdge = edges # get the last element of the list

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
            # also insert the node at the end of the edge to also get crossing nodes, ...
            # the last node should not be included, otherwise elevator nodes would be included in the path
            if edge["to_node_osm_id"] != 0 and edge != lastEdge:
                insertPathsElementsRefSQL(cur, pathId, 'N', edge["to_node_osm_id"])


def insertPathLink(cur, relation_id, pathLink, from_id, to_id, from_type, to_type, level):
    edgeList = [f"{edge[0]} {edge[1]}" for edge in pathLink]
    linestring = "LINESTRING(" + ",".join(edgeList) + ")"

    # use 'INSERT INTO ... ON CONFLICT DO NOTHING' to avoid duplicate entries
    # 'RETURNING path_id' returns the generated path_id
    cur.execute(
        '''
        INSERT INTO path_links (stop_area_relation_id, edge, geom, level)
        VALUES (%s, (%s, %s, %s, %s), ST_GeomFromText(%s, 4326), %s)
        ON CONFLICT DO NOTHING RETURNING path_id
        ''',
        (relation_id, from_id, to_id, from_type, to_type, linestring, level)
    )

    path_id = cur.fetchone()
    if path_id:
        return path_id[0] # return the path_id generated by the database
    else:
        return None


def insertAccessSpaces(cur, currentEdge, previousEdge, relation_id):
    edge_type = currentEdge["edge_type"]
    street_type = currentEdge["street_type"]

    if edge_type == "elevator" or street_type == "stairs" or street_type == "escalator" or currentEdge["incline"] != None:
        # going into the elevator/stairs/escalator/ramp: use level from the previous edge
        # this might fail if two special cases are directly connected (e.g. escalator to stairs)
        current_level = previousEdge["level"] or 0
    else:
        # normal case: use current level
        current_level = currentEdge["level"] or 0

    # create unique id for the access space, that will be filled into the 'IFOPT' column
    # 'STOP_PLACE'_'OSM_NODE_ID':'LEVEL_IF_EXISTS'
    newIFOPT = str(relation_id) + "_" + str(currentEdge["from_node_osm_id"]) + ":" + (str(current_level) if current_level != None else "")
    geomString = "POINT(" + str(currentEdge["path"][0][0]) + " " + str(currentEdge["path"][0][1]) + ")"

    try:
        # use INSERT INTO ... ON CONFLICT DO NOTHING to avoid duplicate entries
        cur.execute(
            'INSERT INTO access_spaces (node_id, relation_id, "level", "IFOPT", geom) VALUES (%s, %s, trim_scale(%s), %s, ST_GeomFromText(%s, 4326)) ON CONFLICT DO NOTHING',
            (currentEdge["from_node_osm_id"], relation_id, current_level, newIFOPT, geomString)
        )
    except Exception as e:
        exit(e)

    return newIFOPT, current_level


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

    edge_type = currentEdge["edge_type"]
    previousEdge_type = previousEdge["edge_type"]
    street_type = currentEdge["street_type"]
    previous_street_type = previousEdge["street_type"]

    # transition from one edge_type to another
    if (edge_type != previousEdge_type):
        if (edge_type == "elevator" or previousEdge_type == "elevator"): return True
        if (edge_type == "cycle_barrier" or previousEdge_type == "cycle_barrier"): return True
        if (edge_type == "entrance"):
            door_type = currentEdge["door_type"]
            if (door_type != "no" and door_type != None): return True
        if (previousEdge_type == "entrance"):
            door_type = previousEdge["door_type"]
            if (door_type != "no" and door_type != None): return True
    # transition from one street_type to another
    if (street_type != previous_street_type):
        if (street_type == "stairs" or previous_street_type == "stairs"): return True
        if (street_type == "escalator" or previous_street_type == "escalator"): return True
        if (street_type == "moving_walkway" or previous_street_type == "moving_walkway"): return True
    # transition on ramps
    if (currentEdge["incline"] != previousEdge["incline"]): return True

    return False


def createPathNetwork(cur, edges, fromNode, toNode):
    relation_id = fromNode.relation_id
    edgeIter = iter(edges)
    firstEdge = next(edgeIter)

    previousEdge = firstEdge
    previousIFOPT = fromNode.IFOPT
    previousType = fromNode.type

    fromLevel = firstEdge["level"] or 0
    toLevel = firstEdge["level"] or 0

    # create 'pathLink' that will be inserted into the database
    # - a pathLink is a list of two nodes (stop_area_element and/or access_space), that are connected by one or multiple edges
    # - an edge can consist multiple nodes (polyline)
    pathLink = firstEdge["path"]
    pathLinkEdges = [firstEdge] # all edges that are part of the pathLink

    for edge in edgeIter:
        if requiresAccessSpace(previousEdge, edge): # checks whether the given parameters need the creation of an access space
            newIFOPT, toLevel = insertAccessSpaces(cur, edge, previousEdge, relation_id) # returns a newly created IFOPT for the access space and the level of the access space
            newType = "ACCESS_SPACE"
            pathId = insertPathLink(cur, relation_id, pathLink, previousIFOPT, newIFOPT, previousType, newType, toLevel - fromLevel)
            if pathId:
                insertPathsElementsRef(cur, pathId, pathLinkEdges)
            pathLink = edge["path"] # create a new pathLink consisting of the current edge
            pathLinkEdges = [edge]
            previousIFOPT = newIFOPT
            previousType = newType
            fromLevel = toLevel
        else:
            # append all but the first node of the edge, because the first node is the same as the last node of the previous edge
            # use extend, because there can be multiple nodes in the edge (polyline)
            pathLink.extend(edge["path"][1:])
            pathLinkEdges.append(edge)
            toLevel = edge["level"] or 0

        previousEdge = edge

    # the last part of the path is not inserted yet (between the last access space and the stop_area_element)
    pathId = insertPathLink(cur, relation_id, pathLink, previousIFOPT, toNode.IFOPT, previousType, toNode.type, toLevel - fromLevel)

    if pathId:
        insertPathsElementsRef(cur, pathId, pathLinkEdges)


def insertPGSQL(cur, insertRoutes, fromNode, toNode):
    # PPR can return multiple possible paths for one connection:
    for route in insertRoutes:
        edges = route["edges"]
        createPathNetwork(cur, edges, fromNode, toNode)


def makeRequest(url, payload, fromNode, toNode):
    payload["start"]["lat"] = fromNode.lat
    payload["start"]["lng"] = fromNode.lng
    payload["destination"]["lat"] = toNode.lat
    payload["destination"]["lng"] = toNode.lng

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
        "include_full_path": False,
        "include_steps": False,
        "include_steps_path": False,
        "include_edges": True,
        "include_statistics": False,
        'allow_match_with_no_level': True,
        'no_level_penalty': 0
    }

    try:
        with open("profiles/include_accessible.json", "r") as f:
            payload["profile"] = json.load(f)
    except Exception as e:
        conn.close()
        exit(e)

    stop_area_edges = None

    try:
        # get all relevant edges for stop areas
        # SRID in POSTGIS is default set to 4326 --> x = lng, Y = lat
        cur.execute('''
            SELECT relation_id,
            "start_IFOPT", ST_X(start_geom) as start_lng, ST_Y(start_geom) as start_lat, start_type,
            "end_IFOPT", ST_X(end_geom) as end_lng, ST_Y(end_geom) as end_lat, end_type
            FROM stop_area_edges
        ''')
        stop_area_edges = result = cur.fetchall()

    except Exception as e:
        conn.close()
        exit(e)

    for edge in stop_area_edges:
        fromNode = MainNode(
            edge["relation_id"],
            edge["start_IFOPT"],
            edge["start_lat"],
            edge["start_lng"],
            edge["start_type"]
        )

        toNode = MainNode(
            edge["relation_id"],
            edge["end_IFOPT"],
            edge["end_lat"],
            edge["end_lng"],
            edge["end_type"]
        )

        json_data = makeRequest(url, payload, fromNode, toNode)
        insertPGSQL(cur, json_data["routes"], fromNode, toNode)

        conn.commit()

    print("Finished receiving paths from PPR!")

    conn.close()


if __name__ == "__main__":
    main()
