#!/bin/bash
# trap 'interrupted' INT
#

export BenchScriptsDir=$(cd $(dirname $0) ; pwd)

handleArgs() {
    # Determine benchmark to run (first argument)
    if [ $# -lt 2 ]; then
        echo "Usage: $0 suite-instance-id test-case-id"
        exit 1
    fi
    export SuiteInstanceId=$1
    export TestcaseId=$2
    
    # Set test case config file path and check for it.
    export TestcaseConfigFile=${BenchScriptsDir}/test-case-definitions/${TestcaseId}.tc   
    if [ ! -f ${TestcaseConfigFile} ]; then
        echo "ERROR: Can't find test case definition file at ${TestcaseConfigFile}"
        exit 1
    fi

    echo ">>>>>>>>>> Starting $0 with suite instance ID '$SuiteInstanceId', test case '$TestcaseId' at $(date) with hosts ${LSB_HOSTS}..." 
}

initialize() {
    # special case for test cases using the S machines as an SM/TE
    if [ "$benchSMachine" != "" ]; then
        echo "----- Special S-machine test case - appending $benchSMachine to list of LSB_HOSTS"
        LSB_HOSTS="$LSB_HOSTS $benchSMachine"
        ARCHIVE_ROOT=/tmp
    else
        ARCHIVE_ROOT=$TC_ARCHIVE_ROOT
    fi
    

    if [ "$TC_NUM_TES" = "" ]; then
        echo "Testcase configuration error: TC_NUM_TES undefined."
        exit 1
    fi 
    if [ "$TC_NUM_SMS" = "" ]; then
        echo "Testcase configuration error: TC_NUM_SMS undefined."
        exit 1
    fi 
    if [ "$TC_COMMIT" = "" ]; then
        echo "WARNING: TC_COMMIT undefined.  Setting to region:1 default"
        export TC_COMMIT=region:1
    fi
    if [ "$TC_JOURNAL" = "" ]; then
        export TC_JOURNAL=enable
        echo "WARNING: TC_JOURNAL undefined.  Setting to '$TC_JOURNAL' by default"
    fi
    if [ "$TC_JOURNAL_SYNC_METHOD" = "" ]; then
        export TC_JOURNAL_SYNC_METHOD=kernel
        echo "WARNING: TC_JOURNAL_SYNC_METHOD undefined.  Setting to '$TC_JOURNAL_SYNC_METHOD' by default"
    fi
    if [ "$TC_JOURNAL_MAX_FILE_SIZE_BYTES" = "" ]; then
        export TC_JOURNAL_MAX_FILE_SIZE_BYTES=4194304
        echo "WARNING: TC_JOURNAL_MAX_FILE_SIZE_BYTES undefined.  Setting to '$TC_JOURNAL_MAX_FILE_SIZE_BYTES' by default"
    fi
    if [ "$TC_JOURNAL_PATH" = "" ]; then
        export TC_JOURNAL_PATH=/ssd/archive
        echo "WARNING: TC_JOURNAL_PATH undefined.  Setting to $TC_JOURNAL_PATH by default"
    fi
    if [ "$TC_TE_MEM_SETTING" == "" ] || [ "$TC_SM_MEM_SETTING" == "" ]; then
        echo "ERROR: Both TC_TE_MEM_SETTING and TC_SM_MEM_SETTING must be defined (best in variables.sh)"
        exit 1
    fi
    if [ "$TC_NUM_STORAGEGROUPS_PER_SM" = "" ]; then
        echo "ERROR: TC_NUM_STORAGEGROUPS_PER_SM undefined"
        exit 1
    fi
    if [ ! -f $BigNCTestFile ]; then
        echo "WARNING: can't find $BigNCTestFile for network test."
    fi
    if [ ! -d $DBT2Home ]; then
        echo "ERROR: can't find $DBT2Home"
        exit 1
    fi        

    if [ ! -e $DBT2Home/bin/dbt2-client ]; then
        echo "ERROR: can't find $DBT2Home/bin/dbt2-client - did you build dbt2 and 'make install' into $DBT2Home?"
        exit 1
    fi
    # Other initialization and validation
    : ${BROKER_PORT:="48004"}
    export BROKER_PORT
    export NUODB_ARCHIVE_DIR=/${ARCHIVE_ROOT}/bench_${USER}_DBT2_a
    export NUODB_JOURNAL_DIR=$TC_JOURNAL_PATH/bench_${USER}_DBT2_j
    export NUODB_DATABASE=dbt2
    export atomSqlFile=${BenchTmp}/atoms.sql

    # identify roles for machines (benchmark driver, TE, SM)
    if [ "$TC_SINGLE_HOST" == "1" ]; then
        let NUM_TC_HOSTS=1
        let NUM_LSB_HOSTS=1
        local lsbArr=($LSB_HOSTS)
        SM_HOSTS_ARR[0]="${lsbArr[0]}"
        TE_HOSTS_ARR[0]="${lsbArr[0]}"
    else
        let NUM_TC_HOSTS=TC_NUM_TES+TC_NUM_SMS
        let NUM_LSB_HOSTS=$(echo $LSB_HOSTS | wc -w | awk '{print $1}')
        if [ $NUM_TC_HOSTS -ne $NUM_LSB_HOSTS ]; then
            echo "Testcase configuration error: number requested hosts in testcase ($NUM_TC_HOSTS) != number gotten from LSB ($NUM_LSB_HOSTS)"
            exit 1
        fi
        local lsbArr=($LSB_HOSTS)
        for host in ${lsbArr[*]}; do
            if [ ${#TE_HOSTS_ARR[*]} -lt $TC_NUM_TES ]; then
                TE_HOSTS_ARR[${#TE_HOSTS_ARR[*]}]=$host
            else
                SM_HOSTS_ARR[${#SM_HOSTS_ARR[*]}]=$host
            fi
        done
    fi

    #TODO: check for evenly divisible # of TEs/SMs for data cetners

    if [ "$TC_SINGLE_HOST" == "1" ]; then
        local lsbArr=($LSB_HOSTS)
        local nuoHost=${lsbArr[0]}
        launchProvisionHostStr="$nuoHost,broker,${nuoHost}_dc0_region,${nuoHost}"
        brokerForRegion[0]=$nuoHost
    else
        # For NuoDB machines, set peer, region, broker|agent
        nuodbPeer=""
        nuodbRegion=""
        nuodbAgentType=""
        regionPtr=0
        numHostsInRegion=0
        masterBroker=""
        launchProvisionHostStr=""
        let tesPerDataCenter=TC_NUM_TES/TC_NUM_DATACENTERS
        let smsPerDataCenter=TC_NUM_SMS/TC_NUM_DATACENTERS
        # Map TEs to regions/data centers
        for nuoHost in ${TE_HOSTS_ARR[*]}; do 
            if [ "$masterBroker" == "" ]; then
                masterBroker=$nuoHost
            fi
            # Assign broker for this region if there isn't one yet
            if [ "${brokerForRegion[$regionPtr]}" == "" ]; then
                brokerForRegion[$regionPtr]=$nuoHost
                nuodbAgentType="broker"
                nuodbPeer=$masterBroker
            else
                nuodbAgentType="broker" # changed - was agent.  now everything is a broker
                nuodbPeer=${brokerForRegion[$regionPtr]}
            fi
            if [ "$TC_MULTI_DC_ONE_REGION" == "true" ]; then
                nuodbRegion="dc0_region"
            else
                nuodbRegion="dc${regionPtr}_region"
            fi
            launchProvisionHostStr="${launchProvisionHostStr};${nuoHost},${nuodbAgentType},${nuodbRegion},${nuodbPeer}"
            if [ ${TC_NUM_DATACENTERS} -gt 1 ]; then
                case $regionPtr in
                    0)
                        dc0hosts="${dc0hosts} ${nuoHost}"
                        ;;
                    1)
                        dc1hosts="${dc1hosts} ${nuoHost}"
                        ;;
                    2)
                        dc2hosts="${dc2hosts} ${nuoHost}"
                        ;;
                    3)
                        dc3hosts="${dc3hosts} ${nuoHost}"
                        ;;
                    4)
                        dc4hosts="${dc4hosts} ${nuoHost}"
                        ;;
                esac
            fi
            # move the region ptr if necessary
            let numHostsInRegion++
            if [ $numHostsInRegion -ge $tesPerDataCenter ]; then
                let regionPtr++
                numHostsInRegion=0
            fi
        done
        regionPtr=0
        numHostsInRegion=0
        # Map SMs to regions / data centers
        for nuoHost in ${SM_HOSTS_ARR[*]}; do 
            nuodbAgentType="agent"
            nuodbPeer=${brokerForRegion[$regionPtr]}
            if [ "$TC_MULTI_DC_ONE_REGION" == "true" ]; then
                nuodbRegion="dc0_region"
            else
                nuodbRegion="dc${regionPtr}_region"
            fi
            launchProvisionHostStr="${launchProvisionHostStr};${nuoHost},${nuodbAgentType},${nuodbRegion},${nuodbPeer}"
            if [ ${TC_NUM_DATACENTERS} -gt 1 ]; then
                case $regionPtr in
                    0)
                        dc0hosts="${dc0hosts} ${nuoHost}"
                        ;;
                    1)
                        dc1hosts="${dc1hosts} ${nuoHost}"
                        ;;
                    2)
                        dc2hosts="${dc2hosts} ${nuoHost}"
                        ;;
                    3)
                        dc3hosts="${dc3hosts} ${nuoHost}"
                        ;;
                    4)
                        dc4hosts="${dc4hosts} ${nuoHost}"
                        ;;
                esac
            fi
            # move the region ptr if necessary
            let numHostsInRegion++
            if [ $numHostsInRegion -ge $smsPerDataCenter ]; then
                let regionPtr++
                numHostsInRegion=0
            fi
        done

    fi
    export launchProvisionHostStr
    export SM_HOSTS=${SM_HOSTS_ARR[*]}
    export TE_HOSTS=${TE_HOSTS_ARR[*]}
    if [ "$TC_SINGLE_HOST" == "1" ]; then
        export NUODB_HOSTS="$SM_HOSTS"      
    else
        export NUODB_HOSTS="$SM_HOSTS $TE_HOSTS"
    fi
    export BROKER_HOST=${TE_HOSTS_ARR[0]}

    # Create benchtmp and logstmp on all hosts
    for host in $LSB_HOSTS; do
        ssh -o StrictHostKeyChecking=false $host "rm -rf $BenchTmp ; mkdir -p $BenchTmp ; rm -rf $LogsTmp ; mkdir -p $LogsTmp"
    done
    mkdir -p ${BenchTmp}/logs-work
    
    echo ----- SM_HOSTS = $SM_HOSTS
    echo ----- TE_HOSTS = $TE_HOSTS
}

