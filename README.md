# installOpenFOAM

Author: Masashi Imano <masashi.imano@gmail.com>

## Settings

Edit these files appropriately first.

- etc/sytem
- etc/url
- etc/version
- sytem/{SYSTEM}/bashrc
- sytem/{SYSTEM}/settings
- sytem/{SYSTEM}/jobScript (optional)
- sytem/{SYSTEM}/url (optional)
- sytem/{SYSTEM}/version (optional)

## How to install

```bash
./install.sh
```

## Source files

Source files of OpenFOAM, ThirdParty and related third-pary packages listed in etc/version and system/{SYSTEM}/version are automatically download from URLs listed in etc/url and etc/{SYSTEM}/url.

If download from the Internet is disabled, locate source files in 'download' directory in advance.
