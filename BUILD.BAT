rem prepare source tree
mkdir mtsrc
del mtsrc\*.*
copy mt.pas mtsrc
copy mt_*.pas mtsrc
copy mtconfig.pas mtsrc

copy \compiled\mt.exe .
copy \compiled\mtconfig.exe .
del c:\temp\mt_a036.zip
pkzip -es -P c:\temp\mt_a036.zip @manifest.txt
del mt.exe
del mtconfig.exe
