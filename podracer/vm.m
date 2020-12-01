
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

static int createPty(bool waitForConnection)
{
    struct termios tos;
    char ptsn[PATH_MAX];
    int sfd;
    int tty_fd;

    if (openpty(&tty_fd, &sfd, ptsn, &tos, NULL) < 0) {
        perror("openpty: ");
        return -1;
    }

    if (tcgetattr(sfd, &tos) < 0) {
        perror("tcgetattr:");
        return -1;
    }

    cfmakeraw(&tos);
    if (tcsetattr(sfd, TCSAFLUSH, &tos)) {
        perror("tcsetattr:");
        return -1;
    }
    close(sfd);

    int f = fcntl(tty_fd, F_GETFL);
    fcntl(tty_fd, F_SETFL, f | O_NONBLOCK);

    NSLog(@"+++ fd %d connected to %s\n", tty_fd, ptsn);
    
    if (waitForConnection) {
        // Causes a HUP:
        close(open(ptsn, O_RDWR | O_NOCTTY));

        NSLog(@"+++ Waiting for connection to:  %s\n", ptsn);

        // Poll for the HUP to go away:
        struct pollfd pfd = {
            .fd = tty_fd,
            .events = POLLHUP
        };
        
        do {
            poll(&pfd, 1, 100);
        } while (pfd.revents & POLLHUP);
    }

    return tty_fd;
}

/* console_type: 0 stdout/in, 1 pty */
VZVirtualMachineConfiguration *getVMConfig(unsigned long mem_size_mb,
    unsigned int nr_cpus, unsigned int console_type, NSString *cmdline, NSString *kernel_path,
    NSString *initrd_path, NSString *disc_path, NSString *cdrom_path, NSString *bridged_eth)
{
    // Linux bootloader setup:
    
    NSURL *kernelURL = [NSURL fileURLWithPath:kernel_path];
    NSURL *initrdURL = nil;
    NSURL *discURL = nil;
    NSURL *cdromURL = nil;

    if (initrd_path)
        initrdURL = [NSURL fileURLWithPath:initrd_path];

    if (disc_path)
        discURL = [NSURL fileURLWithPath:disc_path];

    if (cdrom_path)
        cdromURL = [NSURL fileURLWithPath:cdrom_path];

    NSLog(@"+++ Linux bootloader setup: kernel at %@, initrd at %@, cmdline '%@', %d cpus, %luMB memory\n", kernelURL, initrdURL, cmdline, nr_cpus, mem_size_mb);

    VZLinuxBootLoader *lbl = [[VZLinuxBootLoader alloc] initWithKernelURL:kernelURL];
    [lbl setCommandLine:cmdline];
    if (initrdURL)
        [lbl setInitialRamdiskURL:initrdURL];

    // Configuration setup
    
    VZVirtualMachineConfiguration *conf = [[VZVirtualMachineConfiguration alloc] init];

    /* I can't seem to access members such as maximumAllowedCPUCount and maximumAllowedMemorySize :( */
    [conf setBootLoader:lbl];
    [conf setCPUCount:nr_cpus];
    [conf setMemorySize:mem_size_mb*1024*1024UL];

    // Devices
    
    // Serial
    int ifd = 0, ofd = 1;

    if (console_type == 1) {
        int pty = createPty(true);
        if (pty < 0) {
            NSLog(@"--- Error creating pty for serial console!\n");
            return nil;
        }
        ifd = pty;
        ofd = pty;
    }

    NSFileHandle *cons_out = [[NSFileHandle alloc] initWithFileDescriptor:ofd];
    NSFileHandle *cons_in = [[NSFileHandle alloc] initWithFileDescriptor:ifd];
    VZSerialPortAttachment *spa = [[VZFileHandleSerialPortAttachment alloc] initWithFileHandleForReading:cons_in fileHandleForWriting:cons_out];
    
    VZVirtioConsoleDeviceSerialPortConfiguration *cons_conf = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
    [cons_conf setAttachment:spa];
    [conf setSerialPorts:@[cons_conf]];

    // Network
    NSArray *bni = [VZBridgedNetworkInterface networkInterfaces];
    VZBridgedNetworkInterface *iface = nil;
    for (id o in bni) {
        if (![[o identifier] compare:bridged_eth]) {
            NSLog(@"+++ Found bridged interface object for %@ (%@)\n", [o identifier], [o localizedDisplayName]);
            iface = o;
        }
    }

    if (bridged_eth && !iface) {
        NSLog(@"--- Warning: ethernet interface %@ not found\n", bridged_eth);
    }

    VZNetworkDeviceAttachment *nda = nil;

    if (iface) {
        // Attempt to create a bridged attachment:
        nda = [[VZBridgedNetworkDeviceAttachment alloc] initWithInterface:iface];
    }
    // Otherwise, or if failed, create a NAT attachment:
    if (!nda) {
        nda = [[VZNATNetworkDeviceAttachment alloc] init];
    }
    
    VZVirtioNetworkDeviceConfiguration *net_conf = [[VZVirtioNetworkDeviceConfiguration alloc] init];
    [net_conf setAttachment:nda];
    [conf setNetworkDevices:@[net_conf]];
    
    // Entropy
    VZEntropyDeviceConfiguration *entropy_conf = [[VZVirtioEntropyDeviceConfiguration alloc] init];
    [conf setEntropyDevices:@[entropy_conf]];
    
    // Storage/disc
    NSArray *discs = @[];

    if (discURL) {
        NSLog(@"+++ Attaching disc %@\n", discURL);
        VZDiskImageStorageDeviceAttachment *disc_sda = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:discURL readOnly:false error:nil];
        if (disc_sda) {
            VZStorageDeviceConfiguration *disc_conf = [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:disc_sda];
            discs = [discs arrayByAddingObject:disc_conf];
        } else {
            NSLog(@"--- Couldn't open disc at %@\n", discURL);
        }
    }

    if (cdromURL) {
        NSLog(@"+++ Attaching CDROM %@\n", cdromURL);
        VZDiskImageStorageDeviceAttachment *cdrom_sda = [[VZDiskImageStorageDeviceAttachment alloc]
                                                         initWithURL:cdromURL
                                                         readOnly:true error:nil];
        if (cdrom_sda) {
            VZStorageDeviceConfiguration *cdrom_conf = [[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:cdrom_sda];
            discs = [discs arrayByAddingObject:cdrom_conf];
        } else {
            NSLog(@"--- Couldn't open disc at %@\n", discURL);
        }
    }

    [conf setStorageDevices:discs];

    return conf;
}
