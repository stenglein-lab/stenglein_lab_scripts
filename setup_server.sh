#!/bin/bash
#
# Setup a Stenglein lab analysis server
#
# This is based on How I setup the cctsi-103 server
# goal: create a re-usable script for server setup
#
# This done on cctsi-103 server with Ubuntu 16.04
# 
# 5/17/2017
# Mark Stenglein

# TODO: convert this to make/snakemake format


# kludgy way to only execute part of the script
if [ "dont_do_this_part_already_done" = "XXX" ]
then

echo "bla bla bla" > /dev/null

# just keep moving this else down to keep adding to what will get done
else



# update packages
echo "Going to run Ubuntu updates. Press enter to continue."
read x
sudo apt-get update
sudo apt-get upgrade

# setup UFW firewall
# see: https://www.digitalocean.com/community/tutorials/initial-server-setup-with-ubuntu-16-04
sudo ufw app list
echo "should see: Available applications: OpenSSH"

sudo ufw allow OpenSSH

echo "check UFW status"
sudo ufw status

echo "going to enable UFW firewall (press Y to continue)"
sudo ufw enable

echo "check UFW status: should be active w/ OpenSSH connections enabled"
sudo ufw status

# install msmtp for emailing...
sudo apt install -y msmtp msmtp-mta

msmtprc=$(cat <<'END_MSMTPRC'
account default 
host smtp.colostate.edu
port 25
from `hostname -a`@colostate.edu
auth off
syslog LOG_MAIL
END_MSMTPRC
)

echo "Adding the following lines to /etc/msmtprc"
echo "$msmtprc" 
sudo echo "$msmtprc" > /etc/msmtprc 


# install HDF5 libs, for utils like h5dump
sudo apt-get update
sudo apt-get install -y libhdf5-serial-dev
sudo apt install -y hdf5-tools

# Now, install LAMP: Apache, MySQL, PHP (precursors for webmin)
# see: https://www.digitalocean.com/community/tutorials/how-to-install-linux-apache-mysql-php-lamp-stack-on-ubuntu-16-04

# install Apache
sudo apt-get update
sudo apt-get install -y apache2

echo "Checking Apache Config.  Should see 'Sytnax OK' as output"
sudo apache2ctl configtest

echo "going to enable web traffic through firewall"
# sudo ufw app list

sudo ufw allow in "Apache Full"

echo "if you navigate to this host's hostname in a browser you should see a default Apache page"


# MySQL
echo "setting up MySQL"
sudo apt-get install -y mysql-server

echo "securing MySQL"
echo "answer No to first 2 questions (VALIDATE PASSWORD PLUGIN and Change the password for root and Yes to the rest.  See:"
echo "https://www.digitalocean.com/community/tutorials/how-to-install-linux-apache-mysql-php-lamp-stack-on-ubuntu-16-04"
mysql_secure_installation


# setup mysql databases for stenglein lab servers

# First, move mysql db to /home, and populate it with NCBI Taxonomy info
# 
# Move mysql data directory
# see:
# https://stackoverflow.com/questions/1795176/how-to-change-mysql-data-directory
#
echo "-----------------------------------------------------------"
echo "going to do some major work on my sql databases"
echo "(move data directory, create new dbs and users, etc.)"
echo " "
read -p " *** Are you sure you want to continue? ***   (y or Y to continue): " -n 1 -r
echo " "
if [[ $REPLY =~ ^[Yy]$ ]]
then
   echo moving mysql data directory
   echo "see: https://stackoverflow.com/questions/1795176/how-to-change-mysql-data-directory"

   echo "sudo /etc/init.d/mysql stop"
   sudo /etc/init.d/mysql stop

   echo "sudo cp -R -p /var/lib/mysql /home/databases"
   sudo cp -R -p /var/lib/mysql /home/databases

   echo "need to edit my.cnf file.  "
   echo "change datadir from /var/lib/mysql to /home/databases/mysql"
   # TODO: could use sed to to this

   echo going to vi now
   echo enter to continue
   read x

   sudo vi /etc/mysql/mysql.conf.d/mysqld.cnf 

   echo "now need to edit AppArmour config file"
   echo "Look for lines beginning with /var/lib/mysql. Change /var/lib/mysql to reflect the new path."

   echo going to vi now
   echo enter to continue
   read x
   sudo vi /etc/apparmor.d/usr.sbin.mysqld

   echo "sudo /etc/init.d/apparmor reload"
   sudo /etc/init.d/apparmor reload

   echo "sudo /etc/init.d/mysql restart"
   sudo /etc/init.d/mysql restart

   # now, create a new database and a corresponding user for NCBI_Taxonomy usage
   echo "going go create a new table in mysql and an NCBI_Taxonomy user.  Will be prompted for (mysql) root user password"
   echo enter to continue
   read x

   sql_file=/tmp/sql_setup_$$

