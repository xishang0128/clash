Clash_data_dir="/data/adb/clash"

rm_data() {
    rm -rf ${Clash_data_dir}
}

rm -f /data/adb/service.d/service.sh
rm_data