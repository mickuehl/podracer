//
//  main.m
//  podracer
//
//  Created by Michael Kuehl on 28.11.20.
//
//

#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import "vm.h"

#define VERSION "v0.1 25/11/2020"

static void usage(const char *me)
{
    fprintf(stderr, "Syntax:\n\t%s <options>\n\n"
                    "Options are:\n"
                    "\t-k <kernel path> [REQUIRED]\n"
                    "\t-a <kernel cmdline arguments>\n"
                    "\t-i <initrd path>\n"
                    "\t-d <disc image path>\n"
                    "\t-c <CDROM image path>\n"
                    "\t-b <bridged ethernet interface> [otherwise NAT]\n"
                    "\t-p <number of processors>\n"
                    "\t-m <memory size in MB>\n",
                    me);
}


int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];

        if (argc == 1) {
            usage(argv[0]);
            return 1;
        }
        NSString *kern_path = [standardDefaults stringForKey:@"k"];
        NSString *cmdline = [standardDefaults stringForKey:@"a"];
        NSString *initrd_path = [standardDefaults stringForKey:@"i"];
        NSString *disc_path = [standardDefaults stringForKey:@"d"];
        NSString *cdrom_path = [standardDefaults stringForKey:@"c"];
        NSString *eth_if = [standardDefaults stringForKey:@"b"];
        NSInteger cpus = [standardDefaults integerForKey:@"p"];
        NSInteger mem = [standardDefaults integerForKey:@"m"];

        if (!kern_path) {
            fprintf(stderr, "--- Need kernel path!\n");
            usage(argv[0]);
            return 1;
        }

        if (!cmdline) {
            cmdline = @"console=hvc0";
        }
        
        if (cpus == 0) {
            cpus = 1;
        }
        
        if (mem == 0) {
            mem = 512;
        }
        
        NSLog(@"vftool (" VERSION ") starting");

        /* **************************************************************** */
        // Create config

        VZVirtualMachineConfiguration *conf = getVMConfig(mem, (int)cpus, 0, cmdline, kern_path, initrd_path, disc_path, cdrom_path, eth_if);
 
        if (!conf) {
            NSLog(@"Couldn't create configuration for VM.\n");
            return 1;
        }

        /* **************************************************************** */
        // Validate config
        
        NSError *confErr = NULL;
        [conf validateWithError:&confErr];

        if (confErr) {
            NSLog(@"-- Configuration vaildation failure! %@\n", confErr);
            return 1;
        }
        NSLog(@"+++ Configuration validated.\n");
        
        /* **************************************************************** */
        // Create VM

        // Create a secondary dispatch queue because I don't want to use dispatch_main here
        // (i.e. the blocks/interaction works on the main queue unless we do this).
        dispatch_queue_t queue = dispatch_queue_create("Secondary queue", NULL);
        
        VZVirtualMachine *vm = [[VZVirtualMachine alloc] initWithConfiguration:conf queue:queue];
        
        dispatch_sync(queue, ^{
            NSLog(@"+++ canStart = %d, vm state %d\n", vm.canStart, (int)vm.state);
            if (!vm.canStart) {
                NSLog(@"--- VM is not startable :(\n");
                exit(1);
            }
        });

        // Start VM
        dispatch_sync(queue, ^{
            [vm startWithCompletionHandler:^(NSError *errorOrNil){
                if (errorOrNil) {
                    NSLog(@"--- VM start error: %@\n", errorOrNil);
                    exit(1);
                } else {
                    NSLog(@"+++ VM started\n");
                }
            }];
        });
        
        // We could register a delegate and get async updates from the state, e.g. shutdown.
        do {
            sleep(1);
        } while(vm.state == VZVirtualMachineStateRunning ||
                vm.state == VZVirtualMachineStateStarting);
        
        NSLog(@"+++ Done, state = %d\n", (int)vm.state);
    }
    return 0;
}

