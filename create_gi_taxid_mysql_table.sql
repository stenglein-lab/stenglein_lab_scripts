use NCBI_Taxonomy;
CREATE TABLE `gi_taxid_map_temp` (
   `gi` INTEGER, 
   `taxid` INTEGER,
   PRIMARY KEY (`gi`)
);
load data infile '/home/databases/NCBI_Taxonomy/gi_taxid.dmp' into table gi_taxid_map_temp;
drop table gi_taxid_map;
rename TABLE gi_taxid_map_temp TO gi_taxid_map;


