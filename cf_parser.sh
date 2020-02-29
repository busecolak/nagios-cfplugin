#!/bin/bash

appstatus=0
usagestatus=0
usagestatusarray=()
criticallimit=80.0
warninglimit=70.0
cpuwarninglimit=50.0

cfparse_output(){

    # arguments of this method. cfapp_output refers to output of "cf app" command from CF CLI.
    cfapp_output="$1"
    appname="$2"
    hostname="$3"

    # this gets the instance(s) information of cf app output such as #0 #1
    instanceinfo="$(echo -e "$cfapp_output" | grep "^#")"

    # these get the instance number (1/1) and state
    cf_state="$(echo "$cfapp_output" | grep "requested state:" | awk '{print $3}')"
    instances="$(echo "$cfapp_output" | grep "instances:" | awk '{print $2}')"

    # write info to influx
    app_info_to_influx "$instanceinfo"
    exit_code
}

app_info_to_influx() {

    # get instance info and make it one intance in a line if multiple
    instanceinfo=$(echo -e "$1" | sed -e "s/ #/\n#/g")

    # keep intance info of every intance in an array
    readarray -t instance_info_array <<<"$(echo -e "$instanceinfo")"
    i=0
    for instance_info in "${instance_info_array[@]}"
    do
        # for each instance parse the info then write to influx
        cfparse_appinfo
        cfparse_state
        write_to_influx
        i=i+1
    done
}

cfparse_appinfo() {
    # appinfo=(instance state uptime cpu memoryusage of maxmemory diskusage of maxdisk)

    # per instance parce the info indicated above by spliting with space character
    appinfo_array=($(echo $instance_info | egrep -i [" "]))

    # for memoryusage maxmemory diskusage and maxdisk
    for i in 4 6 7 9
    do
        # convert format to mb format
        appinfo_array[i]=$(convert_to_m ${appinfo_array[i]})
    done

    cpu_percent=${appinfo_array[3]::-1}
    memory_percent=$(calculate_percent ${appinfo_array[4]} ${appinfo_array[6]})
    disk_percent=$(calculate_percent ${appinfo_array[7]} ${appinfo_array[9]})

    if (( $(echo "$memory_percent > $criticallimit" |bc -l) )) || (( $(echo "$disk_percent > $criticallimit" |bc -l) )) || (( $(echo "$cpu_percent > $criticallimit" |bc -l) )); then
        usagestatusarray[$i]="2"
    elif (( $(echo "$memory_percent > $warninglimit" |bc -l) )) || (( $(echo "$disk_percent > $warninglimit" |bc -l) )) || (( $(echo "$cpu_percent > $cpuwarninglimit" |bc -l) )); then
        usagestatusarray[$i]="1"
    else
		usagestatusarray[$i]="0"
	fi
}

cfparse_state(){

    # parse instance numbers such as 1/1
    instance_count=(${instances//// })
    active_instances=${instance_count[0]}
    total_instances=${instance_count[1]}

    check_usage_status

    # generate the status
    zero=0

    if [ "${cf_state}" == "started" ]; then

        if [ "$active_instances" -eq "$zero" ]; then
            #echo "CRITICAL - There is no active instance for $appname"
            appstatus="2"
            state="CRITICAL"
        elif [ "$active_instances" -lt "$total_instances" ]; then
            #echo "WARNING - All instances of $appname are not running"
            appstatus="1"
            state="WARNING"
        elif [ "$active_instances" -eq "$total_instances" ]; then
            state="OK"
            #echo "OK - All instances running for $appname"
            #appstatus="0"
        else
            #echo "UNKNOWN - Unknown instance status for $appname"
            appstatus="3"
            state="UNKNOWN"
        fi

		if [ "$usagestatus" -eq 2 ]; then
			#echo "CRITICAL - Memory or disk usage exceeded the critical limit"
			appstatus="2"
			state="CRITICAL"
		elif [ "$usagestatus" -eq 1 ]; then
			#echo "WARNING - Memory or disk usage exceeded the warning limit"
			appstatus="1"
			state="WARNING"
		else
			appstatus="0"
			state="OK"
		fi

	elif [ "${cf_state}" == "stopped" ]; then
		#echo "CRITICAL - $appname is not running"
		appstatus="2"
		state="CRITICAL"
	else
		#echo "UNKNOWN - $appname status is unknown"
		appstatus="3"
		state="UNKNOWN"
	fi
}

exit_code() {
	if [ "$appstatus" -eq 2 ]; then
		if [ "$usagestatus" -eq 2 ]; then
			echo "CRITICAL - Resource usage exceeded the critical limit"
		else
			echo "CRITICAL - There is no active instance for $appname"
		fi
		echo "$data"
		exit 2
	elif [ "$appstatus" -eq 1 ]; then
		if [ "$usagestatus" -eq 1 ]; then
			echo "WARNING - Resource usage exceeded the warning limit"
		else
			echo "WARNING - All instances of $appname are not running"
		fi
		echo "$data"
		exit 1
	elif [ "$appstatus" -eq 0 ]; then
		echo "OK - All instances running for $appname"
		echo "$data"
		exit 0
	else
		echo "UNKNOWN - $appname status is unknown"
		echo "$data"
		exit 3
	fi
}

write_to_influx(){
	if [ "$appinfo_array" == "" ]; then
		cpu=0
		memory=0
		disk=0
		instance=-1
		instance_state="none"
	else
		cpu=${appinfo_array[3]::-1}
		instance=$(echo ${appinfo_array[0]} | sed 's/^.//')
		memory=${appinfo_array[4]}
		disk=${appinfo_array[7]}
		instance_state=${appinfo_array[1]}
	fi

	data="${appname},hostname=${hostname},state=${state} instance=${instance},max_cpu=${cpu},max_memory=${memory},max_disk=${disk},app_status=${appstatus},instance_state=\"${instance_state}\""

	curl -i -XPOST 'http://localhost:8086/write?db=InfluxDB' --data-binary "$data" > /dev/null 2>&1
}

convert_to_m(){
	#convert G to M
	if [[ $1 == *G ]];then
			x=$(echo -e "$1" | sed -e "s/G//g")
			echo $(bc <<< "$x*1024")
	#delete M
	elif [[ $1 == *M ]];then
			echo $(echo -e "$1" | sed -e "s/M//g")
	else
			echo $(echo -e "$1")

	fi
}

calculate_percent(){
	usage=$1
	max=$2
	if [[ $2 != 0 ]];then
			echo $(bc <<< "scale=1; 100*$usage/$max")
	else
			echo 0
	fi
}

contains(){
	value=$1
	c_result=1
	for stat in "${usagestatusarray[@]}"
	do
		if [ "$stat" -eq "$value" ]; then
			c_result=0
		fi
	done
}

check_usage_status(){
	contains "0"
	if [ "$c_result" -eq 0 ]; then
		usagestatus="0"
	else
		contains "1"
		if [ "$c_result" -eq 0 ]; then
			usagestatus="1"
		else
			contains "2"
			if [ "$c_result" -eq 0 ]; then
				usagestatus="2"
			fi
		fi
	fi
}

cfparse_output "$1" "$2" "$3"
