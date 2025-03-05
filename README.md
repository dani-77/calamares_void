# calamares_void - a easy way to incorporate calamares with a Void based distro/respin


## Requirements

a working void-packages and all it's dependencies; 


```
git clone https://github.com/void-linux/void-packages
```

- GNU bash

- xbps >= 0.56

- git

- curl

- util-linux

- bsdtar

- coreutils

- binutils

- xtools

- calamares

- rsync

- grub


## 1st

clone this repo

```
git clone https://github.com/dani-77/calamares_void
```

and copy srcpkgs/calamares to void-packages/srcpkgs

Example
```
cp -r srcpkgs/calamares ~/void-packages/srcpkgs
```

then create the package

```
./xbps-src pkg calamares
```

## 2nd

Edit the calamares settings.conf, branding and show.qml to your needs.

Then copy calamares dir to where you need it to be incorporated in your ISO (this directory is already treated to work and must be incorporated in your iso at /etc/calamares).


## 3rd

With void-mklive, treat the mkiso.sh to create your custom ISO; I add mine as an example.

Examine it and compare it to the original mkiso.sh; you will notice that are several differences and adaptations.

To create the sway iso

```
sudo ./mkiso.sh -r /home/YOUR_USER/void-packages/hostdir/binpkgs/cereus-extra -b sway -- -T YOUR_BRAND

Hope it can help.
