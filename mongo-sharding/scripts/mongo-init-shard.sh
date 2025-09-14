#!/bin/bash

###
# Инициализируем бд
###

docker compose exec -T mongos mongosh <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF


docker compose exec -T mongos mongosh <<EOF
use somedb
db.helloDoc.countDocuments()
EOF