preClean() {
    # passed-in by openlava when it schedules a job.  If not set, then set it as an env variable before calling
    if [ "$LSB_HOSTS" == "" ]; then
        echo "ERROR: LSB_HOSTS undefined."
        exit 1
    fi
    
    echo "----- preClean(): shutting down domain and agents..."
    mgr "shutdown domain" > /dev/null 2>&1 
    sleep 2
    for host in ${LSB_HOSTS}; do
        ssh -tt -o StrictHostKeyChecking=false $host "sudo killall nuodb ; sudo killall nmon ; sudo killall dbt2-client ; sudo killall dbt2-driver ; sudo rm -rf $NUODB_JOURNAL_DIR" > /dev/null 2>&1
        if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
            ssh -tt -o StrictHostKeyChecking=false $host "sudo killall java"  > /dev/null 2>&1
        fi
        if [ "$TC_USE_EXISTING_DB" != "true" ]; then
            ssh -q -tt -o StrictHostKeyChecking=false $host "sudo rm -rf $NUODB_ARCHIVE_DIR"  > /dev/null 2>&1
        fi
    done

    echo "----- Clearing traffic control on all NuoDB hosts ('No such file...' errors may be ignored)..."
    # reset traffic control settings on all our machines
    if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
        for host in ${NUODB_HOSTS}; do
            ssh -o StrictHostKeyChecking=false -tt $host "
nicName=\$(netstat -nr | tail -1 | awk '{print \$8}')
sudo tc qdisc del dev \$nicName root
"
        done
    fi
}

