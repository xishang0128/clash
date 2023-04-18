#!/bin/sh
#!/bin/sh


arch=arm64
os=android

url=`curl -s https://api.github.com/repos/MetaCubeX/Clash.Meta/releases/tags/Prerelease-Alpha | grep "download/Prerelease-Alpha/clash.meta-$os-$arch-alpha" | cut -d : -f 2,3 | tr -d \"`
version=`echo $url | awk -F '.' '{print $4}' | awk -F '-' '{print $NF}'`
size=`curl -s  https://api.github.com/repos/MetaCubeX/Clash.Meta/releases/tags/Prerelease-Alpha | grep -B 5 "download/Prerelease-Alpha/clash.meta-$os-$arch-alpha" | grep size | awk -F ':' '{print $2}' | awk -F ',' '{print $1}'`

update() {
wget -O ./clash.gz $url

filesize=`stat ./clash.gz | grep Size | awk -F ' ' '{print $2}'`
if [ -z $filesize ]; then
  filesize=`stat ./clash.gz | grep 大小 | awk -F ' ' '{print $1}' | awk -F '：' '{print $2}'`
elif [ -z $filesize ]; then
  filesize=`stat ./clash.gz | awk -F '"' '{print $1}' | awk -F ' ' '{print $NF}'`
fi

if [ $size = $filesize ]; then
  gzip -d ./clash.gz
  ls -al
  mv ./clash ./clash/bin/clash
else
  echo 更新失败了喵,压缩包校验失败
  exit 1
fi
}

update
