INTRODUCTION

dbt2-nuodb-controller.sh is a shell script which automates the setup,
execution and results processing of DBT-2 benchmarks with NuoDB.  Some
notable features include:

* Use of "testcase configuration" files for defining all the parameters
  of a testcase.  
* Full support for NuoDB TPSG: creating DBT-2 database with arbitrary number
  of partitions and storage groups mapped to SMs.
* Geo support: distribute TE/SM nodes across 1-5 simulated data-centers/regions,
  with configurable latency added between regions
* Database "warmup" to setup index chairmanship
* Log network statistics prior to test for later analysis 
* Run NMON on all hosts and package statistics with test results for analysis

NOTE that at this time, the controller script only supports running
DBT2 client, driver, and NuoDB TE on the same machines.  NuoDB SMs
will be on separate systems.  Being a distributed database, this is a
common usecase for NuoDB, to run a TE on the same host as the
database client.

INITIAL SETUP

Follow these steps to setup a new set of hosts to run the
controller.  The account from which you will run the framework needs
to have a shared home directory across all the hosts, OR

* The dbt2 directory needs to be accessible from the same location on
  all machines in your cluster.  This could be achieved with a shared
  NFS directory or by rsync'ing the folder to all systems.
* Add the following line to the /etc/sudoers file on all your hosts:
  "your-user-id ALL=(ALL) NOPASSWD: ALL"
* Ensure the account can ssh to all the hosts without requiring a password
* If you're using an SSD for the journal, the /etc/fstab entry for
  /ssd should have the "discard" option, and make /ssd world writable:
  sudo chmod 777 /ssd
* Install the 'nmon' package on all hosts
* Build dbt2 according to instructions in dbt2/README-NUODB.md.  You
  will need to do the 'make install' part also.  Note the install
  directory you chose (CMAKE_INSTALL_PREFIX:PATH)... This will be the value
  you set in DBT2Home in your variables.sh, discussed below.

SETTING UP TESTCASES AND PREPARING TO RUN BENCHMARKS

The DBT2 framework comprises a suite of testcases which you can use
as-is, modify, or create your own.  A testcase is defined by a set of
testcase configuration variables.  The primary variables are described
at the end of this document.  Testcase variables are shell variables
beginning with TC_ and are defined in 2 places:

* The variables.sh file.  These affect all testcases but can be overriden
  by defining them in...
* A testcase configuration file.  These are in the test-case-definitions
  directory and are named testcaseID.tc.  Note the .tc extension.
  Variables defined here will override those in variables.sh.
  
There are a few testcases in the test-case-definitions directory which you can use
as a starting point for creating your own testcase configuration files.

Before starting, you will want to set these variables in variables.sh to customize for your environment:

* DBT2Home - path to your DBT2 install directory
* BenchOutputRoot - directory where results are stored
* EMAIL_ADDR - your e-mail address, where the script will send error messages and results summaries
* TC_PATH_TO_BUILD - full path and filename of the NuoDB build

EXECUTING A BENCHMARK

To execute the benchmark, determine the set of machines to run with,
which should equal the number of client, TE and SM hosts defined in
the testcase configuration file.  Login to the first in the set of
hosts, cd to <dbt2>/bin/nuodb/controller and run:

LSB_HOSTS="host1 host2 host3 ... hostX" ./dbt2-nuodb-controller.sh
Usage: ./dbt2-nuodb-controller.sh suite-instance-id test-case-id 

LSB_HOSTS is a space-separated list of hostnames to be used for the benchmark.  The script will choose TEs from the head of the list, and SMs from the tail.  The script also requires the following arguments:

* The suite-instance-id is a string representing the directory name
  where results will be written (in $BenchOutputRoot).  A single
  suite-instance-id directory may contain output from one or more
  testcases, but only one instance of a testcase.  For instance, if you
  wanted to run testcase X multiple times, you would need a different
  suite-instance-id for each run.

* The test-case-id is the file in test-case-definitions with the
  testcase variables you want to run with (but without the .tc
  extension).

VIEWING RESULTS

Results are written to the directory specified by BenchOutputRoot in
variables.sh, with a subdirectory matching the suite-instance-id given
as an argument to the controller script.  In the suite instance
directory is a .tgz for each testcase run for that suite instance.
The tarball contents are:

- host1-logs, host2-logs, etc...  - there is one directory for each
  DBT-2 client machine.  It contains debug info about state of index
  atoms before and after test, dbt2 client and driver errors logs, and
  result statistics.

- network-stats-AFTER.txt - output of the network check routine run
  before the workload starts.  If your results are less than expected,
  check this for network anomalies.

- nmon - directory of nmon system statistics files, useful for viewing
  with the NMONVisualizer:
  http://nmonvisualizer.github.io/nmonvisualizer/

- nuodb-setup - configuration dump of NuoDB domain and process
  configuration

- nuodb-stats.log and nuodb-trace.log - output of nuodbmgr monitor
  database and trace domain commands running while the workload was
  being executed.

- results.txt - summary of DBT2 results (including the final NOTPM
  number), collated by DBT2 results processor from all the client
  machines.


TESTCASE VARIABLES

Below are the primary testcase variables and their definitions:

TC_SM_MEM_SETTING - SM heap size (example: 24g)
TC_TE_MEM_SETTING - TE heap size (example: 24g)
TC_DURATION_SEC - duration of DBT2 benchmark phase (not including database load, initialization, etc...)
TC_NUM_DATACENTERS - number of "data centers", groups of hosts that will get their own region and potentially have latency added to other hosts.
TC_NUM_STORAGEGROUPS_PER_SM - number of storage groups per SM
TC_NUM_SMS_PER_STORAGEGROUP - number of SMs per storage group
TC_NUM_SMS_PER_SMHOST - number of SMs per host.  Rarely used, but some hosts may perform better with two SMs processes (S1 and S2 seem to)
TC_1WAY_LATENCY_MS - In a multi-datacenter test, number of ms latency in each direction (ex: 10, which would yield 20ms total latency between datacenters)
TC_MULTI_DC_ONE_REGION - true/false - if "true", then domain will be setup as 1 region though hosts will have latency added as they normally would in a multi-dc benchmark.
TC_WAREHOUSES - total number of DBT2 warehouses
TC_NUM_DB_CONNS_PER_TE - number of database connections per DBT2 driver/te set (typically 64 on a p-rack machine)
TC_NUM_TES - total number of TEs (not 'per datacenter')
TC_NUM_SMS - total number of SMs
TC_STORAGEGROUPS - total number of storage groups.  Should be evenly divisible by number of SMs
TC_WARMUP_DB - true/false - if true, then "warmup" the database chairmanship, an optimization to improve performance (and simulates affect of having chairmanship migration)
TC_NUM_PARTITIONS - total number of database partitions.  Should also be evenly divisible by number of TEs
TC_JOURNAL - enable/disable
TC_COMMIT - local/remote/region/remote:x/region:s - commit protocol set on the TEs
TC_ARCHIVE_ROOT - location of NuoDB archive directory
TC_JOURNAL_SYNC_METHODj - matches --journal-sync-method value when starting SM
TC_JOURNAL_MAX_FILE_SIZE_BYTES - matches --journal-max-file-size-bytes value when starting SM
TC_JOURNAL_PATH - matches --journal-dir option when starting SM
TC_SINGLE_HOST - 0/1 - If 1, this is a single-host testcase - client/te/sm run on same host
