//
//  vm.h
//  podracer
//
//  Created by Michael Kuehl on 28.11.20.
//

#ifndef vm_h
#define vm_h

VZVirtualMachineConfiguration *getVMConfig(unsigned long mem_size_mb,
    unsigned int nr_cpus, unsigned int console_type, NSString *cmdline, NSString *kernel_path,
    NSString *initrd_path, NSString *disc_path, NSString *cdrom_path, NSString *bridged_eth) ;

#endif /* vm_h */
