#!/usr/bin/perl

use strict;
use warnings;
use String::Util qw(trim);
use File::Basename;
use File::Compare;
use PostgresNode;
use Test::More;

# Expected folder where expected output will be present
my $expected_folder = "t/expected";

# Results/out folder where generated results files will be placed
my $results_folder = "t/results";

# Check if results folder exists or not, create if it doesn't
unless (-d $results_folder)
{
   mkdir $results_folder or die "Can't create folder $results_folder: $!\n";;
}

# Check if expected folder exists or not, bail out if it doesn't
unless (-d $expected_folder)
{
   BAIL_OUT "Expected files folder $expected_folder doesn't exist: \n";;
}

# Get filename of the this perl file
my $perlfilename = basename($0);

#Remove .pl from filename and store in a variable
$perlfilename =~ s/\.[^.]+$//;
my $filename_without_extension = $perlfilename;

# Create expected filename with path
my $expected_filename = "${filename_without_extension}.out";
my $expected_filename_with_path = "${expected_folder}/${expected_filename}" ;

# Create results filename with path
my $out_filename = "${filename_without_extension}.out";
my $out_filename_with_path = "${results_folder}/${out_filename}" ;
my $dynamic_out_filename_with_path = "${results_folder}/${out_filename}.dynamic" ;

# Delete already existing result out file, if it exists.
if ( -f $out_filename_with_path)
{
   unlink($out_filename_with_path) or die "Can't delete already existing $out_filename_with_path: $!\n";
}

# Create new PostgreSQL node and do initdb
my $node = PostgresNode->get_new_node('test');
my $pgdata = $node->data_dir;
$node->dump_info;
$node->init;

# Update postgresql.conf to include/load pg_stat_monitor library   
$node->append_conf('postgresql.conf', "shared_preload_libraries = 'pg_stat_statements,pg_stat_monitor'");
# Set bucket duration to 3600 seconds so bucket doesn't change.
$node->append_conf('postgresql.conf', "pg_stat_statements.track_utility = off");
$node->append_conf('postgresql.conf', "pg_stat_monitor.pgsm_bucket_time = 1800");
$node->append_conf('postgresql.conf', "track_io_timing = on");
$node->append_conf('postgresql.conf', "pg_stat_monitor.pgsm_track_utility = no");

# Start server
my $rt_value = $node->start;
ok($rt_value == 1, "Start Server");

# Create extension and change out file permissions
my ($cmdret, $stdout, $stderr) = $node->psql('postgres', 'CREATE EXTENSION pg_stat_statements;', extra_params => ['-a']);
ok($cmdret == 0, "Create PGSS Extension");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");
chmod(0640 , $out_filename_with_path)
    or die("unable to set permissions for $out_filename_with_path");

# Create extension and change out file permissions
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'CREATE EXTENSION pg_stat_monitor;', extra_params => ['-a']);
ok($cmdret == 0, "Create PGSM Extension");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");
chmod(0640 , $out_filename_with_path)
    or die("unable to set permissions for $out_filename_with_path");

# Run required commands/queries and dump output to out file.
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'SELECT pg_stat_monitor_reset();', extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
ok($cmdret == 0, "Reset PGSM Extension");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");

# Run required commands/queries and dump output to out file.
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'SELECT pg_stat_statements_reset();', extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
ok($cmdret == 0, "Reset PGSS Extension");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");

# Run 'SELECT * from pg_stat_monitor_settings;' two times and dump output to out file 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'SELECT * from pg_stat_monitor_settings;', extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
ok($cmdret == 0, "Print PGSM Extension Settings");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");

# Create example database and run pgbench init
# ($cmdret, $stdout, $stderr) = $node->psql('postgres', 'CREATE database example;', extra_params => ['-a']);
# ok($cmdret == 0, "Create Database example");
# TestLib::append_to_file($out_filename_with_path, $stdout . "\n");

my $port = $node->port;

