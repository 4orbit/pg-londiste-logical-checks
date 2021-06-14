#!/bin/sh -ex

export PATH=/usr/pgsql-12/bin:$PATH
export PGDATA_MASTER=/tmp/master
export PGDATA_STANDBY=/tmp/standby

## kill pgqd and londiste proc

kill -9 $(cat $PGDATA_MASTER/londiste_master.pid | head -n 1)
kill -9 $(cat $PGDATA_MASTER/pgqd.pid | head -n 1)
kill -9 $(cat $PGDATA_STANDBY/londiste_standby.pid | head -n 1)

pg_ctl stop -D $PGDATA_MASTER || echo "ok"
pg_ctl stop -D $PGDATA_STANDBY || echo "ok"
rm -rf $PGDATA_MASTER
rm -rf $PGDATA_STANDBY