cat > $sql_file << SQL_FILE

CREATE DATABASE NCBI_Taxonomy;
CREATE USER 'NCBI_Taxonomy'@'localhost' IDENTIFIED BY 'NCBI_Taxonomy';
GRANT ALL PRIVILEGES ON NCBI_Taxonomy.* TO 'NCBI_Taxonomy'@'localhost';
GRANT FILE on *.* to 'NCBI_Taxonomy'@'localhost';

FLUSH PRIVILEGES;

SQL_FILE

   cat $sql_file | mysql -u root -p

   rm $sql_file

   
else
   echo "not going to do anything to mysql dbs..."
fi


# PHP
echo "installing PHP"
sudo apt-get install -y php libapache2-mod-php php-mcrypt php-mysql

# echo "give PHP files priority over HTML"



# Webmin
echo "going to install Webmin"
echo "see: https://www.digitalocean.com/community/tutorials/how-to-install-webmin-on-ubuntu-16-04"
echo "  "
echo "going to edit /etc/apt/sources.list with vi.  Add the following lines to the bottom of that file and save:"
echo " "
echo "# for webmin"
echo "deb http://download.webmin.com/download/repository sarge contrib" 
echo " "
echo "# for R packages
echo "deb http://cran.rstudio.com/bin/linux/ubuntu xenial/"
echo " "
echo "<enter> to continue: "
read x
sudo vi /etc/apt/sources.list

echo "adding Webmin PGP key"
echo "should see 'OK' after adding key"
wget http://www.webmin.com/jcameron-key.asc
sudo apt-key add jcameron-key.asc

# refresh w/ Webmin info
sudo apt-get update

# actually install Webmin
echo "installing webmin."
echo "you should see output at end like: Webmin install complete. You can now login to https://..."
sudo apt-get install -y webmin


# allow Webmin through firewall
sudo ufw allow 10000

echo "now you can navigate to this https://<this_hostname>:10000 to login to webmin"

# SSL certificate setup for webmin to avoid ugly warning 
# can't use Let's Encrypt to do SSL cert. because CSU servers behind a firewall that won't let let's encrypt connect to the server :<
# echo "follow instructions at: https://www.digitalocean.com/community/tutorials/how-to-install-webmin-on-ubuntu-16-04"
# echo "   to setup SSL certificate that won't give error"


# setup .bashrc of my user

bashrc=$(cat <<'END_BASHRC'

# use vi to do command line editing
set -o vi

# don't overwrite files
set -o noclobber

#--------
# aliases
#--------
# Prevent accidentally clobbering files.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'

# ls aliases
alias ll='ls -l --color'
alias ls='ls -hF --color'         # colors
alias lk='ls -lSrh'               # sort by size, biggest last
alias lt='ls -ltr --color'        # sort by date, most recent last

alias more='less'
export PAGER=less

export PERL5LIB="${PERL5LIB}:/home/apps/stenglein_lab_scripts"

PATH="${PATH}:/home/apps/bin:/home/apps/stenglein_lab_scripts"

END_BASHRC
)

echo "Adding the following lines to ~/.bashrc:"
echo "$bashrc" 
echo "$bashrc" >> ~/.bashrc

echo "Adding the following lines to /etc/skel/.bashrc"
sudo echo "$bashrc" >> /etc/skel/.bashrc

# Setup .vimrc for my user
# vim defaults

