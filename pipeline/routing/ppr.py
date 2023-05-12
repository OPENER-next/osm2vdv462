import psycopg2
from psycopg2.extras import DictCursor
import requests
import json
import os

def truncateTables(conn, cur):
    cur.execute('TRUNCATE TABLE paths')
    cur.execute('TRUNCATE TABLE paths_elements_ref')
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


def insertPGSQL(cur,insertRoutes,start, stop ,path_counter):
    # PPR can return multiple possible paths for one connection:
    for route in insertRoutes:
        path = route["path"]
        edges = route["edges"]
        # distance = route["distance"]
        relation_id = stop["relation_id"]

        insertPathsElementsRef(cur, edges, path_counter)
        insertPath(cur, relation_id, start["IFOPT"], stop["IFOPT"], path)


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