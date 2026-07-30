# Custom PHP extensions

This directory is an escape hatch for extensions that cannot be distributed by
OneinStack, such as licensed loaders or private modules.

Place ABI-compatible shared libraries in `extensions/` and their `.ini` files
in `conf.d/`, then rebuild the PHP service:

```bash
./oneinstack build php
./oneinstack up php
./oneinstack php-ext verify
```

Example `conf.d/20-vendor-loader.ini`:

```ini
zend_extension=vendor_loader.so
```

The shared library must match the selected PHP version, thread-safety mode,
architecture and libc. The image build fails when PHP reports a startup error.
Vendor licenses and redistribution terms remain the deployer's responsibility.
