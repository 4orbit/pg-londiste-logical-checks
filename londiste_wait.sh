#!/bin/sh -ex

while [[ `londiste3 $PGDATA_STANDBY/londiste_standby.ini compare 2>&1| grep -c 'checksum'` = 0 ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"
