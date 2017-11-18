#!/bin/bash

# A shell script to setup databases on a Stenglein lab analysis server
# Mark Stenglein 7/24/2017

mkdir /home/databases

# download & process NCBI nr & nt databases
mkdir /home/databases/nr_nt
cd /home/databases/nr_nt

wget https://raw.githubusercontent.com/stenglein-lab/stenglein_lab_scripts/master/fetch_nr_nt
wget https://raw.githubusercontent.com/stenglein-lab/stenglein_lab_scripts/master/build_indexes
chmod +x fetch_nr_nt build_indexes
# download nr & nt databases and build indexes from them...
./fetch_nr_nt

# copy (rsync) some other dbs directly over from stengleinlab-101...
echo "going to copy some already built sequence db indexes from the 101 server."
echo "note that rsync will prompt for passwords for each one."
echo "if you don't enter in the password soon enough, the rsync will fail, and you'll have to re-run it."
echo "enter to continue"
read x

cd /home/databases
rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/NCBI_Taxonomy/ ./NCBI_Taxonomy | tee -a db_rsync_log.txt 
rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/human/ ./human | tee -a db_rsync_log.txt 
# rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/mouse/ ./mouse | tee -a db_rsync_log.txt 
# rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/mosquito/ ./mosquito | tee -a db_rsync_log.txt 
# rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/tick/ ./tick | tee -a db_rsync_log.txt 
# rsync -av --ignore-errors --stats --rsh=ssh stengleinlab101.cvmbs.colostate.edu::databases/snake/ ./snake | tee -a db_rsync_log.txt 

# setup NCBI Taxonomy db in mysql db
echo "import NCBI Taxonomy db into mysql db"
cd /home/databases/NCBI_Taxonomy
./create_gi_taxid_mysql_table
