#!/bin/sh

path=$(cd ../ ; pwd)
redir_port="$(cat ${path}/clash/config.yaml | grep "redir-port" | awk -F ':' '{print $2}' )"
echo $redir_port