## set plot type

#print "Setting for PNG output" #DEBUG
pngWidth1=640
pngHeight1=240
if ( ! exists("pngWidth") ) { 
  pngWidth=pngWidth1
}
if ( ! exists("pngHeight") ) { 
  pngHeight=pngHeight1
}
set terminal pngcairo enhanced color font 'FreeSans' fontscale 0.8 size pngWidth,pngHeight
