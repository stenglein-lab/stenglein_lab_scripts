use NCBI_Taxonomy;
CREATE TABLE `acc_taxid_map_temp` (
   `acc` CHAR(12), 
   `acc_ver` CHAR(15), 
   `taxid` INTEGER,
   `gi` INTEGER, 
   PRIMARY KEY (`acc`)
);
load data local infile '/home/databases/NCBI_Taxonomy/nucl_gb.accession2taxid' into table acc_taxid_map_temp IGNORE 1 LINES;
load data local infile '/home/databases/NCBI_Taxonomy/prot.accession2taxid' into table acc_taxid_map_temp IGNORE 1 LINES;
drop table if exists acc_taxid_map;
rename TABLE acc_taxid_map_temp TO acc_taxid_map;
