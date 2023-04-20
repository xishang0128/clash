#!/bin/sh

export PATH="/data/adb/magisk:/data/adb/ksu/bin:$PATH:/data/data/com.termux/files/usr/bin"

scripts_dir=$(dirname `realpath $0`)

source ${scripts_dir}/config

mkdir -p ${run_path}
mkdir -p ${path}/${bin_name}

# ${path}/bin/yq -i ".tproxy-port=${tproxy_port}" ${path}/clash/config.yaml
# ${path}/bin/yq -i ".dns.listen=\"${dns_listen}\"" ${path}/clash/config.yaml
# ${path}/bin/yq -i ".dns.fake-ip-range=\"${fakeip_range}\"" ${path}/clash/config.yaml

# ${path}/bin/yq -o=json -i "(.inbounds[] | select(.type == \"tproxy\") | .listen_port) = ${tproxy_port}" ${path}/sing-box/config.json

find ${path} -mtime +3 -type f -name "*.log" | xargs rm -f

log() {
  export TZ=Asia/Shanghai
  now=$(date +"[%Y-%m-%d %H:%M:%S %Z]")
  case $1 in
    Info)
      [ -t 1 ] && echo -e "\033[1;32m${now} [Info]: $2\033[0m" || echo "${now} [Info]: $2"
      ;;
    Warn)
      [ -t 1 ] && echo -e "\033[1;33m${now} [Warn]: $2\033[0m" || echo "${now} [Warn]: $2"
      ;;
    Error)
      [ -t 1 ] && echo -e "\033[1;31m${now} [Error]: $2\033[0m" || echo "${now} [Error]: $2"
      ;;
    *)
      [ -t 1 ] && echo -e "\033[1;30m${now} [$1]: $2\033[0m" || echo "${now} [$1]: $2"
      ;;
  esac
}

create_tun_link() {
  mkdir -p /dev/net
  [ ! -L /dev/net/tun ] && ln -s /dev/tun /dev/net/tun
}

probe_tun_device() {
  ifconfig | grep -q ${tun_device} || return 1
}

forward() {
  iptables -w 100 $1 FORWARD -o ${tun_device} -j ACCEPT
  iptables -w 100 $1 FORWARD -i ${tun_device} -j ACCEPT
  ip6tables -w 100 $1 FORWARD -o ${tun_device} -j ACCEPT
  ip6tables -w 100 $1 FORWARD -i ${tun_device} -j ACCEPT
}

check_permission() {
  if which ${bin_name} | grep -q "/system/bin/" ; then
    user=$(echo ${user_group} | awk -F ':' '{print $1}')
    group=$(echo ${user_group} | awk -F ':' '{print $2}')
    user_id=$(id -u ${user})
    group_id=$(id -g ${group})
    [ ${user_id} ] && [ ${group_id} ] || \
    (user_group="root:net_admin" && log Error "${user_group} error, use root:net_admin instead.")
    bin_path=$(which ${bin_name})
    chown ${user_group} ${bin_path}
    chmod 0700 ${bin_path}
    if [ "${user_id}" != "0" ] || [ "${group_id}" != "3005" ] ; then
      # setcap has been deprecated as it does not support binary outside of the /system/bin directory
      setcap 'cap_net_admin,cap_net_raw,cap_net_bind_service+ep' ${bin_path} || \
      (user_group="root:net_admin" && log Error "setcap authorization failed, you may need libcap package.")
    fi
    chown -R ${user_group} ${path}
    return 0
  elif [ -f ${bin_path} ] ; then
    user_group="root:net_admin"
    chown ${user_group} ${bin_path}
    chmod 0700 ${bin_path}
    chown -R ${user_group} ${path}
    return 0
  else
    return 1
  fi
}

start_bin() {
  ulimit -SHn 1000000
  case "${bin_name}" in
    clash)
      if ${bin_path} -t -d ${path}/${bin_name} > ${run_path}/check.log 2>&1 ; then
        log Info "starting ${bin_name} service."
        nohup busybox setuidgid ${user_group} ${bin_path} -d ${path}/${bin_name} > ${path}/${bin_name}/${bin_name}_$(date +%Y%m%d%H%M).log 2> ${run_path}/error_${bin_name}.log &
        echo -n $! > ${pid_file}
        return 0
      else
        log Error "configuration check failed, please check the ${run_path}/check.log file."
        return 1
      fi
      ;;
    *)
      log Error "$1 core error"
      return 2
      ;;
  esac
}

start_adgh() {
  ulimit -SHn 1000000
  if [ -f ${path}/dns/AdGuardHome.yaml ]; then
    if ${path}/bin/adgh --check-config -w ${path}/dns > ${run_path}/check.log 2>&1 ; then
      log Info "starting adghome service."
      nohup busybox setuidgid ${user_group} ${path}/bin/adgh -w ${path}/dns --pidfile ${path}/dns/.adgh.pid > /dev/null &
      return 0
    else
      log Error "configuration check failed, please check the ${run_path}/check.log file."
      return 1
    fi
  else
    log Info "starting adghome service."
    nohup busybox setuidgid ${user_group} ${path}/bin/adgh -w ${path}/dns --pidfile ${path}/dns/.adgh.pid > /dev/null &
    return 0
  fi
}

start_mos() {
  ulimit -SHn 1000000
  if [ -f ${path}/dns/mosdns.yaml ]; then
    log Info "starting adghome service."
    nohup busybox setuidgid ${user_group} ${path}/bin/mosdns start -d ${path}/clash -c ${path}/dns/mosdns.yaml > /dev/null &
    echo -n $! > ${path}/dns/.mos.pid
    if (cat /proc/$(cat ${path}/dns/.mos.pid)/cmdline | grep -q mosdns); then
      return 0
    else
      log Error "configuration check failed, please check the ${run_path}/check.log file."
      return 1
    fi
  fi
}

