# -*- coding: utf-8 -*-
"""
Created on Wed Oct 27 16:54:06 2021

@author: Sophocles
"""

import numpy as np
import math


while True:
  try:
    D = int(input("Enter The Diameter: "))
    break
  except ValueError:
      print("The Diameter can be only integer ...")
      continue
  
    
R =float(input("Enter the Range :"))


array1= np.arange(D*D)
array1 =array1.reshape(D , D)

## vohthitiko print
print(array1)  


topolist =  []  ## List of each node's neighbors
count=0         ## 


for i in range(D):
        for j in range (D): 
            neighblist=[]   ## help var for insert every neighbor in each node
            for k in range(math.floor(R)):
                    if(i-k-1>=0):
                        neighblist.append(array1[i-k-1][j])    ##Do not exceed top borders
                    
                    if(i+k+1<D):   
                         neighblist.append(array1[i+k+1][j])   ##Do not exceed  bot borders
                         
                    if(j-k-1>=0):
                         neighblist.append(array1[i][j-k-1])     ##Do not exceed left borders
                    
                    if(j+k+1<D):
                         neighblist.append(array1[i][j+k+1])  ##Do not exceed right borders
                    
                    if (i-k-1>=0 and j-k-1>=0):
                         neighblist.append(array1[i-k-1][j-k-1])   ##Do not exceed top left borders
                        
                    if (i+k+1<D and j-k-1>=0):  
                         neighblist.append(array1[i+k+1][j-k-1])   ##Do not exceed bot left borders
                        
                    if(i-k-1>=0 and j+k+1<D):
                         neighblist.append(array1[i-k-1][j+k+1])   ##Do not exceed top right borders
                         
                    if(i+k+1<D and j+k+1<D):
                         neighblist.append(array1[i+k+1][j+k+1])   ## Do not exceed bot right borders
                    
                    topolist.insert(count,neighblist)
                    count +=1

file = open("topology.txt","w")
for m in range(len(topolist)):
    for n in range(len(topolist[m])):
        file.write(str(m) + " " + str(topolist[m][n]) + " -50\n")

file.close()
      
    
    