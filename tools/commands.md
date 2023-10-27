# Commands
Some useful tools and commands when working with or developing the export.

- remove all containers, volumes etc. (basically reset docker compose) of the current docker compose project
  ```
  docker compose down --volumes --remove-orphans --rmi local
  ```
  or `docker compose down --volumes --remove-orphans --rmi all` to remove all images

- convert .osm to .pbf using **osmium**
  ```
  osmium cat input_file.osm -o output.osm.pbf
  ```

- format xml using **xmllint**
  ```
  xmllint -format -recover input_file.xml > output_file.xml
  ```

