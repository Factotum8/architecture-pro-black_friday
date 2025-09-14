#!/bin/bash

###
# Инициализируем бд
###
docker exec -i mongos bash -lc 'mongosh --quiet' <<'JS'
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
JS

docker exec -i mongos bash -lc 'mongosh --quiet' <<'JS'
use somedb
db.helloDoc.countDocuments()
JS