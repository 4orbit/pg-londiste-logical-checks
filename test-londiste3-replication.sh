#!/bin/sh -ex

export PATH=/usr/pgsql-11/bin:$PATH
export PGDATA_MASTER=/tmp/master
export PGDATA_STANDBY=/tmp/standby
export PYTHONPATH=/usr/local/lib/python2.7/site-packages:/usr/lib/python2.7/site-packages:/usr/local/lib64/python2.7/site-packages

## kill pgqd and londiste proc
kill -9 $(cat $PGDATA_MASTER/londiste_master.pid | head -n 1)
kill -9 $(cat $PGDATA_MASTER/pgqd.pid | head -n 1)
kill -9 $(cat $PGDATA_STANDBY/londiste_standby.pid | head -n 1)

pg_ctl stop -D $PGDATA_MASTER || echo "ok"
pg_ctl stop -D $PGDATA_STANDBY || echo "ok"
rm -rf $PGDATA_MASTER
rm -rf $PGDATA_STANDBY

# setup master
initdb -D $PGDATA_MASTER
cat <<EOF >>$PGDATA_MASTER/postgresql.conf
port=15432
EOF

pg_ctl  -D $PGDATA_MASTER start
pgbench -i -s 10 -p 15432

# setup standby
initdb -D $PGDATA_STANDBY
cat <<EOF >>$PGDATA_STANDBY/postgresql.conf
port=25432
EOF

pg_ctl  -D $PGDATA_STANDBY start
psql -p 25432 <<SQL
CREATE TABLE public.pgbench_accounts (
    aid integer NOT NULL,
    bid integer,
    abalance integer,
    filler character(84)
)
WITH (fillfactor='100');
ALTER TABLE ONLY public.pgbench_accounts
    ADD CONSTRAINT pgbench_accounts_pkey PRIMARY KEY (aid);
SQL

cat <<EOF >>$PGDATA_MASTER/londiste_master.ini
[londiste3]
job_name = master_table
db = dbname=postgres port=15432
queue_name = replication_queue
logfile = $PGDATA_MASTER/londiste_master.log
pidfile = $PGDATA_MASTER/londiste_master.pid
EOF

londiste3 $PGDATA_MASTER/londiste_master.ini create-root master 'dbname=postgres port=15432'

londiste3 -d $PGDATA_MASTER/londiste_master.ini worker

cat <<EOF >>$PGDATA_STANDBY/londiste_standby.ini
[londiste3]
job_name = standby_table
db = dbname=postgres port=25432
queue_name = replication_queue
logfile = $PGDATA_STANDBY/londiste_standby.log
pidfile = $PGDATA_STANDBY/londiste_standby.pid
EOF

londiste3 $PGDATA_STANDBY/londiste_standby.ini create-leaf standby 'dbname=postgres port=25432' --provider='dbname=postgres port=15432'

londiste3 -d $PGDATA_STANDBY/londiste_standby.ini worker

cat <<EOF >>$PGDATA_MASTER/pgqd.ini
[pgqd]
base_connstr = port=15432
logfile = $PGDATA_MASTER/pgqd.log
pidfile = $PGDATA_MASTER/pgqd.pid
EOF

pgqd -d $PGDATA_MASTER/pgqd.ini

londiste3 $PGDATA_MASTER/londiste_master.ini add-table public.pgbench_accounts

londiste3 $PGDATA_STANDBY/londiste_standby.ini add-table public.pgbench_accounts


while [[ `londiste3 $PGDATA_STANDBY/londiste_standby.ini compare 2>&1| grep -c 'checksum'` = 0 ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"

pgbench -T 120 -c 40 -p 15432

while [[ `londiste3 $PGDATA_STANDBY/londiste_standby.ini compare 2>&1| grep -c 'checksum'` = 0 ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"


