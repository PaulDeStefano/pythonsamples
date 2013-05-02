# python script

import tabular as tb
import numpy as np
import matplotlib.pylab as pylab
import matplotlib.pyplot as plt

def mkHist1() :
    newt = tb.io.loadSV('PT003050.csv')[0]
    plt.figure(1)
    plt.xlabel("Clock Bias (ns)")
    plt.ylabel("Frequency")
    n, bins, patches = plt.hist(newt['rcvr_clk_ns'] , bins=50,  )
    p = np.polyfit(newt['decimal_hour'],newt['rcvr_clk_ns'],1)
    print p
    #pFunc = np.poly1d(p)
    plt.show()


def mkClkBias() :
    t2 = tb.io.loadSV('PT003050.new.csv')[0]
    plt.figure(2)
    plt.title('Clock Bias (w/ linear trend removed)')
    plt.xlabel('Hours of the Day')
    plt.ylabel('Bias (ns)')
    plt.grid(True)
    plt.plot( t2['decimal_hour'], t2['rcvr_clck_ns-trend'] )

def mkHist2() :
    t2 = tb.io.loadSV('PT003050.new.csv')[0]
    plt.figure(3)
    plt.title('Clock Bias (w/o Trend) Histogram')
    plt.xlabel('Bias (ns)')
    plt.ylabel('Frequency')
    n,bins,patches = plt.hist(t2['rcvr_clck_ns-trend'], 20, histtype='step' )

## MAIN ##
if __name__ == '__main__' :
    #mkHist1()
    #mkClkBias()
    mkHist2()
    plt.show()

