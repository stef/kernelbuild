#!/usr/bin/ksh
# invoke like
# ./build.sh 3.6.6 https://grsecurity.net/test/grsecurity-2.9.1-3.6.6-201211072001.patch
kver="$1"
grsecurl="$2"
lver="${3:-$kver}"

function die {
    echo "error" >&1
    exit 1
}

wget -c "$grsecurl" || die
wget -c "$grsecurl.sig" || die
gpg --verify "${grsecurl##*/}.sig" "${grsecurl##*/}" || die

wget -c "https://www.kernel.org/pub/linux/kernel/v3.0/linux-$kver.tar.xz" || die
wget -c "https://www.kernel.org/pub/linux/kernel/v3.0/linux-$kver.tar.sign" || die

[[ -d linux-$kver ]] || {
   xz -cd linux-$kver.tar.xz | gpg --verify linux-$kver.tar.sign - || die

   echo "extracting kernel"
   tar xJf linux-$kver.tar.xz || die
}

cd linux-$kver || die

patch -N -p1 <../"${grsecurl##*/}" || die

cp ../CONFIG .config || die

ARCH=x86_64 make oldconfig || die

ARCH=x86_64 make || die

find . -iname "*.ko" -exec strip --strip-debug {} \; || die

cp .config ../config-$lver || die

ls /lib/modules
echo "Remove any obsolete modules/kernels from the boot/root partition before continuing"
read

sudo ARCH=x86_64 make modules_install || die

cd ../tp_smapi || die
sudo make install HDAPS=1 KVER=$lver-grsec || die

cd ..

gpg2 --sign config-$lver || die

ls /boot
mount | fgrep /boot
echo "clean up !correct! boot device before generating grub config"
read
cd linux-$kver || die
sudo cp arch/x86_64/boot/bzImage /boot/vmlinuz-$lver-grsec || die
sudo cp -v System.map /boot/System.map-$lver-grsec || die
sudo mkinitramfs -o /boot/initrd.img-$lver-grsec $lver-grsec || die
sudo chmod o+r /boot/initrd.img-$lver-grsec

sudo grub-mkconfig -o /boot/grub/grub.cfg || die

cp arch/x86_64/boot/bzImage vmlinuz-$lver-grsec || die
cp System.map System.map-$lver-grsec || die
cp /boot/initrd.img-$lver-grsec . || die
 
bootfiles="vmlinuz-$lver-grsec System.map-$lver-grsec initrd.img-$lver-grsec"
tar cjvf boot-$lver.txz $bootfiles || die
sudo chmod o-r /boot/initrd.img-$lver-grsec
gpg2 --sign boot-$lver.txz || die

echo "uploading backup"
turl $(cat boot-$lver.txz.gpg | pv -ftrab | sudo -u tahoe tahoe put - kernel:boot-$lver.txz.gpg | tail -1) boot-$lver.txz.gpg >/tmp/bbi.txt
echo "backup is stored at:"
cat /tmp/bbi.txt
publish /tmp/bbi.txt
rm /tmp/bbi.txt

# archiving modules
basedir=$(realpath ..)
(cd /lib/modules; tar cjvf "$basedir/modules-$lver.txz" "$lver-grsec") || die
gpg2 --sign ../modules-$lver.txz || die

echo "uploading modules"
turl $(cat ../modules-$lver.txz.gpg | pv -ftrab | sudo -u tahoe tahoe put - kernel:modules-$lver.txz.gpg | tail -1) modules-$lver.txz.gpg

echo "archiving kernel tree"
tar cJvf ../arch/arch-$lver.txz vmlinux vmlinux.o System.map .config || die
make mrproper || die
cd ..
tar cJf arch/linux-$lver.txz linux-$kver && rm -rf linux-$kver

echo "!!!! don't forget to run grub-install --boot-directory=/boot /dev/sdb???????"
