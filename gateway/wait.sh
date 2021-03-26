#!/bin/sh

start_file="/home/user/start"
while [ ! -f $start_file ]; do
	sleep 1
done
exec $@
