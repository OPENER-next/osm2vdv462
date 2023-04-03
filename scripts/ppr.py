import psycopg2
import requests
import json
import os

def insertPath(cur, relation_id, dhid_from, dhid_to, path):
    stepList = [f"{step[0]} {step[1]}" for step in path]
    linestring = "LINESTRING(" + ",".join(stepList) + ")"
    cur.execute(
        'INSERT INTO paths (stop_area_relation_id, "from", "to", geom) VALUES (%s, %s, %s, ST_GeomFromText(%s, 4326))',
        (relation_id, dhid_from, dhid_to, linestring)
    )


def insertPathsElementsRef(cur, edges, path_counter):
    osm_way_ids = []
    for edge in edges:
        osm_way_id = abs(edge["osm_way_id"])
        # currently also the crossed ways are included (negative way osm id)
        if osm_way_id != 0 and osm_way_id not in osm_way_ids:
            osm_way_ids.append(osm_way_id)
            cur.execute(
                "INSERT INTO paths_elements_ref (path_id, osm_type, osm_id) VALUES (%s, %s, %s)",
                (path_counter, 'W', osm_way_id)
            )


def makeRequest(url, payload, stop_places, i, ii):
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

    return response.json()


def insertPGSQL(cur,json_data,stop_places,path_counter,i,ii):
    # PPR can return multiple possible paths for one connection:
    for route in json_data["routes"]:
        path = route["path"]
        edges = route["edges"]
        # distance = route["distance"]
        relation_id = stop_places[ii]["relation_id"]
                
        insertPathsElementsRef(cur, edges, path_counter)
        insertPath(cur, relation_id, stop_places[i]["IFOPT"], stop_places[ii]["IFOPT"], path)


def main():
    # Connect to PostgreSQL database
    conn = psycopg2.connect(
        host = os.environ['host_postgis'],
        port = "5432",
        database = "osm2vdv462",
        user = "admin",
        password = "admin"
    )

    # Open a cursor to perform database operations
    cur = conn.cursor()

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

    stop_places = []

    try:
        # SRID in POSTGIS is default set to 4326 --> x = lng, Y = lat
        cur.execute(
                'SELECT stop_area_osm_id, category, id, ST_X(geom), ST_Y(geom) FROM stop_area_elements'
            )
        result = cur.fetchall()
        for node in result:
            stop_places.append({"relation_id": node[0], "category": node[1], "IFOPT": node[2], "osm_id": node[2], "osm_type": node[3], "lat": node[4], "lng": node[3]})

    except Exception as e:
        conn.close()
        exit(e)

    path_counter = 1
    
    print("retrieving paths ...")

    # Iterate through all stop_places to get the path between all of them.
    for i in range(len(stop_places) - 1):
        for ii in range(i + 1 , len(stop_places)):
            
            json_data = makeRequest(url, payload,stop_places,i,ii)
            insertPGSQL(cur,json_data,stop_places,path_counter,i,ii)
            path_counter = path_counter + 1
            
            # generate bidirectional paths:
            json_data = makeRequest(url, payload,stop_places,ii,i)
            insertPGSQL(cur,json_data,stop_places,path_counter,ii,i)
            path_counter = path_counter + 1

    conn.commit()
        
    print("finished!")

    conn.close()


if __name__ == "__main__":
    main()