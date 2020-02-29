#!/bin/bash

cf t -o "$targetorg" -s "$targetspace"
cf app app1 $> /nagiostemp/app1_state_${targetorg}.txt
cf app app2 $> /nagiostemp/app2_state_${targetorg}.txt
