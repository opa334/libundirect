#/bin/sh
set -e

make clean
make FINALPACKAGE=1
cp -v "./.theos/obj/libundirect.dylib" "$THEOS/lib"

make clean
make FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
cp -v "./.theos/obj/libundirect.dylib" "$THEOS/lib/iphone/rootless"

mkdir -p "$THEOS/include/libundirect"
cp -v "libundirect.h" "$THEOS/include/libundirect"
cp -v "libundirect_dynamic.h" "$THEOS/include/libundirect"
cp -v "libundirect_hookoverwrite.h" "$THEOS/include/libundirect"
echo "successfully installed libundirect"