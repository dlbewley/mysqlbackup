#!/usr/bin/perl -w
################################################################################
# $Id$
# mysqlbackup.pl v1.0 dale@bewley.net 04/22/2000 
#-------------------------------------------------------------------------------
# Based on ideas from:
#  http://perl.apache.org/guide/snippets.html#Mysql_Backup_and_Restore_Scripts
#  http://jeremy.zawodny.com/mysql/mysqlsnapshot/
# 
# What this script does:
# 	1. obtain a list of databases
# 	2. dump all the databases into a separate dump files (these dump files 
# 	are ready for DB restore)
# 	3. backs up the last update log file and creates a new log file
#		Is this the safest way to do that???
#
# Todo
#	o No need to do a full dump each time, add a switch to only rotate
#	  the update log.
#	o Log actions
#
################################################################################

use strict;
use warnings;
use DBI;
use Getopt::Long;

## Prototypes

sub Hashes($);
sub Execute($);
sub help();
sub get_mysql_vars();

my %conf = (
################################################################################
# Adjust the following defaults for your site.
    database	=> 'mysql', # db used to create a handle for listing all db's
    host  	    => 'localhost',
    exclude_dbs => [ qw( information_schema ) ],
    min_binary_logs => 4,

    # See http://www.mysql.com/php/manual.php3?section=>Option_files
    my_cnf 	=> '/root/.my.cnf', 
    user	=> '',	# will be read from $conf{'my_cnf'}
    pass	=> '',	# will be read from $conf{'my_cnf'}

    # where will database backups be dumped?
    dump_dir  	=> "/var/backup/mysql",
    # solaris
    #my $conf{'mysql_admin_exec'} => "/usr/local/mysql/bin/mysqladmin",
    # linux
    mysql_admin_exec => "/usr/bin/mysqladmin",
    gzip_exec 	=> "/bin/gzip",
    not_master => 0,
################################################################################
    help       => 0,
    test       => 0,
    verbose    => 0,
);

GetOptions(
           "h|help"             => \$conf{help},
           "u|user=s"           => \$conf{user},
           "m|mycnf=s"          => \$conf{mycnf},
           "p|pass|password=s"  => \$conf{pass},
           "d|dir|dumpdir=s"    => \$conf{dump_dir},
           "v|verbose"          => \$conf{verbose},
           "t|test"             => \$conf{test},
           "n|nomaster"         => \$conf{not_master},
          );

if ($conf{'help'}) { help() && exit; }

sub help() {
   print "Help!\n";
}

################################################################################
# begin main
if ($conf{'my_cnf'} && ! $conf{'pass'}) {
	# read username and password from .my.cnf file
	open (MY_CNF,"<$conf{'my_cnf'}") || 
		warn "Can't read db password, can't read list of databases." .
			" Will attempt to rotate transaction log.";
	while (<MY_CNF>) {
		# skip comments
		(/^\s*[#|;]/ && next) || chomp;
		my ($key,$val) = split(/\s*=\s*/);
        # don't clobber user supplied values
        if ($key eq 'user')     { !$conf{'user'} && ($conf{'user'} = $val) }
		if ($key eq 'password') { !$conf{'pass'} && ($conf{'pass'} = $val) } 
	}
}

# get list of databases.
print "Connecting to DB $conf{'database'} on $conf{'host'} as $conf{'user'}\n" if ($conf{'verbose'});
my $dbh = DBI->connect("DBI:mysql:$conf{'database'}:$conf{'host'}", $conf{'user'}, $conf{'pass'});
$dbh->{RaiseError} = 1;

my @db_names = $dbh->func('_ListDBs');
print "Found DBs ", join(', ', @db_names), "\n" if ($conf{'verbose'});

# did we get a list?
$db_names[0] || warn "Can not find list of databases. No dumps made. " .
		"Will attempt to rotate transaction log.";

# get list of mysql variables
my $vars = get_mysql_vars();
#foreach my $key (sort keys %$vars) {
#    print "$key -> $$vars{$key}\n";
#}

# restart the update log to log to a new file!
system $conf{'mysql_admin_exec'}, 'refresh' if (! $conf{'test'});

# check if binary logging is enabled.
if ($vars->{'log_bin'} eq 'ON') {
   print "Binary logging is enabled\n" if ($conf{'verbose'});

    my $log_sql ='show master logs';
    my $log_sth = $dbh->prepare($log_sql);
    $log_sth->execute();
    my $binary_logs = $log_sth->fetchall_arrayref();
    print "Found ", scalar @$binary_logs, " logs\n" if ($conf{'verbose'});

    if (scalar @$binary_logs > $conf{'min_binary_logs'}) {
        print "Purging logs older than $conf{'min_binary_logs'} latest logs\n" if ($conf{'verbose'});
        my $purge_stm = "purge master logs to '" . 
            $$binary_logs[-$conf{'min_binary_logs'}][0] . "'";
        print "$purge_stm\n" if ($conf{'verbose'});
        if (! $conf{'test'}) {
            $dbh->do($purge_stm) || warn "Failed to purge logs $!";
        }
    }
} else {
    print "To enable binary logging add 'bin-log' to the '[mysqld]' section of my.cnf\n" if ($conf{'verbose'});
}

# we use mysqladmin from here on out
$dbh->disconnect;

# convert unix time to date + time
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
my $time  = sprintf("%0.2d:%0.2d:%0.2d",$hour,$min,$sec);
my $date  = sprintf("%0.4d.%0.2d.%0.2d",$year+1900,++$mon,$mday);
my $timestamp = "$date.$time";

# dump all the DBs we want to backup
foreach my $db_name (@db_names) {
    # skip static databases - this is ugly
    next if (grep( /^$db_name$/, @{$conf{'exclude_dbs'}}));
    print "Backing up: $db_name\n" if ($conf{'verbose'});

	my $dump_file = "$conf{'dump_dir'}/$timestamp.$db_name.sql";
    # http://dev.mysql.com/doc/mysql/en/mysqldump.html
    # TODO add support for command line user / pass
	my $dump_command = "/usr/bin/mysqldump --defaults-extra-file=$conf{'my_cnf'} --opt '$db_name' > '$dump_file'";
    if (! $conf{'test'}) {
        system $dump_command;
    } else {
        print "Not executing: $dump_command\n";
    }
}

# compress all the created files
system "$conf{'gzip_exec'} $conf{'dump_dir'}/$timestamp.*" if (! $conf{'test'});

#-------------------------------------------------------------------------------

## Fetch SHOW VARIABLES
##
sub get_mysql_vars() {
    my %vars;
    my @rows = Hashes("SHOW VARIABLES");

    foreach my $row (@rows) {
        my $name  = $row->{Variable_name};
        my $value = $row->{Value};

        $vars{$name} = $value;
    }

    return \%vars;
}

## Run a query and return the records as an array of hashes.
sub Hashes($) {
    my $sql   = shift;

    my @records;

    if (my $sth = Execute($sql)) {
        while (my $ref = $sth->fetchrow_hashref) {
            push @records, $ref;
        }
    }

    return @records;
}

## Execute an SQL query and return the statement handle.
sub Execute($)
{
    my $sql = shift;

    ##
    ## Prepare the statement
    ##
    my $sth = $dbh->prepare($sql);

    if (not $sth) {
        die $DBI::errstr;
    }

    ##
    ## Execute the statement.
    ##

    my $ReturnCode = $sth->execute;

    if (not $ReturnCode) {
        return undef;
    }

    return $sth;
}
