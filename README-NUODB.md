# Setting up DBT-2  for NuoDB
DBT-2 is a TPC-C like benchmark popular among SQL users. Setting it up is not
terribly well documented, so let me detail how this ought to be done below.
## Download It
You can download the cleaned up version of DBT-2 from Github here:

  https://github.com/nuodb/dbt2

## Install Prerequisite Software

Install Python 2.7.2 for run scripts. 
In this newest version of DBT-2 we have replace the dependency on R and rpy2 with a
pure Python implementation of the post-process module.

You will also need a GNU compiler, CMake (the latest version possible).

## Compile It
The build procedure is simple:

```bash
export NUODB_INCLUDE_DIR=/opt/nuodb/include
export NUODB_LIB_DIR=/opt/nuodb/lib64
cmake -G "Unix Makefiles" -DDBMS=nuodb
make
```

If you want to use `make install`, then set your prefix too:

```bash
cmake -G "Unix Makefiles" -DDBMS=nuodb -DCMAKE_INSTALL_PREFIX:PATH=/opt/local/dbt -DCMAKE_BUILD_TYPE=Debug
```

To install it locally:

```bash
make install
```

To create a redistributable package:

```bash
make package
```

## New Benchmark Controller usage

NuoDB has created a set of scripts and configuration files to wrap
dbt2 and simplify test setup and execution.  The new tool is in
bin/nuodb/controller.  Instructions are in the README.txt file there.
The former way for running dbt2 is described below.

## Before Proceeding

Modify the bin/nuodb/dbt2-nuodb-profile file so that your NuoDB installation
location is properly identified:

>       : ${NUODB_HOME:="/opt/nuodb"}

## Generate and Load Data
In order to test you have to generate data files which are imported into NuoDB
via NuoSQL. The tool that automates this is dbt2-nuodb-load-db:

>       -g - generate data files
>       -w - number of warehouses (example: -w 3)

```bash
dbt2-nuodb-start-db -f
dbt2-nuodb-load-db -w 3 -g
dbt2-nuodb-stop-db
```

n.b. stop db before running a workload as running workload itself will start the database.
## Run the Benchmark
Modify the bin/dbt2-nuodb-profile to match your environment setup.

Add the lib64 directory of your NuoDB installation to the LD_LIBRARY_PATH if you
are using a pre-built distribution; otherwise, for local builds the RPATH is set
so you should not have to configure anything in that case.

The benchmark is run using the run_workload script. Usage is as follows:

```bash
dbt2-run-workload -a nuodb -c <number of database connections> -d <duration of test> -w <number of warehouses>
```

Other options:

>       -c #  -  Set the number of database connections.
>       -d <database name. (default dbt2)>
>       -h <database host name. (default localhost)>
>       -l <database port number>
>       -o <enable oprofile data collection>
>       -s <delay of starting of new threads in milliseconds>
>       -n <no thinking or keying time (default no)>
>       -w #  -  Set the warehouse scale factor.
>       -z <comments for the test>

Example: dbt2-run-workload -a nuodb -c 20 -d 100 -w 1 -s 100 -o /var/tmp/results-1

Test will be run for 120 seconds with 20 database connections and scale factor (num of warehouses) 1

For measuring maximum throughput, use the -n option.

Helpful hints provided here:

http://www.tpc.org/information/sessions/sigmod/sld016.htm

## Review Results

Sample output follows:

        $ dbt2-run-workload -a nuodb -c 16 -d 300 -w 1 -s 100 -o /var/tmp/results21 
        No matching processes belonging to you were found
        [INFO] Shutting down chorus and monitors
        Domain entry failed: Connection refused, localhost/127.0.0.1:48004
        [INFO]: Starting broker
        	Execute: java -jar /opt/nuodb/jar/nuoagent.jar --broker --port 48004 --domain domain --password bird --verbose --bin-dir /opt/nuodb/bin --port-range 48010,48999 >> /var/tmp/dbt2/logs/dbt2-broker.log 2>&1 &
        [INFO] Starting archive manager and recreating database
        Started: [SM] machine.local/10.1.37.224:48010 [ pid = 8117 ] ACTIVE
        [INFO] Starting transaction engine
        Started: [TE] machine.local/10.1.37.224:48011 [ pid = 8124 ] ACTIVE
        DBT-2 test for nuodb started...

        DATABASE SYSTEM: localhost
        DATABASE NAME: dbt2
        DATABASE CONNECTIONS: 16
        TERMINAL THREADS: 10
        TERMINALS PER WAREHOUSE: 10
        WAREHOUSES PER THREAD/CLIENT PAIR: 1
        SCALE FACTOR (WAREHOUSES): 1
        DURATION OF TEST (in sec): 300
        1 client stared every 100 millisecond(s)

        Stage 1. Starting up client...
        Sleeping 1 seconds
        collecting database statistics...

        Stage 2. Starting up driver...
        100 threads started per millisecond
        -n estimated rampup time: 
        Sleeping 2 seconds
        estimated rampup time has elapsed
        -n estimated steady state time: 
        Sleeping 300 seconds

        Stage 3. Processing of results...
        Killing client...
        /usr/local/bin/dbt2-run-workload: line 648:  8166 Terminated: 15          dbt2-driver ${DRIVER_COMMAND_ARGS} > ${DRIVER_OUTPUT_DIR}/`hostname`/driver-${SEG}.out 2>&1
        /usr/local/bin/dbt2-run-workload: line 575:  8135 Terminated: 15          dbt2-client ${CLIENT_COMMAND_ARGS} -p ${PORT} -o ${CDIR} > ${CLIENT_OUTPUT_DIR}/`hostname`/client-${SEG}.out 2>&1
        [INFO] Shutting down chorus and monitors
        Shutdown database dbt2
        Test completed.
        Results are in: /var/tmp/results21

                                 Response Time (s)
         Transaction      %    Average :    90th %        Total        Rollbacks      %
        ------------  -----  ---------------------  -----------  ---------------  -----
            Delivery   2.80      0.282 :     0.364            4                0   0.00
           New Order  47.55      0.067 :     0.148           68                4   5.88
        Order Status   4.20      0.113 :     0.243            6                0   0.00
             Payment  39.16      0.023 :     0.048           56                0   0.00
         Stock Level   3.50      0.111 :     0.289            5                0   0.00
        ------------  -----  ---------------------  -----------  ---------------  -----

        13.55 new-order transactions per minute (NOTPM)
        5.0 minute duration
        0 total unknown errors
        0.0 seconds(s) ramping up

