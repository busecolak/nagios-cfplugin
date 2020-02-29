#!/bin/bash

queuename=$1
targetorg=$2

python /etc/nagios3/myplugin/queue_parser.py "$queuename" "$targetorg"