find_netstat_path() {
  [ -f /system/bin/netstat ] && alias netstat="/system/bin/netstat" && return 0
  [ -f /system/xbin/netstat ] && alias netstat="/system/xbin/netstat" && return 0
  return 1
}

wait_bin_listen() {
  wait_count=0
  bin_pid=$(busybox pidof ${bin_name})
  find_netstat_path && \
  check_bin_cmd="netstat -tnulp | grep -q ${bin_name}" || \
  check_bin_cmd="ls -lh /proc/${bin_pid}/fd | grep -q socket"
  while [ ${bin_pid} ] && ! eval "${check_bin_cmd}" && [ ${wait_count} -lt 100 ] ; do
    sleep 1 ; wait_count=$((${wait_count} + 1))
  done
  if [ ${bin_pid} ] && eval "${check_bin_cmd}" ; then
    return 0
  else
    return 1
  fi
}

wait_adgh_listen() {
  wait_count=0
  adgh_pid=$(busybox pidof adgh)
  find_netstat_path && \
  check_adgh_cmd="netstat -tnulp | grep -q adgh" || \
  check_adgh_cmd="ls -lh /proc/${adgh_pid}/fd | grep -q socket"
  while [ ${adgh_pid} ] && ! eval "${check_adgh_cmd}" && [ ${wait_count} -lt 100 ] ; do
    sleep 1 ; wait_count=$((${wait_count} + 1))
  done
  if [ ${adgh_pid} ] && eval "${check_adgh_cmd}" ; then
    return 0
  else
    return 1
  fi
}

wait_mos_listen() {
  wait_count=0
  mos_pid=$(busybox pidof mosdns)
  find_netstat_path && \
  check_mos_cmd="netstat -tnulp | grep -q mosdns" || \
  check_mos_cmd="ls -lh /proc/${mos_pid}/fd | grep -q socket"
  while [ ${mos_pid} ] && ! eval "${check_mos_cmd}" && [ ${wait_count} -lt 100 ] ; do
    sleep 1 ; wait_count=$((${wait_count} + 1))
  done
  if [ ${mos_pid} ] && eval "${check_mos_cmd}" ; then
    return 0
  else
    return 1
  fi
}

display_bin_status() {
  if bin_pid=$(busybox pidof ${bin_name}) ; then
    log Info "${bin_name} has started with the $(stat -c %U:%G /proc/${bin_pid}) user group."
    log Info "${bin_name} service is running. ( PID: ${bin_pid} )"
    log Info "${bin_name} memory usage: $(cat /proc/${bin_pid}/status | grep -w VmRSS | awk '{print $2$3}')"
    log Info "${bin_name} cpu usage: $((/system/bin/ps -eo %CPU,NAME | grep ${bin_name} | awk '{print $1"%"}') 2> /dev/null || dumpsys cpuinfo | grep ${bin_name} | awk '{print $1}')"
    log Info "${bin_name} running time: $(busybox ps -o comm,etime | grep ${bin_name} | awk '{print $2}')"
    echo -n ${bin_pid} > ${pid_file}
    return 0
  else
    log Warn "${bin_name} service is stopped."
    return 1
  fi
}

start_service() {
  if check_permission ; then
    log Info "${bin_name} will be started with the ${user_group} user group."
    [ "${proxy_method}" != "TPROXY" ] && create_tun_link
    if start_bin && wait_bin_listen ; then
      log Info "${bin_name} service is running. ( PID: $(cat ${pid_file}) )"
      probe_tun_device && forward -I
      if [ "$adgh" = "true" ]; then
        if start_adgh && wait_adgh_listen ; then
          log Info "adg home service is running. ( PID: $(cat ${path}/dns/.adgh.pid) )"
        fi
      fi
      if [ "$mosdns" = "true" ]; then
        if start_mos && wait_mos_listen ; then
          log Info "adg home service is running. ( PID: $(cat ${path}/dns/.mos.pid) )"
        fi
      fi
      return 0
    else
      if bin_pid=$(pidof ${bin_name}) ; then
        log Warn "${bin_name} service is running but may not listening. ( PID: ${bin_pid} )"
        probe_tun_device && forward -I
        return 0
      else
        log Error "start ${bin_name} service failed, please check the ${run_path}/error_${bin_name}.log file."
        rm -f ${pid_file} >> /dev/null 2>&1
        return 1
      fi
    fi
  else
    log Error "missing ${bin_name} core, please download and place it in the ${path}/bin/ directory"
    return 2
  fi
}

stop_service() {
  if display_bin_status ; then
    log Warn "stopping ${bin_name} service."
    kill $(cat ${pid_file}) || killall ${bin_name}
    forward -D >> /dev/null 2>&1
    sleep 1
    display_bin_status
    if [ "$adgh" = "true" ]; then
      kill $(cat  ${path}/dns/.adgh.pid) || killall adgh
    fi
    if [ "$mosdns" = "true" ]; then
      kill $(cat  ${path}/dns/.mos.pid) || killall mos
    fi
  fi
  rm -f ${pid_file} >> /dev/null 2>&1
}

case "$1" in
  start)
    display_bin_status || start_service
    ;;
  stop)
    stop_service
    ;;
  restart)
    stop_service
    sleep 2
    start_service
    ;;
  status)
    display_bin_status
    ;;
  *)
    log Error "$0 $1 usage: $0 {start|stop|restart|status}"
    ;;
esac