my $out = system ("pgbench -i -s 100 -p $port postgres");
ok($cmdret == 0, "Perform pgbench init");

$out = system ("pgbench -c 10 -j 2 -t 10000 -p $port postgres");
ok($cmdret == 0, "Run pgbench");

($cmdret, $stdout, $stderr) = $node->psql('postgres', "Delete from pgbench_accounts where aid % 9 = 1;", extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
($cmdret, $stdout, $stderr) = $node->psql('postgres', "Delete from pgbench_accounts where aid % 10 = 1;", extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
($cmdret, $stdout, $stderr) = $node->psql('postgres', "Delete from pgbench_accounts where aid % 5 = 1;", extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
($cmdret, $stdout, $stderr) = $node->psql('postgres', "Delete from pgbench_accounts where aid % 3 = 1;", extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
($cmdret, $stdout, $stderr) = $node->psql('postgres', "Delete from pgbench_accounts where aid % 2 = 1;", extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select substr(query,0,130) as query, calls, rows, total_exec_time,min_exec_time,max_exec_time,mean_exec_time,stddev_exec_time from pg_stat_statements where query Like \'%bench%\' order by query,calls desc;', extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
TestLib::append_to_file($dynamic_out_filename_with_path, $stdout . "\n");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select substr(query,0,130) as query, calls, rows_retrieved, total_exec_time, min_exec_time, max_exec_time, mean_exec_time,stddev_exec_time, cpu_user_time, cpu_sys_time from pg_stat_monitor where query Like \'%bench%\' order by query,calls desc;', extra_params => ['-a', '-Pformat=aligned','-Ptuples_only=off']);
TestLib::append_to_file($dynamic_out_filename_with_path, $stdout . "\n");
TestLib::append_to_file($dynamic_out_filename_with_path, "\n\n");

# Compare values for query 'Delete from pgbench_accounts where $1 = $2' 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.total_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: total_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.min_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: min_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.max_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: max_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.mean_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: mean_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.stddev_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: stddev_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_user_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_user_time should not be 0.");
 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_sys_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%Delete from pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_sys_time should not be 0.");


# Compare values for query 'INSERT INTO pgbench_history (tid, bid, aid, delta, mtime) VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)' 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.total_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: total_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.min_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: min_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.max_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: max_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.mean_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: mean_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.stddev_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: stddev_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_user_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_user_time should not be 0.");
 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_sys_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%INSERT INTO pgbench_history%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_sys_time should not be 0.");

# Compare values for query 'SELECT abalance FROM pgbench_accounts WHERE aid = $1' 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.total_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: total_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.min_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: min_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.max_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: max_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.mean_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: mean_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.stddev_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: stddev_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_user_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_user_time should not be 0.");
 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_sys_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%SELECT abalance FROM pgbench_accounts%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_sys_time should not be 0.");

# Compare values for query 'UPDATE pgbench_accounts SET abalance = abalance + $1 WHERE aid = $2' 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.total_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: total_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.min_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: min_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.max_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: max_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.mean_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: mean_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.stddev_exec_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: stddev_exec_time should not be 0.");

($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_user_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_user_time should not be 0.");
 
($cmdret, $stdout, $stderr) = $node->psql('postgres', 'Select PGSM.cpu_sys_time != 0 from pg_stat_monitor as PGSM where PGSM.query Like \'%UPDATE pgbench_accounts SET abalance%\';', extra_params => ['-Pformat=unaligned','-Ptuples_only=on']);
trim($stdout);
is($stdout,'t',"Check: cpu_sys_time should not be 0.");

# Drop extension
$stdout = $node->safe_psql('postgres', 'Drop extension pg_stat_monitor;',  extra_params => ['-a']);
ok($cmdret == 0, "Drop PGSM  Extension");
TestLib::append_to_file($out_filename_with_path, $stdout . "\n");

# Stop the server
$node->stop;

# Done testing for this testcase file.
done_testing();