vimrc=$(cat <<'END_VIMRC'
set ai
set sw=3
set ic
set tabstop=3
syntax on
END_VIMRC
)
echo "Adding the following lines to ~/.vimrc:"
echo "$vimrc" 
echo "$vimrc" >> ~/.vimrc


# to update local repo from remote: run: git fetch; git pull

# Setup /home/apps folder
cd /home
sudo mkdir apps
cd apps
sudo chown -R `whoami` .
mkdir bin

# clone stenglein lab scripts dir from github
cd /home/apps/
git clone https://github.com/stenglein-lab/stenglein_lab_scripts.git 

# download unzip
sudo apt-get install -y zip unzip


# get secure-apt key for installing R
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9

# install R
echo "going to install R"
echo "enter to continue"
read x
sudo apt-get update
sudo apt-get install -y r-base
# libcurl needed for some bioconductor packages...
sudo apt-get install -y libcurl4-openssl-dev
# libxml2 needed for some bioconductor packages...
sudo apt-get install -y libxml2-dev
# 
sudo apt-get install -y libssl-dev

# install bioconductor (does this do anything?) 
sudo R -e 'source("https://bioconductor.org/biocLite.R"); biocLite()'

# Possible TODO: Have users install R packages in a user-specific way?
# TODO: install specific R packages, and do so in a way so that they are available for all users
sudo R -e 'install.packages("tidyverse")'
# packages needed for ballgown
sudo R -e 'source("https://bioconductor.org/biocLite.R"); biocLite(c("ballgown", "RSkittleBrewer", "genefilter", "dplry", "devtools"))'



# install RStudio Server:
# NOTE: should check that this is latest version
echo installing RStudio Server
cd /home/apps
sudo apt-get update
# secure apt for this install 
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
sudo apt-get install gdebi-core
curl -O https://download2.rstudio.org/rstudio-server-1.1.463-amd64.deb
sudo gdebi rstudio-server-1.1.463-amd64.deb
# open up UFW for the RStudio port
sudo ufw allow 8787
cd /home/apps

# install Shiny Server
# NOTE: check that this is latest version
cd /home/apps
# install shiny itself
sudo R -e 'install.packages("shiny")'
curl -O https://download3.rstudio.org/ubuntu-14.04/x86_64/shiny-server-1.5.9.923-amd64.deb
sudo gdebi shiny-server-1.5.9.923-amd64.deb
# open up firewall for the shiny server prt
sudo ufw allow 3838
# this configures shiny server to allow individual users to setup their own shiny server apps 
sudo /opt/shiny-server/bin/deploy-example user-dirs

# install Java
sudo apt-get update
sudo apt-get install -y default-jdk
echo "running java -version: should work"
echo "enter to continue"
read x
echo "java -version"
java -version
echo "enter to continue"
read x

# install pip (python package manager)
sudo apt-get install -y python-pip


# Setup /home/databases folder
cd /home
sudo mkdir databases
sudo chown mdstengl databases
cd databases



# install various apps

# download bowtie2
echo installing bowtie2
cd /home/apps
curl -OL  https://sourceforge.net/projects/bowtie-bio/files/bowtie2/2.3.4.3/bowtie2-2.3.4.3-linux-x86_64.zip
unzip bowtie2-2.3.4.3-linux-x86_64
cd bowtie2-2.3.4.3-linux-x86_64
cp bowtie2* /home/apps/bin
cd /home/apps

# install libtbb, necessary for bowtie2
sudo apt-get install libtbb-dev -y

# install cutadapt
echo "installing cutadapt.  Note, won't install to /home/apps/bin"
echo enter to continue
read x
sudo pip install --upgrade cutadapt

# install FastQC
echo "going to install FastQC.  Note: may be a newer version: check website: https://www.bioinformatics.babraham.ac.uk/projects/fastqc"
echo "enter to continue"
read x
cd /home/apps
curl -O https://www.bioinformatics.babraham.ac.uk/projects/fastqc/fastqc_v0.11.5.zip
unzip fastqc_v0.11.5.zip
cd FastQC
chmod +x fastqc
cd /home/apps/bin
# create a symbolic link to the fastqc executable 
ln -s ../FastQC/fastqc fastqc

