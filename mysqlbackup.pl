#!/usr/bin/perl -w
################################################################################
# mysqlbackup.pl v1.0 dale@bewley.net 04/22/2000 
#-------------------------------------------------------------------------------
#
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
################################################################################

use strict;
use warnings;
use DBI;
use Getopt::Long;

# Prototypes
sub query_to_hash($);
sub run_query($);
sub help($);
sub get_mysql_vars();

################################################################################
# Adjust the following defaults for your site.
my %conf = (
    # See http://www.mysql.com/php/manual.php3?section=>Option_files
    my_cnf 	    => '/root/.my.cnf', # may contain user and password
    user	    => '',	# will be read from $conf{'my_cnf'}
    pass	    => '',	# will be read from $conf{'my_cnf'}
    database	=> 'mysql', # db used to create a handle for listing all db's
    host  	    => 'localhost', # host running mysql to be backed up
    exclude_dbs => [ qw( information_schema ) ], # do not backup these DBs

    dump_dir   => "/var/backup/mysql", # where to place backups
    min_binary_logs => 4, # how many logs to retain
    test       => 0, # don't make any changes
    verbose    => 0, # chatty kathy
    help       => 0, # show help and exit
    not_master => 0, # TODO unused

    # executables
    mysql_admin_exec => "/usr/bin/mysqladmin",
    gzip_exec  => "/bin/gzip",
);
################################################################################

GetOptions(
    "h|help"             => \$conf{help},
    "host=s"             => \$conf{host},
    "u|user=s"           => \$conf{user},
    "p|pass|password=s"  => \$conf{pass},
    "m|mycnf=s"          => \$conf{my_cnf},
    "s|skip-database=s@" => \$conf{exclude_dbs},
    "l|min-logs=i"       => \$conf{min_binary_logs},
    "d|dir|dump-dir=s"   => \$conf{dump_dir},
    "v|verbose"          => \$conf{verbose},
    "t|test"             => \$conf{test},
    "n|nomaster"         => \$conf{not_master},
);

if ($conf{'help'}) { help(\%conf) && exit; }

sub help($) {
   my $conf = shift;
   my $exclude_dbs = join(' ',@{$conf->{'exclude_dbs'}});
   print <<"EOH";

Usage: $0 [options]

 Options            Defaults
   -h | --help      This screen.

   -m | --mycnf     $conf->{'my_cnf'}
                    Specify my.cnf file containing user and password.

   -u | --user	    $conf->{'user'}
                    Specify mysql user, or it will be read from $conf->{'my_cnf'}.

   -p | --pass	    $conf->{'pass'}
                    Specify mysql password, or it will be read from $conf->{'pass'}.

   --host           $conf->{'host'}
                    Host running mysql to be backed up.

   -s | --skip-database  $exclude_dbs
                    Do not backup these databases. Perhaps you have a read-only
                    database which needs infrequent backups.

   -d | --dir | --dump-dir $conf->{'dump_dir'}
                    Where to place backups.

   -l | --min-logs  $conf->{'min_binary_logs'}
                    Retain at least this many binary logs.

   -v | --verbose   $conf->{'verbose'}
                    Provide more feedback.

   -t | --test      $conf->{'test'}
                    Go through the motions, but do not write or change anything.
EOH
}


################################################################################
# begin main
if (! -w $conf{'dump_dir'}) {
    die "Can not write to $conf{'dump_dir'} $!";
}

