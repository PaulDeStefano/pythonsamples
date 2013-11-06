#!/usr/bin/python2.7

import time, serial, struct, sys, os, string, subprocess, datetime

##################################
# SET GLOBAL CONSTANTS
##################################

memSize = 1 #megabytes
memSize = memSize*1024*1024/32 #number of 32 byte blocks in memory
#unique identifier code to test that the right device has been connected to 
identifier = hex(0x3645145)
oldIndexPos = 2
unixPos = 1

#################################
# FUCTIONS
#################################

#Properly closes the serial connection
def closeCon():
	try:
		con.flushInput()
		con.write('e')
		con.flushOutput()
		con.close()
		print "Connection closed"
		print "--------------------------------------------" #XXX
	except:
		print "Connection failed to close properly."

#rounds value to two decimal places
def RndStr(val):
	val = "{0:.2f}".format(val)
	return val

#Converts unix time stamp to string of the form yyyy-mm-ddThh:mm:ssZ
def UnixUTCtoISO(unixTime):
	unixTuple = time.gmtime(unixTime)
	hour = str(unixTuple[3]).zfill(2)
	minute = str(unixTuple[4]).zfill(2)
	second = str(unixTuple[5]).zfill(2)
	ISO_String = datetime.date(unixTuple[0],unixTuple[1],unixTuple[2]).isoformat()
	ISO_String = ISO_String+'T'+hour+':'+minute+':'+second+'Z'
	return ISO_String

#Converts unix time to a date in the form yyyy-mm-dd
def UnixUTCtoDateString(unixTime):
	unixTuple = time.gmtime(unixTime)
	dateString = datetime.date(unixTuple[0],unixTuple[1],unixTuple[2]).isoformat()
	return dateString

#Print output header
print "--------------------------------------------" #XXX
print "Local time: ",time.asctime(time.localtime(time.time()))
print "  UTC time: ",time.asctime(time.gmtime(time.time()))


###################################
# GET SERIAL PORT
###################################

searchStr = "dmesg | grep 'FTDI USB Serial Device converter now attached' | tail -1"
grepFTDI = subprocess.Popen([searchStr],stdout=subprocess.PIPE,shell=True)
(grepFTDI,err) = grepFTDI.communicate()
if grepFTDI == '':
	print "ERROR: Device not found. Try replugging in the USB cable."
	sys.exit()
#end if

grepTuple = string.split(str(grepFTDI))
device = "/dev/"+grepTuple[-1]

##################################
# CONNECT TO DEVICE
###################################


try:
	print "Trying...",device
	con = serial.Serial(device,115200,timeout=2)
except:
	print "Failed to connect on",device
	sys.exit()
else:
	print "Connection succeeded on",device
#Send request for identifier 
try:
	#Be sure everything is empty before starting
	con.flushInput()
	con.flushOutput()
	time.sleep(.5) #XXX
	con.write('p')
except: 
	print "Error: failed to write to",device
#Attempt to read identifier from serial buffer
try:
	ident = con.read(5)
except:
	print "Error: failed to read from",device
else:
	ident = hex(struct.unpack('<ci',ident)[1])
	if ident == identifier:
#		conTest = 1
		print "Device confirmed."
	else:
		print "Error: wrong device."
		closeCon()
		sys.exit()

###################################
# GET CURRENT INDEX NUMBER AND TIMESTAMP
###################################

#Now request the index value (next one to write to)
#(index-1)*32 gives the address to stop reading data at
try:
	con.write('i')

except:
	print "Failed to send 'i'"
	closeCon()
	sys.exit()

#The value returned after sending 'i' is the next UNWRITTEN index
#newIndex will be the newest WRITTEN index
newIndex = con.read(5)
newIndex = struct.unpack('<ci',newIndex)[1]-1 

#Unix time truncated to the second (time of data point +/- 1 min)
epochTime = int(time.time()) 

print "newIndex",newIndex #XXX

##################################
# GET PREVIOUS INDEX NUMBER AND TIMESTAMP FROM FILE
##################################

dataDir = './DATA/'

#find the last file in the directory
lastFile = subprocess.Popen(['ls '+dataDir+' | tail -1'],stdout=subprocess.PIPE,shell=True)
(lastFile,err) = lastFile.communicate()

#print lastFile #XXX

if lastFile == '':
	oldIndex = 0
	timeStep = 66.8 #TODO
	print "Warning: No file found."
	print "Will write to new file..."
	print "Using approximate timestep of",timeStep,"seconds."
	print "Starting to read data at memory location 0x20..."
else:
	currentFile = dataDir+lastFile
	#Now open that file and find the last line
#	try:
#		with open(currentFile) as fh: #'with' auto closes file when done with nested code
	linestring = os.popen("tail -1 "+currentFile).read()
	lineTuple = string.split(linestring)
			#oldIndexPos = lineTuple.index('index')+1
	oldIndex = int(lineTuple[oldIndexPos])
	
			#unixPos = lineTuple.index('unix')+1
	begEpochTime = int(lineTuple[unixPos])
