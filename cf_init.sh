#!/bin/bash

cf_bin="/usr/bin/cf"
cf_api="$CF_API"
targetorg="$TARGET_ORG"
targetspace="$TARGET_SPACE"

if [ ! -x $cf_bin ] ; then
    echo "*** cf initialize failed no binary "
    exit 1
fi

echo "$cf_sso" | $cf_bin login -o $targetorg -s $targetspace --sso
if [ $? -ne 0 ]; then
	echo "*** cf login --sso failed ORG: $targetorg SPACE: $targetspace ***"
    exit 1
fi