# podracer

## Reference

* https://finestructure.co/blog/2020/11/27/running-docker-on-apple-silicon-m1

```shell
sudo mkdir /Volumes/Ubuntu
sudo hdiutil attach -nomount ~/Downloads/focal-desktop-arm64.iso
sudo mount -t cd9660 /dev/diskN  # see below to determine N
open /Volumes/Ubuntu/casper
```

```shell
./podracer -k vmlinuz -i initrd.img -d squashfs.img -c fedora-x86_64-33-1.2.iso -a "console=hvc0 root=live:CDLABEL=Fedora-Sec-Live-33-1-2 rd.live.image rd.live.check quiet"
```

-a "console=hvc0 root=live:CDLABEL=Fedora-Sec-Live-33-1-2 rd.live.image rd.live.check quiet"

