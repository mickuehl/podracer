# fedora iso

Place the kernel and other images needed to boot here.


```shell

sudo mkdir /Volumes/fedora
sudo hdiutil attach -nomount fedora-x86_64-33-1.2.iso

# see output from above to determine N

sudo mount -t cd9660 /dev/diskN /Volumes/fedora

cp /Volumes/fedora/LiveOS/squashfs.img .
cp /Volumes/fedorasec/isolinux/initrd.img .
cp /Volumes/fedorasec/isolinux/vmlinuz .

```
