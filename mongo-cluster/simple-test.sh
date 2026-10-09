#!/usr/bin/env bash
# Simple demo: data written to a MongoDB replica set can still be read
# after a node is turned off.
# Usage: ./simple-test.sh   (same folder as docker-compose.yml; press Enter between steps)
# Works with mongo:4.4 (no AVX needed, fine in VirtualBox) and with 5.0+.
cd "$(dirname "$0")"

B=$'\e[1m'; C=$'\e[36m'; G=$'\e[32m'; N=$'\e[0m'
[ -t 1 ] || { B=; C=; G=; N=; }

step() { echo; echo "${B}=== $* ===${N}"; }
next() { if [ -t 0 ]; then read -r -p "[Enter] " _; fi; }
run()  { echo "${C}\$ $*${N}"; "$@"; }                   # show a command, then run it
js()   { echo "${C}\$ docker exec $1 $MSH school --quiet --eval '$2'${N}"
         docker exec "$1" "$MSH" school --quiet --eval "$2"; }

wait_for()   { local i; for i in $(seq 60); do "$@" && return 0; sleep 1; done
               echo "Timed out. Check 'docker logs mongo1'."; exit 1; }
is_up()      { docker exec "$1" "$MSH" --quiet --eval 'db.adminCommand({ping: 1})' >/dev/null 2>&1; }
is_primary() { [ "$(docker exec "$1" "$MSH" --quiet --eval 'print(db.adminCommand({hello: 1}).isWritablePrimary)' 2>/dev/null)" = true ]; }

READ='db.getMongo().setReadPref("secondaryPreferred"); printjson(db.students.find({}, {_id: 0}).toArray())'

# ------------------------------------------------------------------ setup
step "Setup: start 3 MongoDB nodes and join them into one replica set"
docker compose down -v >/dev/null 2>&1
docker compose up -d
sleep 2
if [ "$(docker inspect -f '{{.State.Running}}' mongo1 2>/dev/null)" != true ]; then
  echo "mongo1 is not running. Last log lines:"; docker logs --tail 5 mongo1
  echo "If you see an AVX warning, use the default mongo:4.4 image (unset MONGO_IMAGE)."
  exit 1
fi
# mongosh ships with MongoDB 5.0+, the older `mongo` shell with 4.4
MSH=$(docker exec mongo1 sh -c 'command -v mongosh >/dev/null && echo mongosh || echo mongo')
for n in mongo1 mongo2 mongo3; do wait_for is_up "$n"; done
docker exec mongo1 "$MSH" --quiet --eval 'rs.initiate({_id: "rs0", members: [
  {_id: 0, host: "mongo1:27017", priority: 2},
  {_id: 1, host: "mongo2:27017"},
  {_id: 2, host: "mongo3:27017"}]})' >/dev/null
wait_for is_primary mongo1
echo "Ready: MongoDB $(docker exec mongo1 "$MSH" --quiet --eval 'print(db.version())')."
echo "mongo1 is the PRIMARY, mongo2 and mongo3 keep copies (SECONDARY)."
next

# ------------------------------------------------------------------ 1
step "1. Insert 3 students on the primary (mongo1)"
js mongo1 'printjson(db.students.insertMany([
  {name: "Anna",  course: "Deep Learning"},
  {name: "Minh",  course: "Deep Learning"},
  {name: "Lukas", course: "Deep Learning"}
], {writeConcern: {w: "majority"}}))'
next

# ------------------------------------------------------------------ 2
step "2. Read from every node: each one has its own copy"
for n in mongo1 mongo2 mongo3; do js "$n" "$READ"; done
next

# ------------------------------------------------------------------ 3
step "3. Turn off mongo1"
run docker stop mongo1
echo "mongo1 can no longer answer:"
js mongo1 "$READ" 2>&1
next

# ------------------------------------------------------------------ 4
step "4. Read again from the nodes that are still running"
for n in mongo2 mongo3; do js "$n" "$READ"; done
echo "${G}${B}All 3 students are still there, although mongo1 is off.${N}"
next

# ------------------------------------------------------------------ 5
step "5. Who is in charge now?"
js mongo2 'rs.status().members.forEach(m => print(m.name + "  " + m.stateStr))'

echo
echo "Bring mongo1 back:  docker start mongo1"
echo "Clean up:           docker compose down -v"
