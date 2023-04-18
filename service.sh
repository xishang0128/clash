#!/bin/sh

module_dir="/data/adb/modules/clash"

[ -n "$(magisk -v | grep lite)" ] && module_dir=/data/adb/lite_modules/clash

scripts_dir="/data/adb/clash/scripts"

(
until [ $(getprop sys.boot_completed) -eq 1 ] ; do
  sleep 3
done
${scripts_dir}/start.sh
)&

inotifyd ${scripts_dir}/inotify.sh ${module_dir} > /dev/null 2>&1 &