# setup mysql login credentials
if ($conf{'my_cnf'} && ! $conf{'pass'}) {
	# read username and password from .my.cnf file
    print "No password specified. Checking $conf{'my_cnf'}\n" if ($conf{'verbose'});
	open (MY_CNF,"<$conf{'my_cnf'}") || die "Can not read $conf{'my_cnf'} $!";

	while (<MY_CNF>) {
		# skip comments
		(/^\s*[#|;]/ && next) || chomp;
		my ($key,$val) = split(/\s*=\s*/);
        # don't clobber user supplied values
        if ($key eq 'user')     { !$conf{'user'} && ($conf{'user'} = $val) }
		if ($key eq 'password') { !$conf{'pass'} && ($conf{'pass'} = $val) } 
	}
}
unless ($conf{'user'} && $conf{'pass'}) { die "Missing mysql login credentials. $!"; }

# connect to mysql
print "Connecting to database '$conf{'database'}' on '$conf{'host'}' as '$conf{'user'}'\n" if ($conf{'verbose'});
my $dbh = DBI->connect("DBI:mysql:$conf{'database'}:$conf{'host'}", $conf{'user'}, $conf{'pass'});
$dbh->{RaiseError} = 1;

# get list of databases.
my @db_names = $dbh->func('_ListDBs');
print "Found databases: ", join(', ', @db_names), "\n" if ($conf{'verbose'});

# did we get a list?
$db_names[0] || die "Can not find list of databases. $!";

# get list of mysql variables
my $vars = get_mysql_vars();
#foreach my $key (sort keys %$vars) { print "$key -> $$vars{$key}\n"; }

# flush tables and rotate binary log
print "Flushing tables and rotating binary log if enabled\n" if ($conf{'verbose'});
if (! $conf{'test'}) {
    my @args = ('-u', $conf{'user'}, "--password=$conf{'pass'}", 'refresh');
    system $conf{'mysql_admin_exec'}, @args;
    # check result
    if ($? != 0 ) {
        if ($? == -1) {
            print "failed to execute: $!\n";
        } elsif ($? & 127) {
            printf "child died with signal %d, %s coredump\n",
                   ($? & 127),  ($? & 128) ? 'with' : 'without';
        } else {
            printf "child exited with value %d\n", $? >> 8;
        }
    }
}

# check if binary logging is enabled.
if ($vars->{'log_bin'} eq 'ON') {
    print "Binary logging is enabled\n" if ($conf{'verbose'});

    # returns Log_name, File_size for each binary log
    my @binary_logs = query_to_hash('show master logs');
    print "Found ", scalar @binary_logs, " logs\n" if ($conf{'verbose'});

    if (scalar @binary_logs > $conf{'min_binary_logs'}) {
        print "Purging logs older than $conf{'min_binary_logs'} latest logs\n" if ($conf{'verbose'});
        my $purge_stm = "purge master logs to '" . 
            $binary_logs[-$conf{'min_binary_logs'}]{'Log_name'} . "'";
        print "$purge_stm\n" if ($conf{'verbose'});

        if (! $conf{'test'}) {
            $dbh->do($purge_stm) || warn "Failed to purge logs $!";
        }
    }

} else {
    print "To enable binary logging add 'bin-log' to the '[mysqld]' section of my.cnf\n" if ($conf{'verbose'});
}

# we are done with mysql, we use mysqladmin from here on out
$dbh->disconnect;

# convert unix time to date + time
my ($sec,$min,$hour,$mday,$mon,$year) = localtime(time);
my $time  = sprintf("%0.2d:%0.2d:%0.2d",$hour,$min,$sec);
my $date  = sprintf("%0.4d.%0.2d.%0.2d",$year+1900,++$mon,$mday);
my $timestamp = "$date.$time";

# dump all the DBs we want to backup
foreach my $db_name (@db_names) {
    next if (grep( /^$db_name$/, @{$conf{'exclude_dbs'}}));
    print "Backing up: $db_name\n" if ($conf{'verbose'});

	my $dump_file = "$conf{'dump_dir'}/$timestamp.$db_name.sql";
    # http://dev.mysql.com/doc/mysql/en/mysqldump.html
    # TODO add support for command line user / pass
	my $dump_command = "/usr/bin/mysqldump --defaults-extra-file=$conf{'my_cnf'} --opt '$db_name' > '$dump_file'";
    if (! $conf{'test'}) {
        system $dump_command;
    } else {
        print "#$dump_command\n";
    }
}

# compress all the created files
system "$conf{'gzip_exec'} $conf{'dump_dir'}/$timestamp.*" if (! $conf{'test'});


################################################################################
# begin functions

# execute query, and return results in an array of hashes.
sub query_to_hash($) {
    my $sql = shift;
    my @records;

    if (my $sth = run_query($sql)) {
        while (my $ref = $sth->fetchrow_hashref) {
            push @records, $ref;
        }
    }

    return @records;
}

# run_query an SQL query and return the statement handle.
sub run_query($) {
    my $sql = shift;

    my $sth = $dbh->prepare($sql);
    if (! $sth) {
        die $DBI::errstr;
    }

    my $result = $sth->execute;
    if (! $result) {
        return undef;
    }

    return $sth;
}

# load mysql status variables into a hash
sub get_mysql_vars() {
    my %vars;
    my @rows = query_to_hash("show variables");

    foreach my $row (@rows) {
        my $name  = $row->{Variable_name};
        my $value = $row->{Value};
        $vars{$name} = $value;
    }

    return \%vars;
}
