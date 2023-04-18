#!/bin/sh

clash(){
	#############################
	status
	#############################
	echo -e " 1 \033[32m启动/重启\033[0mclash服务"
	echo -e " 2 \033[31m停止\033[0mclash服务"
	echo -e " 3 clash\033[33m功能设置\033[0m"
	echo -e " 4 clash\033[36m启动设置\033[0m"
	echo -----------------------------------------------
	echo -e " 0 \033[0m退出脚本\033[0m"
	read -p "请输入对应数字 > " num
	if [ -z "$num" ];then
		errornum
		exit;
	elif [ "$num" = 0 ]; then
		exit;
		
	elif [ "$num" = 1 ]; then
		clashstart
		exit;
	else
		errornum
		exit;
	fi
}

errornum(){
	echo -----------------------------------------------
	echo -e "\033[31m请输入正确的数字！\033[0m"
}

status(){
	echo -e test
}
























[ -z "$1" ] && clash
