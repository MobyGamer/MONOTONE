rem prepare source tree
mkdir mtsrc
del mtsrc\*.*
copy mt.pas mtsrc
copy mt_*.pas mtsrc
copy mtconfig.pas mtsrc

copy \compiled\mt.exe .
copy \compiled\mtconfig.exe .
copy \compiled\mt.map .
del c:\temp\mt_a037d.zip
pkzip -es -P c:\temp\mt_a037d.zip @manifest.txt
copy c:\temp\mt_a037d.zip .
rem del mt.exe
rem del mtconfig.exe
