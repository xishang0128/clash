SKIPUNZIP=1

status=""
architecture=""
system_gid="1000"
system_uid="1000"
clash_data_dir="/data/clash"
modules_dir="/data/adb/modules"
ca_path="/system/etc/security/cacerts"
CPFM_mode_dir="${modules_dir}/clash_premium"
mod_config="${clash_data_dir}/clash.config"
geoip_file_path="${clash_data_dir}/Country.mmdb"

if [ -d "${CPFM_mode_dir}" ] ; then
    touch ${CPFM_mode_dir}/remove && ui_print "- CPFM模块在重启后将会被删除."
fi

case "${ARCH}" in
    arm)
        architecture="armv7"
        ui_print "不支持的架构"
        exit 1
        ;;
    arm64)
        architecture="armv8"
        ;;
    x86)
        architecture="386"
        ui_print "不支持的架构"
        exit 1
        ;;
    x64)
        architecture="amd64"
        ui_print "不支持的架构"
        exit 1
        ;;
esac

mv -f ${clash_data_dir} ${clash_data_dir}.old
mkdir -p ${MODPATH}/system/bin
mkdir -p ${clash_data_dir}

unzip -o "${ZIPFILE}" -x 'META-INF/*' -d $MODPATH >&2

mv -f ${MODPATH}/clash/* ${clash_data_dir}/
rm -rf ${MODPATH}/clash
ln -s ${clash_data_dir}/clash/kernel/clash ${MODPATH}/system/bin/clash
ln -s ${clash_data_dir}/clash/geosite.dat ${clash_data_dir}/mosdns/geosite.dat
ln -s ${clash_data_dir}/clash/geoip.dat ${clash_data_dir}/mosdns/geoip.dat
if [ ! -f "${clash_data_dir}/packages.list" ] ; then
    touch ${clash_data_dir}/packages.list
fi

sleep 1

ui_print "- 开始设置环境权限."
set_perm_recursive ${MODPATH} 0 0 0755 0644
set_perm_recursive ${clash_data_dir} ${system_uid} ${system_gid} 0755 0644
set_perm_recursive ${clash_data_dir}/scripts ${system_uid} ${system_gid} 0755 0755
set_perm  ${clash_data_dir}/clash/kernel/clash  ${system_uid}  ${system_gid}  6755
set_perm  ${clash_data_dir}/mosdns/mosdns ${system_uid}  ${system_gid}  6755
set_perm  ${clash_data_dir}/clash.config ${system_uid} ${system_gid} 0755
set_perm  ${clash_data_dir}/packages.list ${system_uid} ${system_gid} 0644
