#!/bin/sh
# -*- mode: sh; -*-
# $Id$

# Script to merge existing gene_descriptions with those from the families
# (where known) into a new table called $new_gene_description, which is a
# complete replacement for the old table.  The script assumes that the family
# and ensembl-core database live in the same server (so you can do joins).

usage="Usage: $0 ens_core_database -h host -u user family_database"
if [ $# -lt 6 ] ; then
    echo $usage
    exit 1
fi

# where mysql lives (or how it can be found, provided PATH is ok):
mysql=mysql
mysql_extra_flags='--batch'

# Database to read existing descriptions from:
read_database=$1; shift

# Name of the table having the existing descriptions (only changes when the
# schema does, really, but also useful during testing/debugging)
read_gene_desc_table='gene_description'

# the table with new descriptions to be created (in the current database):
new_gene_description='merged_gene_description'

# now produce the SQL (with the $variables  being replaced with their values)
# and pipe this as input into mysql:
(cat <<EOF
select count(*) as all_old_descriptions
from $read_database.$read_gene_desc_table gd
where gd.description is not null
  and gd.description not in ('', 'unknown', 'UNKNOWN');

# creating new local gene_description table;
CREATE TABLE $new_gene_description AS 
SELECT *
FROM  $read_database.$read_gene_desc_table gd 
WHERE gd.gene_id IS NULL;

ALTER TABLE $new_gene_description ADD PRIMARY KEY(gene_id);
# inserting existing desc's:
INSERT INTO $new_gene_description 
  SELECT *
  FROM $read_database.$read_gene_desc_table;

# delete anything that looks remotely unknown:
delete from $new_gene_description where description is null;
delete from $new_gene_description where description = '';
delete from $new_gene_description where description = 'unknown';
delete from $new_gene_description where description = 'UNKNOWN';

# selecting all genes from gene, this time properly as 'unknown':
INSERT INTO $new_gene_description
  SELECT id, 'unknown'
  FROM $read_database.gene;
# this will fail on the knowns, as they should; only the 'unknowns' do get
# in.

# give stats:
select count(*) as unknown_old_descriptions
from $new_gene_description
where description = 'unknown';
  
# this table is local to our mysql session, and is deleted automatically
# when it ends
create temporary table tmp_new_descriptions as
  select gd.gene_id, f.description
  from family f, family_members fm, $new_gene_description gd
  where gd.description ='unknown'
   and fm.db_name ='ENSEMBLGENE'
   and fm.db_id = gd.gene_id
   and fm.family = f.internal_id
   and f.description <> 'UNKNOWN';

delete from $new_gene_description where description = 'unknown';

insert into $new_gene_description
  select * from tmp_new_descriptions;

# give new stats:
select count(*) as all_new_descriptions
from $new_gene_description;
EOF
) | $mysql $mysql_extra_flags "$@"
