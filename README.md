Python Samples
==============

Some sample python scripts.

* sbf2offset.py : Pulls xPPSOffset data from SBF format files (requires pysbf)
* analyseTIC.py : Quick analysis of TIC data.  Produces several plots, applies xPPSOffset corrections

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

> python ./analyseTIC.py --offset xppsoffset.dat ticdata1.dat ticdata2.dat