postClean() {
    echo "----- postClean(): shutting down remaining processes..."
    for host in ${LSB_HOSTS}; do
        if [ "$TC_LEAVE_DB_RUNNING" != "true" ]; then
            mgr "shutdown domain" > /dev/null 2>&1 
            sleep 2
            ssh -tt -o StrictHostKeyChecking=false $host "sudo killall nuodb ; sudo rm -rf $NUODB_JOURNAL_DIR"  > /dev/null 2>&1
        fi
        if [ "$TC_USE_EXISTING_DB" != "true" ]; then
            ssh -tt -q -o StrictHostKeyChecking=false $host "sudo rm -rf $NUODB_ARCHIVE_DIR"  > /dev/null 2>&1
        fi  
        ssh -tt -o StrictHostKeyChecking=false $host "sudo killall nmon ; sudo killall dbt2-client ; sudo killall dbt2-driver" > /dev/null 2>&1
        if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
            ssh -tt -o StrictHostKeyChecking=false $host "sudo killall java"  > /dev/null 2>&1
        fi
    done

    echo "----- Clearing traffic control on all NuoDB hosts ('No such file...' errors may be ignored)..."
    # reset traffic control settings on all our machines
    if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
        for host in ${NUODB_HOSTS}; do
            ssh -o StrictHostKeyChecking=false -tt $host "
nicName=\$(netstat -nr | tail -1 | awk '{print \$8}')
sudo tc qdisc del dev \$nicName root
"
        done
    fi
}

extractNuoDBForController()
{
    if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then    
        echo "----- Extracting build for controller..."
        pushd $BenchTmp > /dev/null
        if [ ! -f $TC_PATH_TO_BUILD ]; then
            echo "$0: ERROR - cannot find NuoDB build at $TC_PATH_TO_BUILD"
            exit 1
        fi
        tar xfz $TC_PATH_TO_BUILD ; mv $(ls -1d nuodb*linux*) nuodb
        popd > /dev/null
    fi
}

