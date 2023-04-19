#!/bin/sh


path=$(cd $(dirname `realpath $0`); cd ../; pwd)
scripts_dir=$(dirname `realpath $0`)
source ${scripts_dir}/config


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
  fakeip_range=$(cat ${path}/clash/config.yaml | head -n "$dnstail" | tail -n +"$dnshead" | grep "fake-ip-range:" | awk -F ': ' '{print $2}')
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
  echo mos
  if [ -f ${path}/dns/mosdns.yaml ]; then
    mos
    mosudp
  else
    clashdns
  fi
else
  clashdns
fi

echo $dns_port