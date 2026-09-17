#!/bin/bash
openssl req -x509 -newkey rsa:4096 -keyout server.key -out server.crt -days 365 -nodes
docker cp server.crt http:/Mythic/http/c2_code/server.crt
docker cp server.key http:/Mythic/http/c2_code/server.key