#!/bin/sh -ex

while [[ `psql -p 25432 -Atc "select count(*) from pg_subscription_rel where srsubstate <> 'r'"` != [0] ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"