launchProvision()
{
    if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
        echo "----- Untarring NuoDB, configuring and starting agents on NuoDB hosts ${NUODB_HOSTS}..."
        echo "host string: $launchProvisionHostStr"
        tmp=/tmp/launch-provision2.$$
        mkdir -p $tmp
        brokerHost=""
        expectedBrokers=0
        expectedAgents=0
        
        for hostChunk in $(echo $launchProvisionHostStr | sed 's/;/ /g'); do
            host=$(echo $hostChunk | awk -F, '{print $1}')
            if [ "$brokerHost" == "" ]; then
                brokerHost=$host
            fi
            
            b=$(echo $hostChunk | awk -F, '{print $2}')
            if [ "$b" == "broker" ]; then
                brokerAgentFlag="true"
                let expectedBrokers++
            else
                brokerAgentFlag="false"
                let expectedAgents++
            fi
            region=$(echo $hostChunk | awk -F, '{print $3}')
            peer=$(echo $hostChunk | awk -F, '{print $4}')
            
            echo -n "-- deploying to '$host': isBroker=$brokerAgentFlag, region=$region, peer=$peer... "
            # Build up a default.properties to copy to the host
            DP=$tmp/default.properties
            rm -f $DP
            echo "domainPassword = bird" >> $DP
            echo "broker = $brokerAgentFlag" >> $DP
            echo "domain = domain" >> $DP
            echo "portRange = 48005" >> $DP
            echo "region=$region" >> $DP
            echo "balancer=ChainableLocalityBalancer,RoundRobinBalancer" >> $DP
            echo "enableAutomation=false" >> $DP
            echo "enableAutomationBootstap=false" >> $DP
            echo "peer=$peer" >>  $DP
            
            ssh $host "rm -rf $BenchTmp/nuodb ; mkdir -p $BenchTmp/nuodb; pkill -9 -x nuodb; pkill -9 -x java > /dev/null 2>&1"
            ssh $host "cd $BenchTmp; tar xfz $TC_PATH_TO_BUILD --strip-components=1 -C $BenchTmp/nuodb"
            scp -q $DP $host:$BenchTmp/nuodb/etc/default.properties > /dev/null    
            ssh $host "$BenchTmp/nuodb/bin/run-nuoagent.sh"
            sleep 3
            lastHost=$host
        done
        
        ssh $brokerHost "$BenchTmp/nuodb/bin/nuodb --version"
        showDomainCmd="ssh $brokerHost $BenchTmp/nuodb/bin/nuodbmgr --broker localhost --password bird --command \"show domain summary\""
        $showDomainCmd
        domainSummaryOut=$($showDomainCmd) > /dev/null 2>&1
        numAgents=$(echo "$domainSummaryOut" | tr ' ' '\n' | grep -c -w agent)
        numBrokers=$(echo "$domainSummaryOut" | tr ' ' '\n' | grep -c -w broker)
        
        if [ "$numBrokers" != "$expectedBrokers" ]; then
            echo "Failure starting agent(s) - we have $numBrokers instead of $expectedBrokers broker(s)"
            echo "DBT2 controller failed starting agents.  Suite instance ID '$SuiteInstanceId', test case '$TestcaseId' at $(date) with hosts ${LSB_HOSTS}" | mail -s "DBT2 benchmark errors" $EMAIL_ADDR
            exit 1
        fi
        
        if [ "$numAgents" != "$expectedAgents" ]; then
            echo "Failure starting agent(s) - we have $numAgents instead of $expectedAgents agent(s)"
            echo "DBT2 controller failed starting agents.  Suite instance ID '$SuiteInstanceId', test case '$TestcaseId' at $(date) with hosts ${LSB_HOSTS}" | mail -s "DBT2 benchmark errors" $EMAIL_ADDR
            exit 1
        fi
        
        rm -rf $tmp
    fi
}

setLatenciesForHostSet()
{
    fromHosts=$1
    toHosts=$2

    echo "----- Setting traffic control TO $toHosts FROM $fromHosts ..."
    for host in ${fromHosts}; do 
        echo "--- Running tc on $host..."
        # SSH to a host and use TC to add 20ms latency on the active network interface to every host in the other datacenter (dc0hosts)
        # YOU MAY HAVE TO ALTER THE LINE BEGINNING WITH nicName TO GET THE NAME OF THE NETWORK INTERFACE IN-USE.
        ssh -o StrictHostKeyChecking=false -tt ${host} "
nicName=\$(netstat -nr | tail -1 | awk '{print \$8}')
sudo tc qdisc add dev \$nicName root handle 1: prio bands 10
sudo tc qdisc add dev \$nicName parent 1:1 handle 10: netem delay ${TC_1WAY_LATENCY_MS}ms
for h in ${toHosts}; do
sudo tc filter add dev \$nicName protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 match ip dst \$(nslookup \$h | awk '/^Address: / { print \$2 }') flowid 10:1 
ping -c 1 \$h
done
ping -c 1 core
"
    done
}

setupDataCenterLatency()
{
    if [ "${TC_1WAY_LATENCY_MS}" == "" ] || [ "${TC_1WAY_LATENCY_MS}" == "0" ]; then
        echo "----- Since TC_1WAY_LATENCY_MS unset or set to 0 ms - will not add latency."
        return
    fi
    
    # Setup latency on network interfaces for multi-data-center test cases
    if [ "${TC_NUM_DATACENTERS}" == "2" ]; then
        echo "----- !!! CHECK PING STATISTICS BELOW TO VERIFY LATENCY. !!!"
        setLatenciesForHostSet "${dc0hosts}" "${dc1hosts}"
        setLatenciesForHostSet "${dc1hosts}" "${dc0hosts}"
    elif [ "${TC_NUM_DATACENTERS}" == "3" ]; then
        echo "----- !!! CHECK PING STATISTICS BELOW TO VERIFY LATENCY. !!!"
        setLatenciesForHostSet "${dc0hosts}" "${dc1hosts} ${dc2hosts}"
        setLatenciesForHostSet "${dc1hosts}" "${dc0hosts} ${dc2hosts}"
        setLatenciesForHostSet "${dc2hosts}" "${dc0hosts} ${dc1hosts}"
    elif [ "${TC_NUM_DATACENTERS}" == "4" ]; then
        echo "----- !!! CHECK PING STATISTICS BELOW TO VERIFY LATENCY. !!!"
        setLatenciesForHostSet "${dc0hosts}" "${dc1hosts} ${dc2hosts} ${dc3hosts}"
        setLatenciesForHostSet "${dc1hosts}" "${dc0hosts} ${dc2hosts} ${dc3hosts}"
        setLatenciesForHostSet "${dc2hosts}" "${dc0hosts} ${dc1hosts} ${dc3hosts}"
        setLatenciesForHostSet "${dc3hosts}" "${dc0hosts} ${dc1hosts} ${dc2hosts}"
    elif [ "${TC_NUM_DATACENTERS}" == "5" ]; then
        echo "----- !!! CHECK PING STATISTICS BELOW TO VERIFY LATENCY. !!!"
        setLatenciesForHostSet "${dc0hosts}" "${dc1hosts} ${dc2hosts} ${dc3hosts} ${dc4hosts}"
        setLatenciesForHostSet "${dc1hosts}" "${dc0hosts} ${dc2hosts} ${dc3hosts} ${dc4hosts}"
        setLatenciesForHostSet "${dc2hosts}" "${dc0hosts} ${dc1hosts} ${dc3hosts} ${dc4hosts}"
        setLatenciesForHostSet "${dc3hosts}" "${dc0hosts} ${dc1hosts} ${dc2hosts} ${dc4hosts}"
        setLatenciesForHostSet "${dc4hosts}" "${dc0hosts} ${dc1hosts} ${dc2hosts} ${dc3hosts}"
    fi    
}

