rem prepare source tree
mkdir mtsrc
del mtsrc\*.*
copy mt.pas mtsrc
copy mt_*.pas mtsrc
copy mtconfig.pas mtsrc

copy \compiled\mt.exe .
copy \compiled\mtconfig.exe .
copy \compiled\mt.map .
del c:\temp\mt_a037c.zip
pkzip -es -P c:\temp\mt_a037c.zip @manifest.txt
copy c:\temp\mt_a037c.zip .
rem del mt.exe
rem del mtconfig.exe
