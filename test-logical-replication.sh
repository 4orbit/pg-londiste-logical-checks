#!/bin/sh -ex

export PATH=/usr/pgsql-11/bin:$PATH
pg_ctl stop -D /tmp/master || echo "ok"
pg_ctl stop -D /tmp/standby || echo "ok"
rm -rf /tmp/master
rm -rf /tmp/standby

# setup master
initdb -D /tmp/master
cat <<EOF >>/tmp/master/postgresql.conf
port=15432
wal_level = logical
EOF

pg_ctl  -D /tmp/master start
pgbench -i -s 10 -p 15432

# setup standby
initdb -D /tmp/standby
cat <<EOF >>/tmp/standby/postgresql.conf
port=25432
EOF

pg_ctl  -D /tmp/standby start
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

# prepare pub
psql -p 15432 <<SQL
    CREATE PUBLICATION pub_pgbench FOR TABLE pgbench_accounts;
SQL

# init sub
psql -p 25432 <<SQL
    CREATE SUBSCRIPTION sub_pgbench CONNECTION 'host=/tmp port=15432 dbname=postgres' PUBLICATION pub_pgbench;
SQL

# add table on master
#psql -p 15432 <<SQL
#    create table new_table(id serial, data text);
#    ALTER PUBLICATION pub_pgbench ADD table new_table;
#    insert into new_table(data) values ('test -1');
#SQL
#
## add table on standby
#psql -p 25432 <<SQL
#    create table new_table(id serial, data text);
#    ALTER SUBSCRIPTION sub_pgbench REFRESH PUBLICATION;
#SQL

while [[ `psql -p 25432 -Atc "select count(*) from pg_subscription_rel where srsubstate <> 'r'"` != [0] ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"

pgbench -T 120 -c 40 -p 15432

while [[ `psql -p 25432 -Atc "select count(*) from pg_subscription_rel where srsubstate <> 'r'"` != [0] ]]; do
    sleep 1
    echo "wait sync"
done
echo "sync complete"


#rm -rf /tmp/standby_backup
#pg_basebackup -p 25432 -D /tmp/standby_backup --checkpoint=fast
#
#
## kill standby and change data on master
#kill -9 $(cat /tmp/standby/postmaster.pid | head -n 1)
#pgbench -i -s 100 -p 15432
#
## start standby from backup
#rm -rf /tmp/standby
#mv /tmp/standby_backup /tmp/standby
#pg_ctl start -D /tmp/standby -w
#
## make check: insert new data
#psql -p 15432 <<SQL
#    insert into new_table(data) values ('test logical');
#SQL
#
## wait sync on replica
#while [[ `psql -p 25432 -Atc "select count(*) from pg_subscription_rel where srsubstate <> 'r'"` != [0] ]]; do
#    sleep 1
#    echo "wait sync"
#done
#echo "sync complete"
#
## no data on standby:
#psql -p 25432 <<SQL
#    select * from new_table;
#SQL