startDB()
{
    storageGroup=0
    smsForThisStorageGroup=0
    storageGroupNames=""
    for host in ${SM_HOSTS}; do
        smPerHostCount=0
        while [ $smPerHostCount -lt $TC_NUM_SMS_PER_SMHOST ]; do
            archiveDir=${NUODB_ARCHIVE_DIR}_sm${smPerHostCount}
            journalDir=${NUODB_JOURNAL_DIR}_sm${smPerHostCount}
            if [ "$TC_USE_EXISTING_DB" != "true" ]; then
                ssh -q -o StrictHostKeyChecking=false -tt $host "
sudo rm -rf $archiveDir
sudo mkdir -p $archiveDir
sudo chmod 777 $archiveDir"
            fi
            ssh -q -o StrictHostKeyChecking=false -tt $host "
sudo rm -rf $journalDir
sudo mkdir -p $journalDir
sudo chmod 777 $journalDir
"
            # If Journal or Archive on SSD, then run fstrim on it
            echo "$NUODB_ARCHIVE_DIR $NUODB_JOURNAL_DIR" | grep '/ssd' > /dev/null
            if [ "$?" -eq "0" ]; then
                echo "----- Running fstrim on SSDs on $host..."
                ssh -tt -o StrictHostKeyChecking=false $host "for x in /ssd* ; do sudo fstrim \$x; done" 
            fi
            if [ "$TC_STORAGEGROUPS" == "true" ]; then
                if [ $smsForThisStorageGroup -eq 0 ]; then
                    currentSg=0
                    storageGroupNames=""
                    while [ $currentSg -lt $TC_NUM_STORAGEGROUPS_PER_SM ]; do
                        storageGroupNames="$storageGroupNames,SG${storageGroup}"
                        let storageGroup++
                        let currentSg++
                    done
                    storageGroupNames=$(echo $storageGroupNames | sed 's/^,//')
                    storageGroupString="--storage-group $storageGroupNames "
                fi
                let smsForThisStorageGroup++
                if [ $smsForThisStorageGroup -ge $TC_NUM_SMS_PER_STORAGEGROUP ]; then
                    smsForThisStorageGroup=0
                fi
                echo "----- SM host $host will use '$storageGroupString'"
            else
                storageGroupString=""
            fi
            echo "----- starting SM on $host..."
            initFlag="yes"
            if [ "$TC_USE_EXISTING_DB" == "true" ]; then
                initFlag="no"
            fi

            mgr "start process sm host $host:$BROKER_PORT database $NUODB_DATABASE archive $archiveDir initialize $initFlag options '${storageGroupString}--journal $TC_JOURNAL --trace none --mem $TC_SM_MEM_SETTING --journal-sync-method $TC_JOURNAL_SYNC_METHOD --journal-max-file-size-bytes $TC_JOURNAL_MAX_FILE_SIZE_BYTES --journal-dir $journalDir $SMOPTS'"
            let smPerHostCount++
        done
    done
    export NUM_SGS=$storageGroup
    for host in ${TE_HOSTS}; do
        echo "----- starting TE on $host..."
        mgr "start process te host $host:$BROKER_PORT database $NUODB_DATABASE options '--journal $TC_JOURNAL --dba-user $DATABASE_USER --dba-password $DATABASE_PASSWORD --trace none --mem $TC_TE_MEM_SETTING --commit $TC_COMMIT $TEOPTS'"
    done
    nuoSql "set system property SKIP_UNCOMMITTED_INSERTS=true;"
}

warmDatabase()
{
    if [ "${TC_WARMUP_DB}" == "true" ]; then
        WCHUNK=`expr ${TC_WAREHOUSES} / ${#TE_HOSTS_ARR[@]}`
        WMIN=1

        
        for H in ${TE_HOSTS}; do
            SQL="insert into warehouse values(${WMIN}, 'foo', 'foo', 'foo', 'foo', 'MA', '123456789', 1, 1);
         insert into district values(1, ${WMIN}, 'foo', 'foo', 'foo', 'foo', 'MA', '123456789', 1, 1, 1);
         insert into customer values(1, 1, ${WMIN}, 'foo', 'ab', 'foo', 'foo', 'foo', 'foo', 'MA', '123456789', '1234', now(), 'oo', 1, 1, 1, 1, 1, 1, 'foo');
         insert into new_order values(2101, 1, ${WMIN});
         insert into orders values(1, 1, ${WMIN}, 5, now(), 0, 0, 0);
         insert into order_line values(1, 1, ${WMIN}, 1, 0, 1, now(), 0, 0, 'aaa');
         insert into stock values(1, ${WMIN}, 5, 'aa', 'bb', 'cc', 'dd', 'ee', 'ff', 'gg', 'hh', 'ii', 'jj', 5, 5, 5, 'foo');"
            
            CMD="echo -e \"$SQL\" > /tmp/warmup.sql ; ${NUODB_HOME}/bin/nuosql ${NUODB_DATABASE}@localhost --user ${DATABASE_USER} --password ${DATABASE_PASSWORD} --schema dbt2 --file /tmp/warmup.sql ; rm -f /tmp/warmup.sql"
            
            echo "----- Warming up database on ${H}..."
            ssh -o StrictHostKeyChecking=false ${H} "${CMD}"
            WMIN=`expr ${WMIN} + ${WCHUNK}`
        done
    fi
}