#	except IOError:
#		print 'ERROR: File failed to open ',currentFile	
#		sys.exit()
	
	print "oldIndex",oldIndex #XXX

##################################
# CALCULATE VALUES FOR GET DATA COMMAND
##################################

# Checking new and old index values
deltaIndex = newIndex - oldIndex

if deltaIndex == 0:
	print "No new data."
	closeCon()
	sys.exit()
elif deltaIndex < 0:
	print "ERROR: New index less than old index."
	closeCon()
	sys.exit()
elif deltaIndex > memSize:
	zeroLines = deltaIndex - memSize
	print "Warning:",str(zeroLines),"data points have been overwritten. Memory should be downloaded at least every 22 days."
	begBlAddr = (newIndex % memSize) + 1
elif deltaIndex <= memSize:
	begBlAddr = (oldIndex % memSize) + 1
#end if
print "begBlAddr",begBlAddr #XXX

endBlAddr = newIndex % memSize
print "endBlAddr",endBlAddr #XXX

numBlocks = ((endBlAddr-begBlAddr) % memSize)+1 
print "numBlocks",numBlocks #XXX

begByteAddr = begBlAddr*32

#Calculate approximate timestamp interval
try:
	timeStep = (epochTime - begEpochTime)/float(numBlocks)
except NameError:
	pass


##################################
# OPEN FILE AND READ DATA FROM SERIAL CONNECTION
##################################


#### THIS BIT LOOPS IN 64KB SEGMENTS
# This lets the fan controller run through it's control loop every few seconds

loopBlocks = numBlocks
loopBytes = numBlocks*32
segSize = 64*1024/32
#print 'Before while: ',numBlocks,loopBlocks,loopBytes #XXX

while loopBlocks >= segSize:
	print 'Downloading:',loopBlocks,'left.' #XXX
	loopBytes = segSize*32
	con.write(struct.pack('<cii','d',begByteAddr,loopBytes))
	try:
		data = data + con.read(loopBytes+1)[1:]
	except:
		data = con.read(loopBytes+1)[1:]
	begByteAddr += loopBytes
	loopBlocks -= segSize
#end While

#print "end while: ",loopBlocks,begByteAddr #XXX

if loopBlocks > 0:
	numBytes = loopBlocks*32
#	print 'in if: ',loopBlocks,numBytes,begByteAddr #XXX
	con.write(struct.pack('<cii','d',begByteAddr,numBytes))
	try:
		data = data + con.read(numBytes+1)[1:]
	except:
		data = con.read(numBytes+1)[1:]
#end if
print 'Fishined downloading data.'
#### END OF THE 64KB LOOP

##################################
# WRITE TO FILE
##################################
linesWritten = 0
for x in range (0,numBlocks):
	dataSeg = data[x*32:(x+1)*32]
	dataSeg = struct.unpack('<ihHHh4B8h',dataSeg)
	log_period = dataSeg[3]
	recordTime = int(round(epochTime-timeStep*(numBlocks-(x+1))))
	#timeString = time.asctime(time.gmtime(recordTime))
	timeString = UnixUTCtoISO(recordTime)
	record_num = str(dataSeg[0])
	fan_speed = str(dataSeg[1])
	status = "{0:#0{1}x}".format(dataSeg[2],6)
	log_period = str(log_period)
	setpoint = RndStr(dataSeg[4]/16.0)
	unused1 = str(dataSeg[5])
	unused2 = str(dataSeg[6])
	unused3 = str(dataSeg[7])
	unused4 = str(dataSeg[8])
	inR = RndStr(dataSeg[9]/16.0)
	inL = RndStr(dataSeg[10]/16.0)
	outR = RndStr(dataSeg[11]/16.0)
	outL = RndStr(dataSeg[12]/16.0)
	neu = RndStr(dataSeg[13]/16.0)
	Cs = RndStr(dataSeg[14]/16.0)
	TIC = RndStr(dataSeg[15]/16.0)
	bat = RndStr(dataSeg[16]/16.0)
	
	dataFile = dataDir+UnixUTCtoDateString(recordTime)+'.dat'
	fh = open(dataFile,"a+")

	fh.write(timeString)
	fh.write(" "+str(recordTime))
	fh.write(" "+record_num)
	fh.write(" "+fan_speed)
	fh.write(" "+status)
	fh.write(" "+log_period)
	fh.write(" "+setpoint)
	fh.write(" "+inR)
	fh.write(" "+inL)
	fh.write(" "+outR)
	fh.write(" "+outL)
	fh.write(" "+neu)
	fh.write(" "+Cs)
	fh.write(" "+TIC)
	fh.write(" "+bat)
	fh.write("\n")

	fh.close()
	linesWritten += 1
#end writing to file



if numBlocks != linesWritten:
	print "ERROR:",linesWritten,"lines written when",numBlocks,"lines expected."

closeCon()
sys.exit()



