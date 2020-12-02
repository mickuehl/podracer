
#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>
#import "vm.h"

#define VERSION "v0.1.0"

static void usage(const char *me) {
    fprintf(stderr, "Usage:\n\t%s -k <kernel path> [options]\n\n"
                    "Options are:\n"
                    "\t-k <kernel path> [REQUIRED]\n"
                    "\t-a <kernel parameters>\n"
                    "\t-i <initrd path>\n"
                    "\t-d <disc image path>\n"
                    "\t-c <CDROM image path>\n"
                    "\t-b <bridged ethernet interface> [default: NAT]\n"
                    "\t-p <number of processors> [default: 1]\n"
                    "\t-m <memory size in MB> [default: 512MB]\n",
                    me);
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];

        NSLog(@"\n\npodracer (" VERSION ")\n\n");
        
        if (argc == 1) {
            usage(argv[0]);
            exit(1);
        }
        
        NSString *pathToKernel = [standardDefaults stringForKey:@"k"];
        NSString *kernelParams = [standardDefaults stringForKey:@"a"];
        NSString *pathToRamdisk = [standardDefaults stringForKey:@"i"];
        NSString *discPath = [standardDefaults stringForKey:@"d"];
        NSString *cdromPath = [standardDefaults stringForKey:@"c"];
        NSString *ifConf = [standardDefaults stringForKey:@"b"];
        NSInteger cpus = [standardDefaults integerForKey:@"p"];
        NSInteger mem = [standardDefaults integerForKey:@"m"];

        if (!pathToKernel) {
            usage(argv[0]);
            exit(1);
        }
        if (!kernelParams) {
            kernelParams = @"console=hvc0";
        }
        if (cpus == 0) {
            cpus = 1;
        }
        if (mem == 0) {
            mem = 512;
        }
        
        // create & start the VM
        NSInteger state = startVirtualMachine(pathToKernel, pathToRamdisk, kernelParams, discPath, cdromPath, ifConf, (int)cpus, (int)mem);
        NSLog(@"         %@", stateToString((int)state)) ;
    }
    return 0;
}