query_partition_atoms() {
    SQL="select a.* from system.localatoms a, system.localtableatoms b where b.tablename='$1' and (a.catalogId=b.tableCatalogId"
    for ((p=1; p <= $TC_NUM_PARTITIONS; p++)) do
        SQL="$SQL or a.catalogId=b.tableCatalogId + $(($p*2))"
    done
    SQL="$SQL ) order by a.chairman,a.catalogid;"

    echo $SQL >> ${atomSqlFile}
}

getAtomInfo()
{
    echo "----- Querying atom info on all TEs..."
    outFile=$1
    echo "" > ${atomSqlFile}
    
    query_partition_atoms "WAREHOUSE"
    query_partition_atoms "DISTRICT"
    query_partition_atoms "CUSTOMER"
    query_partition_atoms "NEW_ORDER"
    query_partition_atoms "ORDERS"
    query_partition_atoms "ORDER_LINE"
    query_partition_atoms "STOCK"

    for H in ${TE_HOSTS}; do
        scp -q ${atomSqlFile} ${H}:${BenchTmp}
        CMD="${NUODB_HOME}/bin/nuosql ${NUODB_DATABASE}@localhost --user ${DATABASE_USER} --password ${DATABASE_PASSWORD} --schema dbt2 --file ${atomSqlFile} > ${LogsTmp}/${outFile}-${H}.txt"            
        ssh -o StrictHostKeyChecking=false ${H} "${CMD}"
    done
}

restartAgents() {
    if [ "$TC_SKIP_INSTALL_START_AGENTS" != "true" ]; then
        echo "----- Stopping and restarting agents..."
        for host in ${LSB_HOSTS}; do        
            ssh -o StrictHostKeyChecking=false $host killall -9 java > /dev/null 2>&1
            sleep 2
            ssh -o StrictHostKeyChecking=false $host rm -rf ${NUODB_HOME}/var/opt/Raft
        done
        for host in ${LSB_HOSTS}; do
            echo "----- Checking $host for running agent:"
            ssh -o StrictHostKeyChecking=false $host ps -ef | grep java | grep -v grep
        done
        sleep 15
        for host in ${LSB_HOSTS}; do
            echo -n "$host ... "
            ssh -o StrictHostKeyChecking=false $host ${NUODB_HOME}/bin/run-nuoagent.sh
            sleep 1
        done
        sleep 15
    fi
}

restartDB()
{
    echo "----- Shutting down domain and waiting 30 seconds..."
    mgr "shutdown domain"
    sleep 30

    restartAgents
    
    for host in ${SM_HOSTS}; do
        smPerHostCount=0
        while [ $smPerHostCount -lt $TC_NUM_SMS_PER_SMHOST ]; do
            archiveDir=${NUODB_ARCHIVE_DIR}_sm${smPerHostCount}
            journalDir=${NUODB_JOURNAL_DIR}_sm${smPerHostCount}
            ssh -o StrictHostKeyChecking=false $host "
rm -rf $journalDir
mkdir -p $journalDir
chmod 777 $TC_JOURNAL_PATH 
"
            echo "----- starting SM on $host..."
            mgr "start process sm host $host:$BROKER_PORT database $NUODB_DATABASE archive $archiveDir initialize no options '--journal $TC_JOURNAL --trace none --mem $TC_SM_MEM_SETTING --journal-sync-method $TC_JOURNAL_SYNC_METHOD --journal-max-file-size-bytes $TC_JOURNAL_MAX_FILE_SIZE_BYTES --journal-dir $journalDir $SMOPTS'"
            let smPerHostCount++
        done
    done
    for host in ${TE_HOSTS}; do
        echo "----- starting TE on $host..."
        mgr "start process te host $host:$BROKER_PORT database $NUODB_DATABASE options '--journal $TC_JOURNAL --dba-user $DATABASE_USER --dba-password $DATABASE_PASSWORD --trace none --mem $TC_TE_MEM_SETTING --commit $TC_COMMIT $TEOPTS'"
    done
    nuoSql "set system property SKIP_UNCOMMITTED_INSERTS=true;"
}

captureSetup() {
    setupFile="nuodb-setup"
    
    dbpids=$(mgr "show domain summary" | awk '/pid/{print $7}' | tr '\n' ' ')
    
    $NUODB_HOME/bin/nuodb --version > $setupFile
    mgr "show domain summary" >> $setupFile
    for line in $(mgr "show domain summary" |grep RUNNING | sed 's/\// /'|awk '{print $2 "," $8}'); do
        host=$(echo $line | cut -d, -f1)
        pid=$(echo $line | cut -d, -f2)
        mgr "show process config host $host:$BROKER_PORT pid $pid" >> $setupFile
    done
    nuoSql "show" >> $setupFile

    mgr "show domain summary"
    mgr "show storagegroups"
}

mgr() {
    echo "----- nuodbmanager: executing '$1'"
    java -jar $NUODB_HOME/jar/nuodbmanager.jar --broker $BROKER_HOST:$BROKER_PORT --user domain --password bird --command "$1"
}

