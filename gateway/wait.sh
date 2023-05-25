#!/bin/sh

# wait for USR1
sleep infinity & PID=$!
trap "kill $PID" USR1
wait

exec $@
