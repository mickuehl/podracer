
#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>

#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <termios.h>
#include <limits.h>
#include <errno.h>
#include <poll.h>
#include <util.h>
#include "vm.h"

static void attachDevices(VZVirtualMachineConfiguration *conf, NSString *discPath, NSString *cdromPath, NSString *ifConf) {
    
    // stdin, stdout
    int ifd = 0, ofd = 1;
    VZNetworkDeviceAttachment *nda = nil;
    NSURL *discURL = nil;
    NSURL *cdromURL = nil;
    
    if (discPath)
        discURL = [NSURL fileURLWithPath:discPath];
    if (cdromPath)
        cdromURL = [NSURL fileURLWithPath:cdromPath];
    
    NSFileHandle *stdOut = [[NSFileHandle alloc] initWithFileDescriptor:ofd];
    NSFileHandle *stdIn = [[NSFileHandle alloc] initWithFileDescriptor:ifd];
    VZSerialPortAttachment *spa = [[VZFileHandleSerialPortAttachment alloc] initWithFileHandleForReading:stdIn fileHandleForWriting:stdOut];
    
    VZVirtioConsoleDeviceSerialPortConfiguration *consConf = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
    [consConf setAttachment:spa];
    [conf setSerialPorts:@[consConf]];
    
    // network devices
    NSArray *bni = [VZBridgedNetworkInterface networkInterfaces];
    VZBridgedNetworkInterface *iface = nil;
    for (id o in bni) {
        if (![[o identifier] compare:ifConf]) {
            NSLog(@"[  OK  ] Found bridged interface for %@ (%@).\n", [o identifier], [o localizedDisplayName]);
            iface = o;
        }
    }

    if (ifConf && !iface) {
        NSLog(@"[FAILED] Warning: Network interface '%@' not found.\n", ifConf);
    }
    if (iface) {
        nda = [[VZBridgedNetworkDeviceAttachment alloc] initWithInterface:iface];
    }
    if (!nda) {
        nda = [[VZNATNetworkDeviceAttachment alloc] init];
    }
    
    VZVirtioNetworkDeviceConfiguration *netConf = [[VZVirtioNetworkDeviceConfiguration alloc] init];
    [netConf setAttachment:nda];
    [conf setNetworkDevices:@[netConf]];
    
    // entropy device for random numbers
    VZEntropyDeviceConfiguration *entropyConf = [[VZVirtioEntropyDeviceConfiguration alloc] init];
    [conf setEntropyDevices:@[entropyConf]];
    
    // volumes
    NSArray *volumes = @[];

    if (discURL) {
        VZDiskImageStorageDeviceAttachment *disc_sda = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:discURL readOnly:false error:nil];
        if (disc_sda) {
            VZStorageDeviceConfiguration *disc_conf = [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:disc_sda];
            volumes = [volumes arrayByAddingObject:disc_conf];
            
            NSLog(@"[  OK  ] Attached disc '%@'.\n", discURL);
        } else {
            NSLog(@"[FAILED] Couldn't open disc at %@.\n", discURL);
        }
    }

    if (cdromURL) {
        VZDiskImageStorageDeviceAttachment *cdrom_sda = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:cdromURL readOnly:true error:nil];
        if (cdrom_sda) {
            VZStorageDeviceConfiguration *cdrom_conf = [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:cdrom_sda];
            volumes = [volumes arrayByAddingObject:cdrom_conf];
            
            NSLog(@"[  OK  ] Attached CDROM '%@'.\n", cdromURL);
        } else {
            NSLog(@"[FAILED] Couldn't open disc at %@.\n", discURL);
        }
    }

    [conf setStorageDevices:volumes];
}

static VZVirtualMachineConfiguration *createVMConfiguration(NSString *pathToKernel, NSString *pathToRamdisk, NSString *kernelParams, unsigned int cpus, unsigned long memSize) {
    
    // bootloader setup
    NSURL *kernelURL = [NSURL fileURLWithPath:pathToKernel];
    NSURL *initrdURL = nil;
    
    if (pathToRamdisk)
        initrdURL = [NSURL fileURLWithPath:pathToRamdisk];
    
    VZLinuxBootLoader *lbl = [[VZLinuxBootLoader alloc] initWithKernelURL:kernelURL];
    [lbl setCommandLine:kernelParams];
    if (initrdURL)
        [lbl setInitialRamdiskURL:initrdURL];
    
    // VM configuration
    VZVirtualMachineConfiguration *conf = [[VZVirtualMachineConfiguration alloc] init];
    [conf setBootLoader:lbl];
    [conf setCPUCount:cpus];
    [conf setMemorySize:memSize*1024*1024UL];
    
    return conf;
}

NSString *stateToString(int state) {

    switch(state) {
        case VZVirtualMachineStateStopped:
            return @"STOPPED";
        case VZVirtualMachineStateRunning:
            return @"RUNNING";
        case VZVirtualMachineStatePaused:
            return @"PAUSED";
        case VZVirtualMachineStateError:
            return @"ERROR";
        case VZVirtualMachineStateStarting:
            return @"STARTING";
        case VZVirtualMachineStatePausing:
            return @"PAUSING";
        case VZVirtualMachineStateResuming:
            return @"RESUMING";
        default:
            return @"UNKNOWN";
    }
}

int startVirtualMachine(NSString *pathToKernel, NSString *pathToRamdisk, NSString *kernelParams, NSString *discPath, NSString *cdromPath, NSString *ifConf, unsigned int cpus, unsigned long memSize) {
    
    // create the basic kernel/VM configuration
    VZVirtualMachineConfiguration *conf = createVMConfiguration(pathToKernel, pathToRamdisk, kernelParams, cpus, memSize) ;
    if (!conf) {
        NSLog(@"[FAILED] Couldn't create VM configuration.\n");
        exit(1);
    }
    
    // attach stdio, discs and network
    attachDevices(conf, discPath, cdromPath, ifConf) ;
    
    // validate the configuration
    NSError *confErr = NULL;
    [conf validateWithError:&confErr];

    if (confErr) {
        NSLog(@"[FAILED] VM validation failed: %@\n", confErr);
        exit(1);
    }
    NSLog(@"[  OK  ] VM configuration is valid.\n");
 
    // start the VM
    dispatch_queue_t queue = dispatch_queue_create("Secondary queue", NULL);
    
    VZVirtualMachine *vm = [[VZVirtualMachine alloc] initWithConfiguration:conf queue:queue];
    
    dispatch_sync(queue, ^{
        NSLog(@"         %@", stateToString((int)vm.state)) ;
        if (!vm.canStart) {
            NSLog(@"[FAILED] VM can not be started :(\n");
            exit(1);
        }
    });
 
    dispatch_sync(queue, ^{
        [vm startWithCompletionHandler:^(NSError *errorOrNil){
            if (errorOrNil) {
                NSLog(@"[FAILED] VM start error: %@\n", errorOrNil);
                exit(1);
            } else {
                NSLog(@"[  OK  ] VM started.\n");
            }
        }];
    });
    
    // We could register a delegate and get async updates from the state, e.g. shutdown.
    do {
        sleep(1);
    } while(vm.state == VZVirtualMachineStateRunning || vm.state == VZVirtualMachineStateStarting);
    
    return (int)vm.state ;
}