nuoSql() {
    sqlCmd=$1
    echo "----- nuosql: executing ${sqlCmd}..."
    echo ${sqlCmd} | ${NUODB_HOME}/bin/nuosql ${NUODB_DATABASE}@${BROKER_HOST} --user ${DATABASE_USER} --password ${DATABASE_PASSWORD}
}

interrupted() {
    postClean
    echo "<<<<<<<<<< Aborting $0 with benchmark '$BenchSuite' on $(date)" 
    exit 1
}

loadDB()
{
    if [ "$TC_USE_EXISTING_DB" != "true" ]; then        
        export DB_HOST=$BROKER_HOST
        export DB_PORT=$BROKER_PORT
        export DB_NAME=dbt2
        export DB_USER=$DATABASE_USER
        export DB_PASSWORD=$DATABASE_PASSWORD
        export DB_DATA="${LogsTmp}/dbt2data"
        export DB_LOGS="${LogsTmp}/dbt2logs"
        
        mkdir -p ${DB_DATA}
        mkdir -p ${DB_LOGS}
        
        PARAMS="-N -w ${TC_WAREHOUSES} -v -g"
        
        # generate a CSV list of storage groups
        if [ "$TC_STORAGEGROUPS" == "true" ]; then
            x=0
            SGCSL=""
            # let NUM_SGS=TC_NUM_SMS*TC_NUM_STORAGEGROUPS_PER_SM
            while [ $x -lt $NUM_SGS ]; do
                SGCSL="${SGCSL},SG${x}"
                let x++
            done
            SGCSL=$(echo $SGCSL | sed 's/^,//')
            PARAMS="$PARAMS -m $SGCSL -t $TC_NUM_PARTITIONS"
        fi
        ${DBT2Home}/bin/dbt2-nuodb-load-db ${PARAMS}
        #TODO: what's put in DB_DATA above and how long does it stick around?
        echo "----- Sleeping 1 minute after load..."
        sleep 60
    fi
}

startNmon()
{
    echo "----- Starting NMON on all NuoDB hosts..."
    for host in ${TE_HOSTS} ${SM_HOSTS}; do
        ssh $host nmon -F ${LogsTmp}/${host}.nmon -s5 -c10000 
    done
}

