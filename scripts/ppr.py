import psycopg2
import requests
import json

def insertSteps(cur, path, path_counter, path_counter_individual, relation_id):
    for step in path:
        cur.execute(
            "INSERT INTO steps_ppr (relation_id, path_id, path_id_individual, step) VALUES (%s, %s, %s, ST_Point(%s, %s, 4326))",
            (relation_id, path_counter, path_counter_individual, step[0], step[1])
        )

def insertDHIDs(cur, path_counter, dhid_from, dhid_to):
    cur.execute(
        'INSERT INTO paths_dhid (path_id, "from", "to") VALUES (%s, %s, %s)',
        (path_counter, dhid_from, dhid_to)
    )

def insertOSMWayIDs(cur, edges, path_counter):
    osm_way_ids = []
    for edge in edges:
        osm_way_id = abs(edge["osm_way_id"])
        # currently also the crossed ways are included (negative way osm id)
        if osm_way_id != 0 and osm_way_id not in osm_way_ids:
            osm_way_ids.append(osm_way_id)
            cur.execute(
                "INSERT INTO paths_osm_id (path_id, osm_id) VALUES (%s, %s)",
                (path_counter, osm_way_id)
            )

def main():
    # Connect to PostgreSQL database
    conn = psycopg2.connect(
        host = "localhost",
        port = "5432",
        database = "osm2vdv462",
        user = "admin",
        password = "admin"
    )

    # Open a cursor to perform database operations
    cur = conn.cursor()

    url = 'http://0.0.0.0:9042/api/route'
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

    stop_places = []

    try:
        # SRID in POSTGIS is default set to 4326 --> x = lng, Y = lat
        cur.execute(
                'SELECT relation_id, "IFOPT", osm_id, osm_type, ST_X(ST_Centroid(geom)), ST_Y(ST_Centroid(geom)), node_id FROM topology_node_to_osm_element'
            )
        result = cur.fetchall()
        for node in result:
            print(f"Append stop place relation: {node[0]}, IFOPT: {node[1]}, node: {node[6]}, lat: {node[5]}, lng: {node[4]}")
            stop_places.append({"relation_id": node[0], "IFOPT": node[1], "osm_id": node[2], "osm_type": node[3], "node": node[6], "lat": node[5], "lng": node[4]})

    except Exception as e:
        conn.close()
        exit(e)

    cur.execute(
        "DROP TABLE IF EXISTS steps_ppr"
    )

    cur.execute(
        """
            CREATE TABLE steps_ppr (
            id SERIAL PRIMARY KEY,
            relation_id INT,
            path_id_individual INT,
            path_id INT,
            step GEOMETRY )
        """
    )

    cur.execute(
        "DROP TABLE IF EXISTS paths_dhid"
    )

    cur.execute(
        """
            CREATE TABLE paths_dhid (
            path_id INT,
            "from" text,
            "to" text )
        """
    )

    cur.execute(
        "DROP TABLE IF EXISTS paths_osm_id"
    )

    cur.execute(
        """
            CREATE TABLE paths_osm_id (
            path_id INT,
            osm_id int )
        """
    )

    path_counter = 0
    
    print("retrieving paths ...")

    # Iterate through all stop_places to get the path between all of them.
    for i in range(len(stop_places) - 1):
        for ii in range(i + 1 , len(stop_places)):
            payload["start"]["lat"] = stop_places[i]["lat"]
            payload["start"]["lng"] = stop_places[i]["lng"]
            payload["destination"]["lat"] = stop_places[ii]["lat"]
            payload["destination"]["lng"] = stop_places[ii]["lng"]

            try:
                response = requests.post(url, json=payload)
            except Exception as e:
                exit(e)

            if response.status_code != 200:
                exit(f'Request failed with status code {response.status_code}: {response.text}')

            json_data = json.loads(response.text)
            
            path_counter_individual = 0

            # PPR can return multiple possible paths for one connection:
            for route in json_data["routes"]:
                path = route["path"]
                edges = route["edges"]
                distance = route["distance"]
                relation_id = stop_places[ii]["relation_id"]
                
                insertOSMWayIDs(cur, edges, path_counter)
                
                insertSteps(cur, path, path_counter, path_counter_individual, relation_id)
                
                insertDHIDs(cur, path_counter, stop_places[i]["IFOPT"], stop_places[ii]["IFOPT"])
                
                path_counter = path_counter + 1
                
                insertOSMWayIDs(cur, edges, path_counter)

                # make steps bidirectional
                insertSteps(cur, reversed(path), path_counter, path_counter_individual, relation_id)

                insertDHIDs(cur, path_counter, stop_places[ii]["IFOPT"], stop_places[i]["IFOPT"])
                    
                path_counter = path_counter + 1
                path_counter_individual = path_counter_individual + 1
            
            conn.commit()

    if path_counter == 0:
        conn.close()
        exit("No paths found!")
        
    print("finished!")

    conn.close()


if __name__ == "__main__":
    main()