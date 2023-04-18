#!/bin/sh

path=$(cd ../ ; pwd)

A=`grep dns: -n $path/clash/config.yaml | awk -F ':' '{print $1}'`
B=$(expr $A + 1)

start(){
dns2=$(cat $path/clash/config.yaml | tail -n +"$B" | head -n "1" | grep "  ")
if [ -n "$dns2" ]; then
  B=$(expr $B + 1)
  start
else
  B=$(expr $B - 1)
fi
}

start

echo A$A B$B