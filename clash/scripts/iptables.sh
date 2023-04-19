#!/bin/sh

export PATH="/data/adb/magisk:/data/adb/ksu/bin:$PATH:/data/data/com.termux/files/usr/bin"

scripts_dir=$(dirname `realpath $0`)

source ${scripts_dir}/config
id="222"
# routing_mark="233"

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

uid_list=()
find_packages_uid() {
  for user_package in ${user_packages_list[@]} ; do
    user=$(echo ${user_package} | awk -F ':' '{print $1}')
    package=$(echo ${user_package} | awk -F ':' '{print $2}')
    uid_list[${#uid_list[@]}]=$(expr ${user} \* "100000" + $(cat /data/system/packages.list | grep ${package} | awk '{print $2}'))
  done
}

probe_user_group() {
  if bin_pid=$(busybox pidof ${bin_name}) ; then
    user=$(stat -c %U /proc/${bin_pid})
    group=$(stat -c %G /proc/${bin_pid})
    return 0
  else
    user=$(echo ${user_group} | awk -F ':' '{print $1}')
    group=$(echo ${user_group} | awk -F ':' '{print $2}')
    return 1
  fi
}

start_redirect() {
  ${iptables} -t nat -N EXTERNAL
  ${iptables} -t nat -F EXTERNAL
  ${iptables} -t nat -N LOCAL
  ${iptables} -t nat -F LOCAL

  ${iptables} -t nat -A EXTERNAL -p udp --dport 53 -j REDIRECT --to-ports ${dns_port}
  ${iptables} -t nat -A LOCAL -p udp --dport 53 -j REDIRECT --to-ports ${dns_port}
  ${iptables} -t nat -A EXTERNAL -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1
  ${iptables} -t nat -A LOCAL -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1

  for subnet in ${intranet[@]} ; do
    ${iptables} -t nat -A EXTERNAL -d ${subnet} -j RETURN
    ${iptables} -t nat -A LOCAL -d ${subnet} -j RETURN
  done

  ${iptables} -t nat -A EXTERNAL -p tcp -i lo -j REDIRECT --to-ports ${redir_port}

  if [ "${ap_list}" != "" ] ; then
    for ap in ${ap_list[@]} ; do
      ${iptables} -t nat -A EXTERNAL -p tcp -i ${ap} -j REDIRECT --to-ports ${redir_port}
    done
    log Info "${ap_list[*]} transparent proxy."
  fi

  ${iptables} -t nat -I PREROUTING -j EXTERNAL


  ${iptables} -t nat -I LOCAL -m owner --uid-owner ${user} --gid-owner ${group} -j RETURN

  if [ "${ignore_out_list}" != "" ] ; then
    for ignore in ${ignore_out_list[@]} ; do
      ${iptables} -t nat -I LOCAL -o ${ignore} -j RETURN
    done
    log Info "${ignore_out_list[*]} ignore transparent proxy."
  fi

  if [ "${proxy_mode}" = "blacklist" ] ; then
    if [ "${uid_list}" = "" ] ; then
      # Route Everything
      ${iptables} -t nat -A LOCAL -p tcp -j REDIRECT --to-ports ${redir_port}
      log Info "transparent proxy for all apps."
    else
      # Bypass apps
      for appid in ${uid_list[@]} ; do
        ${iptables} -t nat -I LOCAL -m owner --uid-owner ${appid} -j RETURN
      done
      # Allow !app
      ${iptables} -t nat -A LOCAL -p tcp -j REDIRECT --to-ports ${redir_port}
      log Info "proxy mode: ${proxy_mode}, ${user_packages_list[*]} no transparent proxy."
    fi
  elif [ "${proxy_mode}" = "whitelist" ] ; then
    # Route apps to Box
    for appid in ${uid_list[@]} ; do
      ${iptables} -t nat -A LOCAL -p tcp -m owner --uid-owner ${appid} -j REDIRECT --to-ports ${redir_port}
    done
    ${iptables} -t nat -A LOCAL -p tcp -m owner --uid-owner 0 -j REDIRECT --to-ports ${redir_port}
    ${iptables} -t nat -A LOCAL -p tcp -m owner --uid-owner 1052 -j REDIRECT --to-ports ${redir_port}
    log Info "proxy mode: ${proxy_mode}, ${user_packages_list[*]} transparent proxy."
  else
    log Warn "proxy mode: ${proxy_mode} error."
    # Route Everything
    ${iptables} -t nat -A LOCAL -p tcp -j REDIRECT --to-ports ${redir_port}
    log Info "transparent proxy for all apps."
  fi

  ${iptables} -t nat -I OUTPUT -j LOCAL

  ${iptables} -A OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${redir_port} -j REJECT
}

stop_redirect() {
  ${iptables} -t nat -D PREROUTING -j EXTERNAL

  ${iptables} -t nat -D OUTPUT -j LOCAL

  ${iptables} -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${redir_port} -j REJECT
  ${iptables} -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner 0 --gid-owner 3005 -m tcp --dport ${redir_port} -j REJECT


  ${iptables} -t nat -F EXTERNAL
  ${iptables} -t nat -X EXTERNAL
  ${iptables} -t nat -F LOCAL
  ${iptables} -t nat -X LOCAL
}

start_tproxy() {
  if [ "${iptables}" = "ip6tables -w 100" ] ; then
    ip -6 rule add fwmark ${id} table ${id} pref ${id}
    ip -6 route add local default dev lo table ${id}
  else
    ip rule add fwmark ${id} table ${id} pref ${id}
    ip route add local default dev lo table ${id}
  fi

  ${iptables} -t mangle -N EXTERNAL
  ${iptables} -t mangle -F EXTERNAL

  # Bypass box itself
  # ${iptables} -t mangle -A EXTERNAL -m mark --mark ${routing_mark} -j RETURN

  # Bypass other if
  # Notice: Some interface is named with r_ / oem / nm_ / qcom_
  # It might need more complicated solution.
  # ${iptables} -t mangle -I EXTERNAL -i rmnet_data+ -j RETURN
  # ${iptables} -t mangle -I EXTERNAL -i ccmni+ -j RETURN

  # Bypass intranet
  # ${iptables} -t mangle -A EXTERNAL -m addrtype --dst-type LOCAL -j RETURN
  # Run `su -c 'zcat /proc/config.gz | grep -i addrtype'` to check compatibility
  if [ "${bin_name}" = "clash" ] ; then
    if [ "${iptables}" = "ip6tables -w 100" ] ; then
      ${iptables} -t mangle -A EXTERNAL -p udp --dport 53 -j RETURN
      for subnet6 in ${intranet6[@]}; do
        ${iptables} -t mangle -A EXTERNAL -d ${subnet6} -j RETURN
      done
    else
      ${iptables} -t mangle -A EXTERNAL -p udp --dport 53 -j RETURN
      for subnet in ${intranet[@]} ; do
        ${iptables} -t mangle -A EXTERNAL -d ${subnet} -j RETURN
      done
    fi
  else
    if [ "${iptables}" = "ip6tables -w 100" ] ; then
      for subnet6 in ${intranet6[@]} ; do
        ${iptables} -t mangle -A EXTERNAL -d ${subnet6} -p udp ! --dport 53 -j RETURN
        ${iptables} -t mangle -A EXTERNAL -d ${subnet6} ! -p udp -j RETURN
      done
    else
      for subnet in ${intranet[@]} ; do
        ${iptables} -t mangle -A EXTERNAL -d ${subnet} -p udp ! --dport 53 -j RETURN
        ${iptables} -t mangle -A EXTERNAL -d ${subnet} ! -p udp -j RETURN
      done
    fi
  fi

  ${iptables} -t mangle -A EXTERNAL -p tcp -i lo -j TPROXY --on-port ${tproxy_port} --tproxy-mark ${id}
  ${iptables} -t mangle -A EXTERNAL -p udp -i lo -j TPROXY --on-port ${tproxy_port} --tproxy-mark ${id}

  # Allow ap interface
  # Notice: Old android device may only have one wlan interface.
  # Some new android device have multiple wlan interface like wlan0(for internet), wlan1(for AP).
  if [ "${ap_list}" != "" ] ; then
    for ap in ${ap_list[@]} ; do
      ${iptables} -t mangle -A EXTERNAL -p tcp -i ${ap} -j TPROXY --on-port ${tproxy_port} --tproxy-mark ${id}
      ${iptables} -t mangle -A EXTERNAL -p udp -i ${ap} -j TPROXY --on-port ${tproxy_port} --tproxy-mark ${id}
    done
    log Info "${ap_list[*]} transparent proxy."
  fi

  ${iptables} -t mangle -I PREROUTING -j EXTERNAL


  ${iptables} -t mangle -N LOCAL
  ${iptables} -t mangle -F LOCAL

  # Bypass ignored interfaces
  if [ "${ignore_out_list}" != "" ] ; then
    for ignore in ${ignore_out_list[@]} ; do
      ${iptables} -t mangle -I LOCAL -o ${ignore} -j RETURN
    done
    log Info "${ignore_out_list[*]} ignore transparent proxy."
  fi

  # Bypass intranet
  # ${iptables} -t mangle -A LOCAL -m addrtype --dst-type LOCAL -j RETURN
  if [ "${bin_name}" = "clash" ] ; then
    if [ "${iptables}" = "ip6tables -w 100" ] ; then
      ${iptables} -t mangle -A LOCAL -p udp --dport 53 -j RETURN
      for subnet6 in ${intranet6[@]} ; do
        ${iptables} -t mangle -A LOCAL -d ${subnet6} -j RETURN
      done
    else
      ${iptables} -t mangle -A LOCAL -p udp --dport 53 -j RETURN
      for subnet in ${intranet[@]} ; do
        ${iptables} -t mangle -A LOCAL -d ${subnet} -j RETURN
      done
    fi
  else
    if [ "${iptables}" = "ip6tables -w 100" ] ; then
      for subnet6 in ${intranet6[@]} ; do
        ${iptables} -t mangle -A LOCAL -d ${subnet6} -p udp ! --dport 53 -j RETURN
        ${iptables} -t mangle -A LOCAL -d ${subnet6} ! -p udp -j RETURN
      done
    else
      for subnet in ${intranet[@]} ; do
        ${iptables} -t mangle -A LOCAL -d ${subnet} -p udp ! --dport 53 -j RETURN
        ${iptables} -t mangle -A LOCAL -d ${subnet} ! -p udp -j RETURN
      done
    fi
  fi

  # Bypass box itself
  ${iptables} -t mangle -I LOCAL -m owner --uid-owner ${user} --gid-owner ${group} -j RETURN

  # ${iptables} -t mangle -I LOCAL -m mark --mark ${routing_mark} -j RETURN

  # Disable kernel
  # ${iptables} -t mangle -A LOCAL -m owner ! --uid 0-99999999 -j DROP

  if [ "${proxy_mode}" = "blacklist" ] ; then
    if [ "${uid_list}" = "" ] ; then
      # Route Everything
      ${iptables} -t mangle -A LOCAL -p tcp -j MARK --set-mark ${id}
      ${iptables} -t mangle -A LOCAL -p udp -j MARK --set-mark ${id}
      log Info "transparent proxy for all apps."
    else
      # Bypass apps
      for appid in ${uid_list[@]} ; do
        ${iptables} -t mangle -I LOCAL -m owner --uid-owner ${appid} -j RETURN
      done
      # Allow !app
      ${iptables} -t mangle -A LOCAL -p tcp -j MARK --set-mark ${id}
      ${iptables} -t mangle -A LOCAL -p udp -j MARK --set-mark ${id}
      log Info "proxy mode: ${proxy_mode}, ${user_packages_list[*]} no transparent proxy."
    fi
  elif [ "${proxy_mode}" = "whitelist" ] ; then
    # Route apps to Box
    for appid in ${uid_list[@]} ; do
      ${iptables} -t mangle -A LOCAL -p tcp -m owner --uid-owner ${appid} -j MARK --set-mark ${id}
      ${iptables} -t mangle -A LOCAL -p udp -m owner --uid-owner ${appid} -j MARK --set-mark ${id}
    done
    ${iptables} -t mangle -A LOCAL -p tcp -m owner --uid-owner 0 -j MARK --set-mark ${id}
    ${iptables} -t mangle -A LOCAL -p udp -m owner --uid-owner 0 -j MARK --set-mark ${id}
    # Route dnsmasq to Box
    ${iptables} -t mangle -A LOCAL -p tcp -m owner --uid-owner 1052 -j MARK --set-mark ${id}
    ${iptables} -t mangle -A LOCAL -p udp -m owner --uid-owner 1052 -j MARK --set-mark ${id}
    # Route DNS request to Box
    [ "${bin_name}" != "clash" ] && ${iptables} -t mangle -A LOCAL -p udp --dport 53 -j MARK --set-mark ${id}
    log Info "proxy mode: ${proxy_mode}, ${user_packages_list[*]} transparent proxy."
  else
    log Warn "proxy mode: ${proxy_mode} error."
    # Route Everything
    ${iptables} -t mangle -A LOCAL -p tcp -j MARK --set-mark ${id}
    ${iptables} -t mangle -A LOCAL -p udp -j MARK --set-mark ${id}
    log Info "transparent proxy for all apps."
  fi

  ${iptables} -t mangle -I OUTPUT -j LOCAL


  ${iptables} -t mangle -N DIVERT
  ${iptables} -t mangle -F DIVERT

  ${iptables} -t mangle -A DIVERT -j MARK --set-mark ${id}
  ${iptables} -t mangle -A DIVERT -j ACCEPT

  ${iptables} -t mangle -I PREROUTING -p tcp -m socket -j DIVERT


  # This rule blocks local access to tproxy-port to prevent traffic loopback.
  if [ "${iptables}" = "ip6tables -w 100" ] ; then
    ${iptables} -A OUTPUT -d ::1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${tproxy_port} -j REJECT
  else
    ${iptables} -A OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${tproxy_port} -j REJECT
  fi


  if [ "${bin_name}" = "clash" ] && [ "${iptables}" = "iptables -w 100" ] ; then
    # android ip6tablses no nat table
    ${iptables} -t nat -N CLASH_DNS_EXTERNAL
    ${iptables} -t nat -F CLASH_DNS_EXTERNAL

    ${iptables} -t nat -A CLASH_DNS_EXTERNAL -p udp --dport 53 -j REDIRECT --to-ports ${dns_port}

    ${iptables} -t nat -I PREROUTING -j CLASH_DNS_EXTERNAL


    ${iptables} -t nat -N CLASH_DNS_LOCAL
    ${iptables} -t nat -F CLASH_DNS_LOCAL

    ${iptables} -t nat -A CLASH_DNS_LOCAL -m owner --uid-owner ${user} --gid-owner ${group} -j RETURN

    ${iptables} -t nat -A CLASH_DNS_LOCAL -p udp --dport 53 -j REDIRECT --to-ports ${dns_port}

    ${iptables} -t nat -I OUTPUT -j CLASH_DNS_LOCAL

    # Fix ICMP (ping), this does not guarantee that the ping result is valid (proxies such as clash do not support forwarding ICMP), 
    # just that it returns a result, "--to-destination" can be set to a reachable address.
    ${iptables} -t nat -I OUTPUT -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1
    ${iptables} -t nat -I PREROUTING -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1
  fi
}

stop_tproxy() {
  if [ "${iptables}" = "ip6tables -w 100" ] ; then
    ip -6 rule del fwmark ${id} table ${id}
    ip -6 route flush table ${id}
  else
    ip rule del fwmark ${id} table ${id}
    ip route flush table ${id}
  fi

  ${iptables} -t mangle -D PREROUTING -j EXTERNAL
    
  ${iptables} -t mangle -D PREROUTING -p tcp -m socket -j DIVERT

  ${iptables} -t mangle -D OUTPUT -j LOCAL

  ${iptables} -t mangle -F EXTERNAL
  ${iptables} -t mangle -X EXTERNAL

  ${iptables} -t mangle -F LOCAL
  ${iptables} -t mangle -X LOCAL

  ${iptables} -t mangle -F DIVERT
  ${iptables} -t mangle -X DIVERT

  if [ "${iptables}" = "ip6tables -w 100" ] ; then
    ${iptables} -D OUTPUT -d ::1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${tproxy_port} -j REJECT
    ${iptables} -D OUTPUT -d ::1 -p tcp -m owner --uid-owner 0 --gid-owner 3005 -m tcp --dport ${tproxy_port} -j REJECT
  else
    ${iptables} -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner ${user} --gid-owner ${group} -m tcp --dport ${tproxy_port} -j REJECT
    ${iptables} -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner 0 --gid-owner 3005 -m tcp --dport ${tproxy_port} -j REJECT
  fi


  # android ip6tablses no nat table
  iptables="iptables -w 100"
  ${iptables} -t nat -D PREROUTING -j CLASH_DNS_EXTERNAL

  ${iptables} -t nat -D OUTPUT -j CLASH_DNS_LOCAL

  ${iptables} -t nat -F CLASH_DNS_EXTERNAL
  ${iptables} -t nat -X CLASH_DNS_EXTERNAL

  ${iptables} -t nat -F CLASH_DNS_LOCAL
  ${iptables} -t nat -X CLASH_DNS_LOCAL

  ${iptables} -t nat -D OUTPUT -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1
  ${iptables} -t nat -D PREROUTING -d ${fakeip_range} -p icmp -j DNAT --to-destination 127.0.0.1
}

disable_ipv6() {
  echo 0 > /proc/sys/net/ipv6/conf/all/accept_ra
  echo 0 > /proc/sys/net/ipv6/conf/wlan0/accept_ra
  echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
  echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6
  echo 1 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6
}

enable_ipv6() {
  echo 1 > /proc/sys/net/ipv6/conf/all/accept_ra
  echo 1 > /proc/sys/net/ipv6/conf/wlan0/accept_ra
  echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
  echo 0 > /proc/sys/net/ipv6/conf/default/disable_ipv6
  echo 0 > /proc/sys/net/ipv6/conf/wlan0/disable_ipv6
}

getdns(){
if [ -z "$dnshead" ]; then
  dnshead=`grep dns: -n ${path}/clash/config.yaml | awk -F ':' '{print $1}'`
  dnstail=$(expr "$dnshead" + 1)
fi
dns=$(cat ${path}/clash/config.yaml | tail -n +"$dnstail" | head -n "1" | grep "  ")
if [ -n "$dns" ]; then
  dnstail=$(expr "$dnstail" + 1)
  getdns
else
  dnstail=$(expr "$dnstail" - 1)
fi
}
clashdns(){
  getdns
  dns_listen=$(cat ${path}/clash/config.yaml | head -n "$dnstail" | tail -n +"$dnshead" | grep "listen:" | awk -F ': ' '{print $2}')
  dns_port=$(echo ${dns_listen} | awk -F ':' '{print $2}')
}
mos(){
if [ -z "$moshead" ]; then
moshead=`grep "servers" -n $path/dns/mosdns.yaml | awk -F ':' '{print $1}'`
moshead=$(expr "$moshead" + 1)
mostail=$(expr "$moshead" + 1)
fi
mos=$(cat $path/dns/mosdns.yaml | tail -n +"$mostail" | head -n "1" | grep "  ")
if [ -n "$mos" ]; then
  mostail=$(expr "$mostail" + 1)
  mos
else
  mostail=$(expr "$mostail" - 1)
  
fi
}
mosudp(){
if [ -z "$mosudphead" ]; then
mosudphead=$(cat $path/dns/mosdns.yaml | head -n "$mostail" | tail -n +"$moshead" | grep -n "udp" | awk -F ':' '{print $1}')
mosudptail=$(expr "$mosudphead" + "$moshead" + 1)
mosudphead=$(expr "$mosudphead" + "$moshead")
fi
mosudp=$(cat $path/dns/mosdns.yaml | tail -n +"$mosudptail" | head -n "1" | grep -v "-")
if [ -n "$mosudp" ]; then
  mosudptail=$(expr "$mosudptail" + 1)
  mosudp
else
  mosudptail=$(expr "$mosudptail" - 1)
  dns_port=$(cat $path/dns/mosdns.yaml | head -n "$mosudptail" | tail -n +"$mosudphead" | grep -n "addr" | awk -F ':' '{print $NF}')
fi
}

if ["$dns_hijack" = "auto"]; then
  if [ "$adgh" = "true" ]; then
    if [ -f ${path}/dns/AdGuardHome.yaml ]; then
      dns_port=$(cat ${path}/dns/AdGuardHome.yaml | grep "  port:" | awk -F ': ' '{print $2}')
    elif [ "$mosdns" = "true" ]; then
      if [ -f ${path}/dns/mosdns.yaml ]; then
        mos
        mosudp
      fi
    else
      clashdns
    fi
  elif [ "$mosdns" = "true" ]; then
    if [ -f ${path}/dns/mosdns.yaml ]; then
      mos
      mosudp
    else
      clashdns
    fi
  else
    clashdns
  fi
elif [ "$dns_hijack" = "adgh" ]; then
  if [ -f ${path}/dns/AdGuardHome.yaml ]; then
    dns_port=$(cat ${path}/dns/AdGuardHome.yaml | grep "  port:" | awk -F ': ' '{print $2}')
  elif [ "$mosdns" = "true" ]; then
    if [ -f ${path}/dns/mosdns.yaml ]; then
      mos
      mosudp
    fi
  else
    clashdns
  fi
elif [ "$dns_hijack" = "mosdns" ]; then
  if [ -f ${path}/dns/mosdns.yaml ]; then
    mos
    mosudp
  else
    clashdns
  fi
else
  clashdns
fi

getdns
redir_port="$(cat ${path}/clash/config.yaml | grep "redir-port" | awk -F ':' '{print $2}')"
tproxy_port="$(cat ${path}/clash/config.yaml | grep "tproxy-port" | awk -F ':' '{print $2}')"
fakeip_range=$(cat ${path}/clash/config.yaml | head -n "$dnstail" | tail -n +"$dnshead" | grep "fake-ip-range:" | awk -F ': ' '{print $2}')

if [ "${proxy_mode}" = "core" ] ; then
  iptables="iptables -w 100" && stop_tproxy >> /dev/null 2>&1
  iptables="ip6tables -w 100" && stop_tproxy >> /dev/null 2>&1
  iptables="iptables -w 100" && stop_redirect >> /dev/null 2>&1
  log Info "proxy_mode: ${proxy_mode}, disable transparent proxy."
  return 0
fi

case "$1" in
  enable)
    iptables="iptables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="ip6tables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="iptables -w 100" && stop_redirect >> /dev/null 2>&1
    sleep 1
    if ! probe_user_group ; then
      log Error "failed to check Box user group, please make sure ${bin_name} core is started."
      return 1
    fi
    find_packages_uid
    intranet[${#intranet[@]}]=$(ip address | grep -w inet | grep -v 127 | awk '{print $2}')
    if [ "${proxy_method}" = "TPROXY" ] ; then
      if (zcat /proc/config.gz | grep -q TPROXY) ; then
        log Info "use TPROXY:TCP+UDP."
        log Info "creating ip(6)tables transparent proxy rules."
        iptables="iptables -w 100"
        start_tproxy && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_tproxy >> /dev/null 2>&1)
        if [ "${ipv6}" = "enable" ] ; then
          log Debug "use IPv6."
          enable_ipv6
          iptables="ip6tables -w 100"
          intranet6[${#intranet6[@]}]=$(ip address | grep -w inet6 | grep -v ::1 | grep -v fe80 | awk '{print $2}')
          start_tproxy && log Info "create ip6tables transparent proxy rules done." || (log Error "create ip6tables transparent proxy rules failed." && stop_tproxy >> /dev/null 2>&1)
        else
          disable_ipv6
          log Warn "disable IPv6."
        fi
      else
        log Warn "the device does not support TPROXY, please switch proxy_method."
        log Info "use REDIRECT:TCP."
        log Info "creating iptables transparent proxy rules."
        iptables="iptables -w 100"
        start_redirect && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_redirect >> /dev/null 2>&1)
        [ "${ipv6}" = "enable" ] && enable_ipv6 && log Warn "enable IPv6." || (disable_ipv6 && log Warn "disable IPv6.")
      fi
    else
      [ "${proxy_method}" = "REDIRECT" ] && log Info "use REDIRECT:TCP." || log Info "use MIXED:TCP+TUN."
      log Info "creating iptables transparent proxy rules."
      iptables="iptables -w 100"
      start_redirect && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_redirect >> /dev/null 2>&1)
      [ "${ipv6}" = "enable" ] && enable_ipv6 && log Warn "enable IPv6." || (disable_ipv6 && log Warn "disable IPv6.")
    fi
    ;;
  disable)
    log Warn "cleaning up ip(6)tables transparent proxy rules."
    probe_user_group
    iptables="iptables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="ip6tables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="iptables -w 100" && stop_redirect >> /dev/null 2>&1
    log Warn "clean up ip(6)tables transparent proxy rules done."
    enable_ipv6
    log Warn "enable IPv6."
    return 0
    ;;
  renew)
    log Warn "cleaning up ip(6)tables transparent proxy rules."
    iptables="iptables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="ip6tables -w 100" && stop_tproxy >> /dev/null 2>&1
    iptables="iptables -w 100" && stop_redirect >> /dev/null 2>&1
    log Warn "clean up ip(6)tables transparent proxy rules done."
    sleep 3
    if ! probe_user_group ; then
      log Error "failed to check Box user group, please make sure ${bin_name} core is started."
      return 1
    fi
    find_packages_uid
    intranet[${#intranet[@]}]=$(ip address | grep -w inet | grep -v 127 | awk '{print $2}')
    if [ "${proxy_method}" = "TPROXY" ] ; then
      if (zcat /proc/config.gz | grep -q TPROXY) ; then
        log Info "use TPROXY:TCP+UDP."
        log Info "creating ip(6)tables transparent proxy rules."
        iptables="iptables -w 100"
        start_tproxy && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_tproxy >> /dev/null 2>&1)
        if [ "${ipv6}" = "enable" ] ; then
          log Debug "use IPv6."
          enable_ipv6
          iptables="ip6tables -w 100"
          intranet6[${#intranet6[@]}]=$(ip address | grep -w inet6 | grep -v ::1 | grep -v fe80 | awk '{print $2}')
          start_tproxy && log Info "create ip6tables transparent proxy rules done." || (log Error "create ip6tables transparent proxy rules failed." && stop_tproxy >> /dev/null 2>&1)
        else
          disable_ipv6
          log Warn "disable IPv6."
        fi
      else
        log Warn "the device does not support TPROXY, please switch proxy_method."
        log Info "use REDIRECT:TCP."
        log Info "creating iptables transparent proxy rules."
        iptables="iptables -w 100"
        start_redirect && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_redirect >> /dev/null 2>&1)
        [ "${ipv6}" = "enable" ] && enable_ipv6 && log Warn "enable IPv6." || (disable_ipv6 && log Warn "disable IPv6.")
      fi
    else
      [ "${proxy_method}" = "REDIRECT" ] && log Info "use REDIRECT:TCP." || log Info "use MIXED:TCP+TUN."
      log Info "creating iptables transparent proxy rules."
      iptables="iptables -w 100"
      start_redirect && log Info "create iptables transparent proxy rules done." || (log Error "create iptables transparent proxy rules failed." && stop_redirect >> /dev/null 2>&1)
      [ "${ipv6}" = "enable" ] && enable_ipv6 && log Warn "enable IPv6." || (disable_ipv6 && log Warn "disable IPv6.")
    fi
    ;;
  enable_ipv6)
    enable_ipv6
    log Warn "enable IPv6."
    ;;
  disable_ipv6)
    disable_ipv6
    log Warn "disable IPv6."
    ;;
  *)
    log Error "$0 $1 usage: $0 {enable|disable|renew|enable_ipv6|disable_ipv6}"
    ;;
esac