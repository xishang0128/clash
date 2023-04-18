#!/bin/sh

scripts_dir=$(dirname `realpath $0`)

source ${scripts_dir}/config

service_path="${scripts_dir}/service.sh"
tproxy_path="${scripts_dir}/iptables.sh"

events=$1
monitor_dir=$2
monitor_file=$3

service_control() {
  if [ ! -f ${box_path}/manual ] ; then
    if [ "${monitor_file}" = "disable" ] ; then
      if [ "${events}" = "d" ] ; then
        ${service_path} start >> ${run_path}/run.log 2>> ${run_path}/run_error.log && \
        ${tproxy_path} enable >> ${run_path}/run.log 2>> ${run_path}/run_error.log
      elif [ "${events}" = "n" ] ; then
        ${tproxy_path} disable >> ${run_path}/run.log 2>> ${run_path}/run_error.log && \
        ${service_path} stop >> ${run_path}/run.log 2>> ${run_path}/run_error.log
      fi
    fi
  fi
}

mkdir -p ${run_path}

service_control