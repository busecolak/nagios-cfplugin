#!/bin/bash

appname=$1
targetorg=$2

cf_output="$(cat /nagiostemp/${appname}_state_${targetorg}.txt 2>>/nagiostemp/error.txt)"

/etc/nagios3/myplugin/cf_parser.sh "$cf_output" "$appname" "$targetorg"

