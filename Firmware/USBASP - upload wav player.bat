avrdude -C ./avrdude.conf -v -p attiny85 -c usbasp -P usb -e
avrdude -C ./avrdude.conf -v -p attiny85 -c usbasp -P usb -U lfuse:w:0xe1:m -U hfuse:w:0xdd:m -U efuse:w:0xff:m
avrdude -C ./avrdude.conf -v -p attiny85 -c usbasp -P usb  -i 100  -Uflash:w:obj_mo\sd8p_mo.hex:i
pause



