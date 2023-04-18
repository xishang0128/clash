#!/bin/sh

SKIPUNZIP=1
ASH_STANDALONE=1

if [ "$BOOTMODE" ! = true ] ; then
  abort "Error: Please install in Magisk Manager or KernelSU Manager"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ] ; then
  abort "Error: Please update your KernelSU and KernelSU Manager or KernelSU Manager"
fi

if [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10683 ] ; then
  service_dir="/data/adb/ksu/service.d"
else 
  service_dir="/data/adb/service.d"
fi

if [ ! -d "$service_dir" ] ; then
    mkdir -p $service_dir
fi

unzip -qo "${ZIPFILE}" -x 'META-INF/*' -d $MODPATH

if [ -d /data/adb/clash ] ; then
  cp /data/adb/clash/scripts/config /data/adb/clash/scripts/config.bak
  ui_print "- User configuration config has been backed up to config.bak"

  cat /data/adb/clash/scripts/config >> $MODPATH/clash/scripts/config
  cp -f $MODPATH/clash/scripts/* /data/adb/clash/scripts/
  ui_print "- User configuration config has been"
  ui_print "- attached to the module config,"
  ui_print "- please re-edit config"
  ui_print "- after the update is complete."

  awk '!x[$0]++' $MODPATH/clash/scripts/config > /data/adb/clash/scripts/config

  rm -rf $MODPATH/clash
else
  mv $MODPATH/clash /data/adb/
fi

mkdir -p /data/adb/clash/bin/
mkdir -p /data/adb/clash/run/

mv -f $MODPATH/service.sh $service_dir/

rm -f customize.sh

set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive /data/adb/clash/ 0 0 0755 0644
set_perm_recursive /data/adb/clash/scripts/ 0 0 0755 0700
set_perm_recursive /data/adb/clash/bin/ 0 0 0755 0700

set_perm $service_dir/service.sh 0 0 0700

# fix "set_perm_recursive /data/adb/clash/scripts" not working on some phones.
chmod ugo+x /data/adb/clash/scripts/*

for pid in $(pidof inotifyd) ; do
  if grep -q inotify.sh /proc/${pid}/cmdline ; then
    kill ${pid}
  fi
done

inotifyd "/data/adb/clash/scripts/inotify.sh" "/data/adb/modules/clash" > /dev/null 2>&1 &