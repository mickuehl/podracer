# podracer


```shell

cd iso

../podracer -k vmlinuz -i initrd.img -d squashfs.img -c Fedora-LXDE-Live-x86_64-33-1.2.iso -a "console=hvc0 root=live:CDLABEL=Fedora-LXDE-Live-33-1-2  rd.live.image rd.live.check quiet"

../podracer -k vmlinuz -i initrd -d ubuntu-20.10-desktop-amd64.iso -a "console=hvc0 root=/dev/vda1"

```

### Reference

* https://finestructure.co/blog/2020/11/27/running-docker-on-apple-silicon-m1
* https://developer.apple.com/documentation/virtualization?language=objc
* https://superuser.com/questions/210333/how-to-boot-fedora-live-cd-iso-from-a-hard-drive

### Other stuff

* https://wiki.lindenstruth.org/wiki/Hdiutil#erstellen
* https://www.tutorialspoint.com/objective_c/index.htm

