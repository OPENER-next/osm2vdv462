import psycopg2
from psycopg2.extras import DictCursor
import requests
import json
import os

def truncateTables(conn, cur):
    cur.execute('TRUNCATE TABLE paths')
    cur.execute('TRUNCATE TABLE paths_elements_ref')
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


def insertAccessSpaces(cur, osm_id, osm_type, IFOPT, tags, geom):
    geomString = "POINT(" + str(geom[0]) + " " + str(geom[1]) + ")"
    print(f"Inserting access space: {osm_id} , {geomString}")
    try:
        # use INSERT INTO ... ON CONFLICT DO NOTHING to avoid duplicate entries
        cur.execute(
            'INSERT INTO access_spaces (osm_id, osm_type, "IFOPT", tags, geom) VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING',
            (osm_id, osm_type, IFOPT, tags, geomString)
        )
    except Exception as e:
        exit(e)
    return 1


def identifyAccessSpaces(cur, edges):
    # access spaces are identified, when there is:
    #   - 1) a transition from a edge_type to another (e.g. from 'footway' to 'elevator')
    #   - 2) a transition from a street_type to another (e.g. from a 'footway' 'stairs')
    special_street_types = ["stairs", "escalator", "moving_walkway"]
    edge_type = None
    previous_edge_type = None
    
    for i in range(len(edges)):
        osm_way_id = abs(edges[i]["osm_way_id"])
        edge_type = edges[i]["edge_type"]
        street_type = edges[i]["street_type"]
        
        # if the edge is the first edge of the path, there is no previous edge to compare to
        if i == 0:
            previous_edge_type = edge_type
            previous_street_type = street_type
            continue

        # 1) edge_type transition:
        if edge_type != "elevator" and previous_edge_type == "elevator":
            # change from "normal" edge to "elevator" edge --> generate access space
            if insertAccessSpaces(cur, osm_way_id, 'N', None, None, edges[i]["path"][0]):
                print("inserted access space: change from normal to elevator")
                previous_edge_type = edge_type
                previous_street_type = street_type
            continue
        elif edge_type == "elevator" and previous_edge_type != "elevator":
            # change from "elevator" edge to "normal" edge --> generate access space
            if insertAccessSpaces(cur, osm_way_id, 'N', None, None, edges[i]["path"][0]):
                print("inserted access space: change from elevator to normal")
                previous_edge_type = edge_type
                previous_street_type = street_type
            continue
        
        # 2) street_type transition:
        if edge_type == "street" or edge_type == "footway":
            if previous_street_type == "none":  # previous edge was generated from PPR
                continue
            elif street_type not in special_street_types and previous_street_type in special_street_types:
                # change from "normal" edge to "special" edge --> generate access space
                if insertAccessSpaces(cur, osm_way_id, 'N', None, None, edges[i]["path"][0]):
                    print("inserted access space: change from normal to special")
                    previous_edge_type = edge_type
                    previous_street_type = street_type
            elif street_type in special_street_types and previous_street_type not in special_street_types:
                # change from "special" edge to "normal" edge --> generate access space
                if insertAccessSpaces(cur, osm_way_id, 'N', None, None, edges[i]["path"][0]):
                    print("inserted access space: change from special to normal")
                    previous_edge_type = edge_type
                    previous_street_type = street_type
        

def insertPGSQL(cur,insertRoutes,start, stop ,path_counter):
    # PPR can return multiple possible paths for one connection:
    for route in insertRoutes:
        path = route["path"]
        edges = route["edges"]
        # distance = route["distance"]
        relation_id = stop["relation_id"]

        insertPathsElementsRef(cur, edges, path_counter)
        insertPath(cur, relation_id, start["IFOPT"], stop["IFOPT"], path)
        
        identifyAccessSpaces(cur, edges)


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
    for entry in stop_area_elements:
        elements = stop_area_elements[entry]
        
        for i in range(len(elements) - 1):
            for ii in range(i + 1 , len(elements)):
                
                json_data = makeRequest(url, payload,elements[i],elements[ii])
                insertPGSQL(cur,json_data["routes"],elements[i],elements[ii],path_counter)
                path_counter = path_counter + 1
                
                # generate bidirectional paths:
                # It is questionable if special cases exist, where paths between stops/quays are different
                # and whether it justifies double the path computation with PPR.
                # see the github discussion: https://github.com/OPENER-next/osm2vdv462/pull/1#discussion_r1156836297
                json_data = makeRequest(url, payload,elements[ii],elements[i])
                insertPGSQL(cur,json_data["routes"],elements[ii],elements[i],path_counter)
                path_counter = path_counter + 1

        conn.commit()
        
    print("Finished receiving paths from PPR!")

    conn.close()


if __name__ == "__main__":
    main()