startClient()
{
    echo "----- start monitor and trace..."
    mgr "monitor database dbt2" > ${BenchTmp}/nuodb-stats.log 2>&1 &
    mgr "trace domain" > ${BenchTmp}/nuodb-trace.log 2>&1 &
    
    echo "----- Starting dbt2-client on ${TE_HOSTS}..."
    for client in ${TE_HOSTS}; do
        clientStartCmd="LD_LIBRARY_PATH=${NUODB_HOME}/lib64 ${DBT2Home}/bin/dbt2-client -f -c $TC_NUM_DB_CONNS_PER_TE -d dbt2 -h localhost -l 48004 -u $DATABASE_USER -a $DATABASE_PASSWORD -o ${LogsTmp} > ${LogsTmp}/dbt2-client.log 2>&1 &"
        echo $clientStartCmd
        ssh -o StrictHostKeyChecking=false $client "$clientStartCmd"
    done
    sleep 5
    
    WCHUNK=$(expr ${TC_WAREHOUSES} / ${#TE_HOSTS_ARR[*]})
    WMIN=1
    WMAX=$WCHUNK
    echo "----- Starting dbt2-driver on ${TE_HOSTS} at $(date)..."
    for client in ${TE_HOSTS}; do
        driverStartCmd="${DBT2Home}/bin/dbt2-driver -d localhost -l ${TC_DURATION_SEC} -wmin ${WMIN} -wmax ${WMAX} -w ${TC_WAREHOUSES} -sleep 1000 -ktd 0 -ktn 0 -kto 0 -ktp 0 -kts 0 -ttd 0 -ttn 0 -tto 0 -ttp 0 -tts 0 -outdir ${LogsTmp} > ${LogsTmp}/dbt2-driver.log 2>&1"
        echo $driverStartCmd
        ssh -o StrictHostKeyChecking=false $client "$driverStartCmd" &
        childPids="$childPids $!"
        WMIN=`expr ${WMIN} + ${WCHUNK}`
        WMAX=`expr ${WMAX} + ${WCHUNK}`
    done
    
    echo "----- waiting for all dbt2-driver processes to finish..."
    wait $childPids
    sleep 10
    ps -ef|grep nuodbmanager|grep -v grep|awk '{print $2}'|xargs kill > /dev/null 2>&1 
}

stopNmon()
{
    echo "----- Stopping NMON on all NuoDB hosts..."
    for host in ${TE_HOSTS} ${SM_HOSTS}; do
        ssh $host killall nmon > /dev/null 2>&1
    done
}

getAndProcessClientStats()  
{
    echo "----- Collecting stats from DBT-2 clients..."
    mkdir -p ${BenchTmp}/logs-work/nmon
    for client in ${TE_HOSTS} ${SM_HOSTS}; do
        ssh -o StrictHostKeyChecking=false $client "cd ${LogsTmp}/.. ; rm -rf ${LogsTmp}/dbt2data ; mv logs ${client}-logs ; tar cf ${client}.tar ${client}-logs ; mv ${client}-logs logs"
        scp -q $client:${LogsTmp}/../${client}.tar ${BenchTmp}/${client}-logs.tar
        pushd ${BenchTmp}/logs-work > /dev/null
        tar xf ${BenchTmp}/${client}-logs.tar
        popd > /dev/null
    done

    pushd ${BenchTmp}/logs-work > /dev/null
    captureSetup
    mv *-logs/*.nmon ${BenchTmp}/logs-work/nmon
    popd > /dev/null

    mv ${BenchTmp}/nuodb-stats.log ${BenchTmp}/logs-work
    mv ${BenchTmp}/nuodb-trace.log ${BenchTmp}/logs-work
    
    cat ${BenchTmp}/logs-work/*-logs/mix.log | sort -t ',' -k 1 > ${BenchTmp}/mixall.log
    $DBT2Home/bin/dbt2-post-process ${BenchTmp}/mixall.log | tee ${BenchTmp}/logs-work/results.txt
    cat ${BenchTmp}/logs-work/results.txt | mail -s "DBT2 Results, suite instance ID '$SuiteInstanceId', test case '$TestcaseId'" $EMAIL_ADDR
    for client in ${TE_HOSTS}; do
        clientLog=${BenchTmp}/logs-work/${client}-logs/mix.log
        if [ -f ${clientLog} ]; then
            cat ${clientLog} | sort -t ',' -k 1 > ${BenchTmp}/mix-sorted.log
            $DBT2Home/bin/dbt2-post-process ${BenchTmp}/mix-sorted.log > ${BenchTmp}/logs-work/${client}-logs/results.txt
            rm -f ${BenchTmp}/mix-sorted.log
        fi
    done
}

checkForErrors()
{
    echo "----- Checking for error count..."
    pushd ${BenchTmp}/logs-work > /dev/null
    errorCount=$(wc -l *-logs/error.log | tail -1 | awk '{print $1}')
    if [ $errorCount -gt 500 ]; then
        errorMsg="DBT-2, suite instance ID '$SuiteInstanceId', test case '$TestcaseId' has $errorCount line(s) of errors in the error.log files"
        echo $errorMsg | mail -s "DBT-2 errors" $EMAIL_ADDR
        echo "ERRORS: $errorMsg"
    fi
    popd > /dev/null
}

archiveClientStats()  
{
    # Move all logs to a directory named with the test case number.
    mv ${BenchTmp}/logs-work ${BenchTmp}/${TestcaseId}
    
    # Make tarball of new logs directory, created in permanent log archive
    StatsDir=${BenchOutputRoot}/${BenchSuite}/${SuiteInstanceId}
    mkdir -p ${StatsDir}
    pushd ${BenchTmp} > /dev/null
    tar cfz ${StatsDir}/${TestcaseId}.tgz ${TestcaseId}
    popd > /dev/null
}

testAndGetNetworkStats()
{    
    for host in ${LSB_HOSTS}; do
        echo ----- $host -------------------------------------------
        ssh $host "killall -q nc ; nc -l $NCPort > /dev/null &"
        sleep 2
        ncOut=$(/usr/bin/time -p cat $BigNCTestFile | nc $host $NCPort)
        echo $ncOut | grep -i real
        iface=$(ssh -o StrictHostKeyChecking=false $host netstat -i | egrep -i eth\|enp |grep BMRU|awk '{print $1}')
        #	ssh -t $host sudo ethtool $iface | grep Speed
        ssh  $host /sbin/ifconfig $iface
    done    
}

#------------------------------------------------------------------------------
# add /bin to PATH if necessary
which hostname >& /dev/null
if [ $? -ne 0 ]; then
    export PATH=$PATH:/bin
fi

declare -a brokerForRegion
declare -a SM_HOSTS_ARR
declare -a TE_HOSTS_ARR
declare dc0hosts
declare dc1hosts
declare dc2hosts
declare dc3hosts
declare dc4hosts

. $(dirname $0)/variables.sh    

handleArgs $*

SuiteVariablesScript=${BenchScriptsDir}/test-case-definitions/default-suite-variables.sh
if [ -f ${SuiteVariablesScript} ]; then
    . ${SuiteVariablesScript}
fi

. ${TestcaseConfigFile}

if [ "$DBT2Home" == "" ]; then
    echo "ERROR: DBT2Home should be defined in variables.sh."
    exit 1
fi
if [ "$TC_SKIP_INSTALL_START_AGENTS" == "true" ]; then
    if [ "$NUODB_HOME" == "" ] || [ ! -e $NUODB_HOME/bin/nuodb ]; then
        echo "ERROR: NUODB_HOME undefined or can't find NUODB_HOME/bin/nuodb."
        exit 1
    fi    
else
    export NUODB_HOME=$BenchTmp/nuodb
fi

preClean
initialize
extractNuoDBForController
echo "----- Testing network and collecting stats..."
# testAndGetNetworkStats > ${BenchTmp}/logs-work/network-stats-BEFORE.txt 2>&1 
launchProvision
startDB
loadDB
restartDB
warmDatabase
getAtomInfo atomInfoAfterWarmup
startNmon
setupDataCenterLatency
startClient
getAtomInfo atomInfoAfterBenchmark
stopNmon
echo "----- Testing network and collecting stats..."
testAndGetNetworkStats > ${BenchTmp}/logs-work/network-stats-AFTER.txt 2>&1 
getAndProcessClientStats
checkForErrors
archiveClientStats
postClean
echo "<<<<<<<<<< Finished $0 with suite instance ID '$SuiteInstanceId', test case '$TestcaseId' at $(date) with hosts ${LSB_HOSTS}..." 
