#!/bin/bash
# Rebuild the caches that Debian normally regenerates in postinst triggers.
set -e
OV=$WORK/ov3; R=$ROOTFS; U=$WORK/union
rm -rf $U && mkdir -p $U/schemas $U/mime/packages

# glib schemas: union of rootfs + overlay, compiled into the overlay
cp -n $R/usr/share/glib-2.0/schemas/* $U/schemas/ 2>/dev/null || true
cp -n $OV/usr/share/glib-2.0/schemas/* $U/schemas/ 2>/dev/null || true
glib-compile-schemas $U/schemas
mkdir -p $OV/usr/share/glib-2.0/schemas && cp $U/schemas/gschemas.compiled $OV/usr/share/glib-2.0/schemas/

# shared-mime-info database from the union of package XML
cp -n $R/usr/share/mime/packages/*.xml $U/mime/packages/ 2>/dev/null || true
cp -n $OV/usr/share/mime/packages/*.xml $U/mime/packages/ 2>/dev/null || true
update-mime-database $U/mime >/dev/null 2>&1
mkdir -p $OV/usr/share/mime && cp -a $U/mime/. $OV/usr/share/mime/

# icon caches
for d in $OV/usr/share/icons/*/; do [ -f "$d/index.theme" ] && gtk-update-icon-cache -q -f -t "$d" || true; done

# gdk-pixbuf loaders cache with target-relative paths
PB=$OV/usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0
if [ -d $PB/loaders ]; then
  GDK_PIXBUF_MODULEDIR=$PB/loaders /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders 2>/dev/null \
    | sed "s|$OV||g" > $PB/loaders.cache
fi

# GIO modules cache
[ -d $OV/usr/lib/x86_64-linux-gnu/gio/modules ] && gio-querymodules $OV/usr/lib/x86_64-linux-gnu/gio/modules || true

# loader path for the Debian multiarch dir (top-level libs are also symlinked in /usr/lib64)
mkdir -p $OV/etc/ld.so.conf.d && echo /usr/lib/x86_64-linux-gnu > $OV/etc/ld.so.conf.d/debian-multiarch.conf
echo post-done
