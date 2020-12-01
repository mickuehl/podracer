
#ifndef vm_h
#define vm_h

int startVirtualMachine(NSString *pathToKernel, NSString *pathToRamdisk, NSString *kernelParams, NSString *discPath, NSString *cdromPath, NSString *ifConf, unsigned int cpus, unsigned long memSize) ;

NSString *stateToString(int state) ;

#endif /* vm_h */
