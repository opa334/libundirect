make
cp -v "./.theos/obj/libundirect.dylib" "$THEOS/lib"
cp -v "libundirect.h" "$THEOS/include"
cp -v "libundirect_hookoverwrite.h" "$THEOS/include"
echo "successfully intalled libundirect"