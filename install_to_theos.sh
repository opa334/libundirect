set -e
make FINALPACKAGE=1
cp -v "./.theos/obj/libundirect.dylib" "$THEOS/lib"

mkdir -p "$THEOS/include/libundirect"
cp -v "libundirect.h" "$THEOS/include/libundirect"
cp -v "libundirect_dynamic.h" "$THEOS/include/libundirect"
cp -v "libundirect_hookoverwrite.h" "$THEOS/include/libundirect"
echo "successfully intalled libundirect"