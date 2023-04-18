until [ $(getprop init.svc.bootanim) = "stopped" ] ; do
    sleep 5
done

service_path=`realpath $0`
module_dir=`dirname ${service_path}`
data_dir="/data/clash"
scripts_dir="${data_dir}/scripts"
Clash_data_dir="/data/clash"
Clash_run_path="${Clash_data_dir}/run"
Clash_pid_file="${Clash_run_path}/clash.pid"
busybox_path="/data/adb/magisk/busybox"

if [ -f ${Clash_pid_file} ] ; then
    rm -rf ${Clash_pid_file}
fi

nohup ${scripts_dir}/clash.service -s && ${scripts_dir}/clash.iptables -s

inotifyd ${scripts_dir}/clash.inotify ${module_dir} >> /dev/null &