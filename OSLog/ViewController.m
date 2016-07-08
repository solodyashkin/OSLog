//
//  ViewController.m
//  OSLog
//
//  Created by Roman Solodyashkin on 7/7/16.
//  Copyright © 2016 IoStream. All rights reserved.
//

#import "ViewController.h"
#import <sys/stat.h>

const int MaxLogSize = 1024;

@interface ViewController ()
{
    NSString *logFilePath;
    NSData *bufData;
    NSDate *bufDate;
    NSByteCountFormatter *bytesFormatter;
    dispatch_source_t source;
    FILE *logFile;
    BOOL testLogRunFlag;
    
    char logBuffer[MaxLogSize];
}
@property (nonatomic, weak) IBOutlet UILabel *appLogSizeLabel;
@property (nonatomic, weak) IBOutlet UILabel *bufLogSizeLabel;
@property (nonatomic, weak) IBOutlet UILabel *flushLabel;
@property (nonatomic, weak) IBOutlet UISwitch *flushSwitch;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    bytesFormatter = [[NSByteCountFormatter alloc] init];
    bytesFormatter.includesActualByteCount = YES;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask, YES);
    NSString *documentsDirectory = paths.firstObject;
    logFilePath = [documentsDirectory stringByAppendingPathComponent:@"logFile.txt"];
    logFile = freopen(logFilePath.UTF8String,"a+", stderr);
    
    [self flushSwitchAction:nil];
    
    dispatch_block_t handler = ^(){
        
        const int inputfd = fileno(logFile);
        
        struct stat st;
        const int rstat = fstat( inputfd, &st );
        
        if ( rstat < 0 )
        {
            NSLog(@"fstat failed: %s", strerror(rstat));
        }
        else
        {
            // limit to MaxLogSize
            if ( st.st_size >= MaxLogSize )
            {
                // lock log file
                const int lres = flock(inputfd, LOCK_EX);
                if ( 0 == lres )
                {
                    // read log data
                    bufData = [NSData dataWithContentsOfFile:logFilePath];
                    bufDate = [NSDate date];
                    
                    // truncate log to zero lenght
                    const int tres = ftruncate(inputfd, 0);
                    if ( 0 != tres )
                    {
                        NSLog(@"truncate failed: %s", strerror(tres));
                    }
                    
                    // unlock log file
                    flock(inputfd, LOCK_UN);
                }
                else
                {
                    NSLog(@"lock failed: %s", strerror(lres));
                }
            }
            
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.appLogSizeLabel.text = [NSString stringWithFormat:@"App log size:%@", [bytesFormatter stringFromByteCount:st.st_size]];
                self.bufLogSizeLabel.text = [NSString stringWithFormat:@"Buf log size:%@, date:%@", [bytesFormatter stringFromByteCount:bufData.length], bufDate];
            });
        }
    };
    
    source =
    [ViewController monitorFileAtPath:logFilePath
                     withEventHandler:handler
                                queue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
    
    // test logging
    testLogRunFlag = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        while ( YES == testLogRunFlag )
        {
            @autoreleasepool
            {
                fprintf(stderr, [NSString stringWithFormat:@"%@ some message\n", [NSDate date]].UTF8String, NULL);
                // look to flushSwitchAction
                //fflush(logFile);
                usleep(500000);
            }
        }
    });
}

- (IBAction)flushSwitchAction:(id)sender
{
    if ( YES == self.flushSwitch.on )
    {
        // v1 set stderr buf size to zero, monitor handler will be called at any write via fprintf or other.
        // if need ~fixed log size use v2 with better perfomance
        setbuf(stderr, NULL);
        self.flushLabel.text = @"Flushed to disk on every call";
    }
    else
    {
        // v2 stderr aumatically flushes when buffer is full and monitor handler will be called
        setvbuf(stderr, logBuffer, _IOFBF, sizeof(logBuffer));
        self.flushLabel.text = @"Flushed to disk when stderr buffer is full";
    }
}

- (void)dealloc
{
    testLogRunFlag = NO;
    
    if ( nil != source )
    {
        if ( 0 == dispatch_source_testcancel(source) )
        {
            dispatch_source_cancel(source);
        }
        source = nil;
    }
    
    if ( NULL != logFile )
        fclose(logFile);
}

+ (dispatch_source_t)monitorFileAtPath:(NSString*)path withEventHandler:(dispatch_block_t)block queue:(dispatch_queue_t)queue
{
    int fildes = open([path UTF8String], O_EVTONLY);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fildes,
                                                      DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND,
                                                      queue);
    dispatch_source_set_event_handler(source, block);
    dispatch_source_set_cancel_handler(source, ^{
        close(fildes);
    });
    dispatch_resume(source);
    return source;
}

@end
