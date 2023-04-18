#!/bin/sh

path=$(cd ../ ; pwd)

gettun(){
if [ -z "$tunhead" ]; then
tunhead=`grep tun: -n $path/clash/config.yaml | awk -F ':' '{print $1}'`
tuntail=$(expr "$tunhead" + 1)
fi
tun=$(cat $path/clash/config.yaml | tail -n +"$tuntail" | head -n "1" | grep "  ")
if [ -n "$tun" ]; then
  tuntail=$(expr "$tuntail" + 1)
  gettun
else
  tuntail=$(expr "$tuntail" - 1)
fi
}

getdns(){
if [ -z "$dnshead" ]; then
dnshead=`grep dns: -n $path/clash/config.yaml | awk -F ':' '{print $1}'`
dnstail=$(expr "$dnshead" + 1)
fi
dns=$(cat $path/clash/config.yaml | tail -n +"$dnstail" | head -n "1" | grep "  ")
if [ -n "$dns" ]; then
  dnstail=$(expr "$dnstail" + 1)
  getdns
else
  dnstail=$(expr "$dnstail" - 1)
fi
}

getsniff(){
if [ -z "$sniffhead" ]; then
sniffhead=`grep sniffer: -n $path/clash/config.yaml | awk -F ':' '{print $1}'`
snifftail=$(expr "$sniffhead" + 1)
fi
sniff=$(cat $path/clash/config.yaml | tail -n +"$snifftail" | head -n "1" | grep "  ")
if [ -n "$sniff" ]; then
  snifftail=$(expr "$snifftail" + 1)
  getsniff
else
  snifftail=$(expr "$snifftail" - 1)
fi
}


gettun
getdns
getsniff




echo TUN 开头"$tunhead"行 结尾"$tuntail"行
echo DNS 开头"$dnshead"行 结尾"$dnstail"行
echo 嗅探 开头"$sniffhead"行 结尾"$snifftail"行