# install galaxy
echo "going to install galaxy"
gal_ver="release_17.01"
echo "NOTE: going to install version: $gal_Ver"
echo "could update in future by running git checkout & git pull.   See: https://galaxyproject.org/admin/get-galaxy/ "
echo enter to continue
cd /home/apps
git clone -b $gal_ver https://github.com/galaxyproject/galaxy.git
cd galaxy
# allow galaxy port 8080 through firewall
sudo ufw allow 8080
cd config
cp galaxy.ini.sample galaxy.ini
echo "edit galaxy.ini and add the following line: "
echo "host = 0.0.0.0"
echo enter to edit
read x
vi galaxy.ini
cd /home/apps

# to run galaxy:
# echo: to run galaxy: sh run.sh
# sh run.sh

# install canu assembler
echo install canu assembler
wget https://github.com/marbl/canu/releases/download/v1.5/canu-1.5.Linux-amd64.tar.xz
tar xvf canu-1.5.Linux-amd64.tar.xz
# TODO: install canu executables somehow?
cd /home/apps

# install gnuplot
echo install gnuplot
sudo apt-get update
sudo apt-get install -y gnuplot

# install graphmap
echo install graphmap
cd /home/apps
echo install graphmap
git clone https://github.com/isovic/graphmap.git
cd graphmap
make modules
make
cp bin/Linux-x64/graphmap /home/apps/bin
cd /home/apps

# install htop
echo install htop
sudo apt-get update
sudo apt-get install -y htop

# install iotop 
sudo apt-get install -y iotop -y

# install nanopolish
echo install nanopolish
cd /home/apps
git clone --recursive https://github.com/jts/nanopolish.git
cd nanopolish/
make
cp nanopolish nanopolish_test /home/apps/bin
cd scripts
cp * /home/apps/bin
cd /home/apps

# install albacore 
echo install albacore
cd /home/apps
curl -O https://americas.oxfordnanoportal.com/software/analysis/ont_albacore-2.3.3-cp35-cp35m-manylinux1_x86_64.whl
sudo -H pip3 install ont_albacore-2.3.3-cp35-cp35m-manylinux1_x86_64.whl


# install cmake (SPAdes,etc dependency)
echo "install cmake (SPAdes,etc dependency)"
sudo apt-get update
sudo apt install -y cmake

# install SPADES
echo install SPADES
cd /home/apps
wget http://cab.spbu.ru/files/release3.10.1/SPAdes-3.10.1.tar.gz
tar -xzf SPAdes-3.10.1.tar.gz
cd SPAdes-3.10.1
PREFIX=/home/apps ./spades_compile.sh
cd /home/apps

# install bwa
echo install bwa
cd /home/apps
git clone https://github.com/lh3/bwa.git
cd bwa; make
cp bwa /home/apps/bin
cd /home/apps

# install parallel
echo install parallel
sudo apt-get install -y parallel

# install samtools
echo install samtools
cd /home/apps
wget https://github.com/samtools/samtools/releases/download/1.5/samtools-1.5.tar.bz2
bunzip2 samtools-1.5.tar.bz2
tar xvf samtools-1.5.tar
cd samtools-1.5/
./configure --prefix=/home/apps
make
make install
cd /home/apps

# install BBTools
echo install BBTools
cd /home/apps
wget https://downloads.sourceforge.net/project/bbmap/BBMap_37.36.tar.gz
tar xvzf BBMap_37.36.tar.gz
# TODO: figure out how to install?

# install cd-hit
echo install cd-hit
cd /home/apps
# wget https://github.com/weizhongli/cdhit/releases/download/V4.6.8/cd-hit-v4.6.8-2017-0621-source.tar.gz
git clone https://github.com/weizhongli/cdhit.git
cd cdhit
make
cp cd-hit* /home/apps/bin
cd cd-hit-auxtools
make
cp cd-hit-dup cd-hit-lap read-linker /home/apps/bin
cd /home/apps

# install gmap
echo install gmap - NOTE: gmap is frequently updated.  Should probably update this URL
echo enter to continue
read x
curl -O http://research-pub.gene.com/gmap/src/gmap-gsnap-2018-07-04.tar.gz
tar xvf gmap-gsnap-2018-07-04.tar.gz
cd gmap-2018-07-04
./configure --prefix=/home/apps
make
make check
make install

