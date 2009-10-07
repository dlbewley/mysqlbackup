#!/usr/bin/perl -w
################################################################################
# $Id$
# mysqlbackup.pl v1.0 dale@bewley.net 04/22/2000 
#-------------------------------------------------------------------------------
# Based on:
#  http://perl.apache.org/guide/snippets.html#Mysql_Backup_and_Restore_Scripts
#
# Changes to the original
#	o Added feature to get list of databases. Why doesn't DBI->data_sources
#	  work?
#	o Read password from .my.cnf file.
#	o Changed file naming scheme to put year first.
#	o Replaced the rename function with File::Copy (move).
#	o Changed format of mysqldump command. Is it better?
#
# 
# What this script does
# 	1. obtain a list of databases
# 	2. dump all the databases into a separate dump files (these dump files 
# 	are ready for DB restore)
# 	3. backs up the last update log file and creates a new log file
#		Is this the safest way to do that???
#
# Todo
#	o No need to do a full dump each time, add a switch to only rotate
#	  the update log.
#	o Write a log or mail a summary when finished.
#
################################################################################

################################################################################
# Adjust the following for your site.
my $DATABASE	= 'mysql'; # db used to create a handle for listing all db's
#my $HOSTNAME	= 'libdev2';
my $HOSTNAME	= 'localhost';

# See http://www.mysql.com/php/manual.php3?section=Option_files
my $MY_CNF 	= '/root/.my.cnf'; 
my $DBUSER	= '';	# will be read from $MY_CNF
my $DBPASS	= '';	# will be read from $MY_CNF

my $DATA_DIR = "/usr/local/mysql/var";
# name of your update log. probably your hostname
my $UPDATE_LOG_BASE	= "$DATA_DIR/$HOSTNAME";
# where will database backups be dumped?
my $DUMP_DIR  	= "/var/backup/mysql";
# solaris
#my $MYSQL_ADMIN_EXEC = "/usr/local/mysql/bin/mysqladmin";
# linux
my $MYSQL_ADMIN_EXEC = "/usr/bin/mysqladmin";
my $GZIP_EXEC 	= "/bin/gzip";
my $VERBOSE = 0;
################################################################################


use strict;
use File::Copy;
use DBI;

if ($MY_CNF) {
	# read username and password from .my.cnf file
	open (MY_CNF,"<$MY_CNF") || 
		warn "Can't read db password, can't read list of databases." .
			" Will attempt to rotate transaction log.";
	while (<MY_CNF>) {
		# skip comments
		(/^\s*[#|;]/ && next) || chomp;
		my ($key,$val) = split(/\s*=\s*/);
		if ($key eq 'user') { $DBUSER = $val; }
		if ($key eq 'password') { $DBPASS = $val; } 
	}
}

# get list of databases. why doesn't DBI->data_sources('mysql') work ??
my $dbh = DBI->connect("DBI:mysql:$DATABASE:$HOSTNAME", $DBUSER, $DBPASS);
my @db_names = $dbh->func('_ListDBs');
$dbh->disconnect;

# did we get a list?
$db_names[0] || warn "Can not find list of databases. No dumps made. " .
		"Will attempt to rotate transaction log.";

$VERBOSE && print "Backing up: " . join ", ", @db_names;

# convert unix time to date + time
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
my $time  = sprintf("%0.2d:%0.2d:%0.2d",$hour,$min,$sec);
my $date  = sprintf("%0.4d.%0.2d.%0.2d",$year+1900,++$mon,$mday);
my $timestamp = "$date.$time";

# dump all the DBs we want to backup
foreach my $db_name (@db_names) {
	my $dump_file = "$DUMP_DIR/$timestamp.$db_name.sql";
    # http://dev.mysql.com/doc/mysql/en/mysqldump.html
	#my $dump_command = "/usr/bin/mysqldump -c -e -l -q --flush-logs $db_name > $dump_file";
	my $dump_command = "/usr/local/mysql/bin/mysqldump --defaults-extra-file=$MY_CNF --opt $db_name > $dump_file";
	system $dump_command;
}

# restart the update log to log to a new file!
system $MYSQL_ADMIN_EXEC, 'refresh';

# compress all the created files
system "$GZIP_EXEC $DUMP_DIR/$timestamp.*";
