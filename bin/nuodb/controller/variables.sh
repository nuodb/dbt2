
# You will need to set these:
export DBT2Home=/opt/dbt2-install    # DBT2 install directory (where "make install" was targeted)
export BenchOutputRoot=/home/$USER/dbt2-bench-output
export EMAIL_ADDR=...@...com
export TC_PATH_TO_BUILD=/home/me/RELEASE-PACKAGE18-3.tgz

# these are variables that affect every test case
export TC_SKIP_INSTALL_START_AGENTS=false  # if 'true', will NOT extract NuoDB and start agent - uses existing running agent.  REQUIRES NUODB_HOME to be set
# export NUODB_HOME=/opt/nuodb   # required only if TC_SKIP_INSTALL_START_AGENTS is true
export TC_LEAVE_DB_RUNNING=false      # if 'true', database processes left running after workload is done
export TC_USE_EXISTING_DB=false      # if 'true', use existing database archive
export TC_SM_MEM_SETTING=8g
export TC_TE_MEM_SETTING=8g
export TC_DURATION_SEC=300
export TC_NUM_DATACENTERS=1
export TC_NUM_STORAGEGROUPS_PER_SM=1
export TC_NUM_SMS_PER_STORAGEGROUP=1
export TC_ARCHIVE_ROOT=/tmp
export TC_NUM_SMS_PER_SMHOST=1
export TC_1WAY_LATENCY_MS=0
export TC_NUM_PARTITIONS=1
export TC_COMMIT="region:1"
export TC_JOURNAL=enable
export TC_JOURNAL_SYNC_METHOD=kernel
export TC_JOURNAL_MAX_FILE_SIZE_BYTES=4194304
export TC_JOURNAL_PATH=/ssd/archive
export TC_MULTI_DC_ONE_REGION=false   # This applies to multi data center tests - if "true", then domain will be setup as 1 region though hosts will have latency added as they normally would in a multi-dc benchmark.

# If this file exists, a 'network test' will be triggered before the workload runs, where the
# script will copy this file to all the hosts and measure the duration.  We've found certain server
# machines with unreliable ethernet and this test helps to detect those.
export BigNCTestFile=/tmp/5GB-junkfile.tar

# These can probably be left alone: -----------------------------------------------------------
export BenchTmp=/tmp/dbt2-$USER
export LogsTmp=$BenchTmp/logs
export DEPLOYMENT_DIR=$BenchTmp
export NUODB_BACKUP_DIR=/tmp/bench-nuodb-backup-$USER
export ARCHIVE_BACKUP_DIR=/tmp/bench-archive-backup-$USER
export DATABASE_USER=dba
export DATABASE_PASSWORD=dba
export NCPort=1234
export PRESERVE_NUODB=0