# install HiSat
echo install HiSat
cd /home/apps
wget ftp://ftp.ccb.jhu.edu/pub/infphilo/hisat2/downloads/hisat2-2.1.0-Linux_x86_64.zip
unzip hisat2-2.1.0-Linux_x86_64.zip
cd hisat2-2.1.0
cp hisat2* /home/apps/bin
cd /home/apps

# install gffread, used, e.g., to convert GFF->GTF format
# see: http://ccb.jhu.edu/software/stringtie/gff.shtml
echo install gffread
cd /home/apps
curl -O http://ccb.jhu.edu/software/stringtie/dl/gffread-0.9.12.Linux_x86_64.tar.gz
tar xvf gffread-0.9.12.Linux_x86_64.tar.gz 
cp gffread-0.9.12.Linux_x86_64/gffread bin
cd /home/apps


# install BLAST+
echo install BLAST+
cd /home/apps
wget ftp://ftp.ncbi.nlm.nih.gov/blast/executables/blast+/LATEST/ncbi-blast-2.6.0+-x64-linux.tar.gz
tar xvzf ncbi-blast-2.6.0+-x64-linux.tar.gz
cd ncbi-blast-2.6.0+/bin
cp * /home/apps/bin
cd /home/apps

# install mafft
echo install mafft
cd /home/apps
wget http://mafft.cbrc.jp/alignment/software/mafft-7.310-with-extensions-src.tgz
tar xvzf mafft-7.310-with-extensions-src.tgz
cd mafft-7.310-with-extensions/core
echo it is necessary to edit the Makefile to install to non-default location.
echo see: http://mafft.cbrc.jp/alignment/software/installation_without_root.html
echo going to vi Makefile
echo enter to continue
read x
# TODO: could change Makefile w/ sed...
vi Makefile
make clean
make
make install
cd /home/apps


