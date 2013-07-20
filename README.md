Python Samples
==============

Some sample python scripts.

* sbf2offset.py : Pulls xPPSOffset data from SBF format files (requires pysbf)
* analyseTIC.py : Quick analysis of TIC data.  Produces several plots, applies 
xPPSOffset corrections

*All scripts require Python 2.7*

sbf2offset.py
-------------
Reads in SBF format files and locates all xPPSOffset data.  It then prints
the xPPSOffset values and the time of the offset to STDOUT.

*Requires https://github.com/jashandeep-sohi/pysbf*

> sbf2offset.py gpslog.sbf >xppsoffset.dat

analyseTIC.py
-------------
Reads in TIC data from sr620 DAQ software.  It finds gaps of arbitrary size and
splits the data set at those points.  Then, it produces a time series plots and
histograms.  If there are xPPSOffset corrections to be applied to the TIC data
provided, then it can also read in xPPSOffset data (output from sbf2offset.py),
apply those corrections to the TIC data set, and re-plot the time series and
histogram.

> python2.7 ./analyseTIC.py --offset xppsoffset.dat ticdata1.dat ticdata2.dat

getTravTempLog.py
-----------------
Works only when connected to the Traveler Box internal controller via USB.

sbf2PVTGeo.py
-------------
Extracts PVTGeodetic block data from SBF files.  Use it just like sbf2offset.py

> sbf2offset.py gpslog.sbf >pvtGeo.dat

mkRINEX+CGGTTS.sh
-----------------
Runs through hard-coded GPS data stores and finds SBF files with full pathnames
matching the given Regular Expression.  For each of the matching SBF file
names, the data is extracted and exported in several different files and
formats (also to hard- coded data stores).

Execute just the data location portion of the script and print which files
would be operated on if run without the --dry-run option.  In this case, only
PT00, the NU1 GPS, would match; other GPSes would be listed as not having any
files to process as they do not match the expression.
> mkRINEX+CGGTTS.sh --dry-run 'PT00.*' 

Process all SBF files from all GPS recieves but only the ones that came from
the internal logging process and only for the first day of the year or '001' as
it is recorded in the SBF file names.
> mkRINEX+CGGTTS.sh 'Internal.*0010'

Process files from all GPS receivers for 2013 (SBF files containing '.13' after
the day of the year) for days of the year 90-129.  But, skip the production
of CGGTTS files.
> mkRINEX+CGGTTS.sh --noCGGTTS '(09[0-9]|1[012][0-9])0\.13'
