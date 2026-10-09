#!/usr/bin/env bash
# Live view of replica-set member states, refreshed every second.
# Run it in a second terminal (or split screen) while a test script runs,
# so students can watch primaries fail, elections happen and nodes rejoin.
# Works with mongo:4.4 and 5.0+. Stop with Ctrl-C.
NODES=(mongo1 mongo2 mongo3)
G=$'\e[1;32m'; S=$'\e[1;34m'; R=$'\e[1;31m'; Y=$'\e[1;33m'; N=$'\e[0m'
JS='rs.status().members.forEach(x => print(x.name.split(":")[0].padEnd(9) + (x.health ? x.stateStr : "DOWN")))'

while true; do
  out=""
  for n in "${NODES[@]}"; do         # ask any node that is still alive (mongosh or legacy mongo shell)
    out=$(docker exec "$n" sh -c 'exec "$(command -v mongosh || command -v mongo)" --quiet --eval "$1"' _ "$JS" 2>/dev/null) \
      && [ -n "$out" ] && break
    out=""
  done
  clear
  printf '\n  Replica set rs0        %s\n  ------------------------------\n' "$(date +%H:%M:%S)"
  if [ -n "$out" ]; then
    echo "$out" | sed -e "s/PRIMARY/${G}PRIMARY${N}/" -e "s/SECONDARY/${S}SECONDARY${N}/" \
                      -e "s/DOWN/${R}DOWN${N}/" -e "s/STARTUP2/${Y}STARTUP2${N}/" \
                      -e "s/RECOVERING/${Y}RECOVERING${N}/" -e "s/ROLLBACK/${Y}ROLLBACK${N}/" \
                | sed 's/^/  /'
  else
    echo "  (no node reachable, or replica set not initiated yet)"
  fi
  sleep 1
done