# install sratoolkit
echo install sratoolkit
cd /home/apps
wget https://ftp-trace.ncbi.nlm.nih.gov/sra/sdk/current/sratoolkit.current-ubuntu64.tar.gz
tar xvzf sratoolkit.current-ubuntu64.tar.gz
cd sratoolkit.2.8.2-1-ubuntu64
cp bin/* /home/apps/bin
cp -R bin/ncbi /home/apps/bin
cd /home/apps

# Install BOOST
sudo apt-get install -y libboost-all-dev


# install RAPSearch
# TODO: Couldn't get rapsearch to work... --> some obscure BOOST issue.  Use diamond instead?
### echo install RAPSearch
### cd /home/apps
### wget https://downloads.sourceforge.net/project/rapsearch2/RAPSearch2.24_64bits.tar.gz
### tar xvzf RAPSearch2.24_64bits.tar.gz
### cd RAPSearch2.24_64bits/
### ./install
### cp bin/* /home/apps/bin
### cd /home/apps

# install diamond 
echo install diamond 
cd /home/apps
curl -OL https://github.com/bbuchfink/diamond/releases/download/v0.9.24/diamond-linux64.tar.gz
tar xzf diamond-linux64.tar.gz
mv diamond bin 

### # install NFS client
### sudo apt-get update
### sudo apt-get install -y nfs-common

# install centrifuge
echo install centrifuge
cd /home/apps
git clone https://github.com/infphilo/centrifuge
cd centrifuge
make
make install prefix=/home/apps
cd /home/apps

# install BEAST
echo install BEAST
cd /home/apps
wget https://github.com/CompEvol/beast2/releases/download/v2.4.7/BEAST.v2.4.7.Linux.tgz
tar xvf BEAST.v2.4.7.Linux.tgz
# TODO: install BEAST to /home/apps possible?

## # install Vienna RNA package - requirement of centroidfold
## echo install Vienna RNA package - requirement of centroidfold
## cd /home/apps
## wget https://www.tbi.univie.ac.at/RNA/download/sourcecode/2_3_x/ViennaRNA-2.3.5.tar.gz
## tar xvf ViennaRNA-2.3.5.tar.gz
## cd ViennaRNA-2.3.5
## ./configure --prefix=/home/apps
## make
## make install
## cd /home/apps
## # note: got an error during make and make install.  Worked?
## # Could use pre-built binaries...

# install centroid fold
echo install centroid fold
cd /home/apps
wget https://github.com/satoken/centroid-rna-package/releases/download/v0.0.15/centroid-rna-package-0.0.15-linux-x86_64.zip
unzip centroid-rna-package-0.0.15-linux-x86_64.zip 
cd centroid-rna-package-0.0.15-linux-x86_64/
cp centroid_* /home/apps/bin
cd /home/apps

# install stringtie
echo install stringtie
cd /home/apps
curl -O http://ccb.jhu.edu/software/stringtie/dl/stringtie-1.3.4c.Linux_x86_64.tar.gz
tar xvf stringtie-1.3.4c.Linux_x86_64.tar.gz
cp stringtie-1.3.4c.Linux_x86_64/stringtie bin
cd /home/apps

# install jmodeltest 2
echo install jmodeltest 2
cd /home/apps
wget https://github.com/ddarriba/jmodeltest2/files/157117/jmodeltest-2.1.10.tar.gz
tar xvf jmodeltest-2.1.10.tar.gz
# TODO: possible to install to /home/apps/bin?  

## # install khmer using pip
## echo install khmer using pip
## pip install --upgrade pip
## pip install --install-option="--prefix=/home/apps" khmer
## # TODO: did this even work?

# install freebayes
echo install freebayes
cd /home/apps
git clone --recursive git://github.com/ekg/freebayes.git
cd freebayes
make
cp bin/freebayes bin/bamleftalign /home/apps/bin
cd /home/apps

# install lofreq
echo install lofreq
cd /home/apps
curl -O -L https://github.com/CSB5/lofreq/raw/master/dist/lofreq_star-2.1.3.1_linux-x86-64.tgz
tar xvf lofreq_star-2.1.3.1_linux-x86-64.tgz
cp lofreq_star-2.1.3.1/bin/* /home/apps/bin
cd /home/apps

# install BEAGLE - used by MrBayes, BEAST, PhyML etc
cd /home/apps
git clone --depth=1 https://github.com/beagle-dev/beagle-lib.git
cd beagle-lib
./autogen.sh
./configure --prefix=/home/apps
make install

# install MrBayes
echo install MrBayes
cd /home/apps
wget https://downloads.sourceforge.net/project/mrbayes/mrbayes/3.2.6/mrbayes-3.2.6.tar.gz
tar xvf mrbayes-3.2.6.tar.gz
cd mrbayes-3.2.6/src
autoconf
./configure --enable-mpi=yes --prefix=/home/apps --with-beagle=/home/apps/
make
make install
cd /home/apps

# install muscle
echo install muscle
cd /home/apps
wget http://www.drive5.com/muscle/downloads3.8.31/muscle3.8.31_i86linux64.tar.gz
tar xvf muscle3.8.31_i86linux64.tar.gz
mv muscle3.8.31_i86linux64 /home/apps/bin

# install PhyML
echo install PhyML
echo "note: the developers of PhyML would like your name and email.  Please go to: http://www.atgc-montpellier.fr/phyml/binaries.php"
cd /home/apps
wget https://github.com/stephaneguindon/phyml/archive/v3.3.20170530.tar.gz
cd phyml-3.3.20170530/
./autogen.sh 
make
cp phyml-mpi /home/apps/bin
cd /home/apps

# install quast
echo install quast
cd /home/apps
wget https://downloads.sourceforge.net/project/quast/quast-4.5.tar.gz
tar -xzf quast-4.5.tar.gz
cd quast-4.5
./install_full.sh
# TODO: install to /home/apps/bin possible?

# install STAR aligner
echo install STAR aligner
cd /home/apps
git clone https://github.com/alexdobin/STAR.git
cd STAR/source
make STAR
cp STAR /home/apps/bin

# install trimal
echo install trimal
cd /home/apps
git clone https://github.com/scapella/trimal.git
cd trimal/source
make
cp readal trimal statal /home/apps/bin
cd /home/apps/bin


# khmer
# htslib

# setup cron jobs
# TODO: could do this on 1 'master database server' and then rsync to others...
echo going to setup cron jobs
echo first, will edit crontab via crontab -e
echo after editing, simply quit and save to save helpful usage info in the crontab
echo enter to continue
read x
crontab -e

echo "now, going to add some additional lines to crontab"

cron_file=/tmp/new_cronjobs_$$

cat > $cron_file << CRON_FILE
PATH=/home/mdstengl/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/home/apps/bin
MAILTO=mark.stenglein@colostate.edu
# on the 1st of every month at 2 AM update NCBI Taxonomy database and update mysql version of it
0 2 1 * * /home/databases/NCBI_Taxonomy/fetch_NCBI_Taxonomy_db
# on the 1st of every month at 4 AM update NR/NT databases and indexes
0 4 1 * * /home/databases/nr_nt/fetch_nr_nt
CRON_FILE

crontab -l -u `whoami` | cat - $cron_file | crontab -u `whoami` -

rm $cron_file

# setup rsync.conf file
echo "going to setup rsyncd.conf file so that automatic backups to stengleinlab201 can occur"
echo "enter to continue"
read x

rsync_file=/tmp/rsyncd.conf.$$

cat > $rsync_file << RSYNC_FILE
[home]
   path = /home/
   comment = home
   read only = yes
   use chroot = no
   # not same as
   # auth users = mstenglein
   hosts allow = stengleinlab201.cvmbs.colostate.edu

RSYNC_FILE

cat $rsync_file >> ~/rsyncd.conf

rm $rsync_file

echo "done setting up rsyncd.conf"
echo "make sure to go to 201 server and setup backup from that end."
echo enter to continue
read x



# add some default paths to /etc/skel/.profile
skel_paths_file=/tmp/skel.paths.$$

cat > $skel_paths_file << SKEL_PROFILE

# include /home/apps/bin in path 
PATH="$PATH:/home/apps/bin:/home/apps/stenglein_lab_scripts"

# add BLASTDB environmental variable and point to /home/databases/nr_nt 
BLASTDB="/home/databases/nr_nt/"

SKEL_PROFILE

# add some paths to default .profile in /etc/skel
sudo cat $skel_paths_file >> /etc/skel/.profile

rm $skel_paths_file




# setup PERL modules
# need DBI perl module for some of the tax pipeline scripts
echo "going to use cpan to install perl DBI module"
echo "enter to continue"
read x
sudo cpan DBI
# install DBD-Mysql module...
sudo apt-get -y install libdbd-mysql-perl

# setup pip3, to install snakemake,
sudo apt-get update
sudo apt-get -y install python3-pip

# install snakemake via pip
sudo pip3 install snakemake

# install biopython via pip
sudo pip3 install biopython

# install hmmer, necessary for RepeatMasker
echo install hmmer
cd /home/apps
wget http://eddylab.org/software/hmmer3/3.1b2/hmmer-3.1b2-linux-intel-x86_64.tar.gz
tar xvf hmmer-3.1b2-linux-intel-x86_64.tar.gz 
cd hmmer-3.1b2-linux-intel-x86_64/
cp binaries/* /home/apps/bin
cd /home/apps

# install TRF
echo "need to install TRF (tandem repeat finder) as a RepeatMasker dependency"
echo "download the trf executable from here: http://tandem.bu.edu/trf/trf.download.html"
echo "and install it into /home/apps/bin"
echo "and make sure it has executable permissions"
echo "enter when that task is complete"
read x

# install RepeatMasker
echo install RepeatMasker
cd /home/apps
wget http://www.repeatmasker.org/RepeatMasker-open-4-0-7.tar.gz
tar xvf RepeatMasker-open-4-0-7.tar.gz
cd RepeatMasker/
echo "going to run the interactive RepeatMasker configure script now..."
echo enter to continue
read x
perl ./configure 

# install perl module needed by RepeatMasker :<
echo "install perl module needed by RepeatMasker"
cpan Text::Soundex

# install bcftools
echo install bcftools
cd /home/apps
git clone git://github.com/samtools/htslib.git
git clone git://github.com/samtools/bcftools.git
cd bcftools/
autoheader && autoconf && ./configure --prefix=/home/apps
make
make install
cd /home/apps

# install tabix, for bgzip, etc.
sudo apt-get update
sudo apt -y install tabix

# install prokka
# see: https://github.com/tseemann/prokka#installation
sudo apt-get update
sudo apt-get -y install libdatetime-perl libxml-simple-perl libdigest-md5-perl bioperl
# NOTE: bioperl installs, via bioperl-run dependency , a bunch of 
#   out of date versions of apps, like samtools...!!
# To remove them, we'll remove the bioperl-run package:
sudo apt-get purge bioperl-run
sudo apt-get autoremove
# continue w/ prokka install
cd /home/apps
git clone https://github.com/tseemann/prokka.git
cd prokka
bin/prokka --setupdb
cd /home/apps

# setup barrnap
# basic rRNA predictor
echo installing barrnap
cd /home/apps
wget https://github.com/tseemann/barrnap/archive/0.8.tar.gz
tar xvf 0.8.tar.gz
cd /home/apps

# install Ruby
sudo apt-get update
sudo apt-get -y install ruby-full


# install mummer
echo installing mummer
cd /home/apps
# TODO: check for new version...
# curl -L tells curl to follow redirects.  This github URL was redirecting to an AWS address...
curl -L -O https://github.com/mummer4/mummer/releases/download/v4.0.0beta2/mummer-4.0.0beta2.tar.gz 
tar xvf mummer-4.0.0beta2.tar.gz 
cd mummer-4.0.0beta2
./configure --prefix=/home/apps
make
make install
cd /home/apps

# install circos & dependencies (a bunch of perl modules)
# TODO: check for new version
echo installing circos
cd /home/apps
curl -O http://circos.ca/distribution/circos-0.69-6.tgz
tar xvf circos-0.69-6.tgz 
cd circos-0.69-6/
# install cpanminus for easier perl module installation
sudo apt-get update
sudo apt-get -y install cpanminus
sudo cpanm Clone Config::General Font::TTF::Font GD GD::Polyline Math::Bezier Math::Round Math::VecStat 
sudo cpanm Params::Validate Readonly Regexp::Common SVG Set::IntSpan Statistics::Basic Text::Format
cd /home/apps

# install bc (calculator)
sudo apt-get update
sudo apt-get -y install bc

# install EMBOSS
# this installs a bunch of programs to /usr/bin -> not wildly happy w/ that...
# sudo apt-get update
# sudo apt-get install -y emboss

# install minimap2
echo installing minimap2
cd /home/apps
git clone https://github.com/lh3/minimap2
cd minimap2 
make
cp minimap2 /home/apps/bin
cd /home/apps

# install seqtk
echo installing seqtk
cd /home/apps
git clone https://github.com/lh3/seqtk.git
cd seqtk/
make
cp seqtk ../bin
cd /home/apps

# install nextflow
cd /home/apps
curl -s https://get.nextflow.io | bash
cp nextflow /home/apps/bin
# TODO: install vim nextflow syntax highlighting: see: https://github.com/LukeGoodsell/nextflow-vim

# install HTSeq
cd /home/apps
sudo apt-get install build-essential python2.7-dev python-numpy python-matplotlib python-pysam python-htseq

# TODO: setup shiny server and install shiny, tidyverse, other packages...

# this library needed to compile ggforce in R
sudo apt-get install libudunits2-dev


# seqtk
cd /home/apps
git clone https://github.com/lh3/seqtk.git
cd seqtk
make
cp seqtk ../bin
cd /home/apps

# install tbl2asn
cd /home/apps
curl -OL ftp://ftp.ncbi.nih.gov/toolbox/ncbi_tools/converters/by_program/tbl2asn/linux64.tbl2asn.gz
gunzip  linux64.tbl2asn.gz
chmod +x linux64.tbl2asn
mv linux64.tbl2asn bin
cd bin
ln linux64.tbl2asn tbl2asn
cd /home/apps


# database setups: see script setup_databases.sh

# TODO: make this a snakemake or make?

# SysAdmin TODO:
# MegaCli (RAID analysis)
# setup RAID monitoring
# i.e. setup cron jobs

fi
