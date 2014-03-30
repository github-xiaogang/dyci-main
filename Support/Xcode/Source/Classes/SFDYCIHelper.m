//
//  SFDYCIHelper.m
//  SFDYCIHelper
//
//  Created by Paul Taykalo on 09/07/12.
//
//

#import "SFDYCIHelper.h"
#import "GCDAsyncSocket.h"

@interface SFDYCIHelper ()<NSNetServiceDelegate ,NSNetServiceBrowserDelegate, GCDAsyncSocketDelegate>


@end

@implementation SFDYCIHelper

#pragma mark - Plugin Initialization

+ (void)pluginDidLoad:(NSBundle *)plugin {
    static id sharedPlugin = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPlugin = [[self alloc] init];
    });
}

- (id)init {
    if (self = [super init]) {
        NSNotificationCenter * notificationCenter = [NSNotificationCenter defaultCenter];
        
        // Waiting for application start
        [notificationCenter addObserver:self
                               selector:@selector(applicationDidFinishLaunching:)
                                   name:NSApplicationDidFinishLaunchingNotification
                                 object:nil];
    }
    return self;
}


- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSLog(@"App finished launching");
    NSMenuItem * runMenuItem = [[NSApp mainMenu] itemWithTitle:@"Product"];
    if (runMenuItem) {
        
        NSMenu * subMenu = [runMenuItem submenu];
        
        // Adding separator
        [subMenu addItem:[NSMenuItem separatorItem]];
        
        // Adding inject item
        NSMenuItem * recompileAndInjectMenuItem =
        [[NSMenuItem alloc] initWithTitle:@"Recompile and inject"
                                   action:@selector(recompileAndInject:)
                            keyEquivalent:@"x"];
        [recompileAndInjectMenuItem setKeyEquivalentModifierMask:NSControlKeyMask];
        [recompileAndInjectMenuItem setTarget:self];
        [subMenu addItem:recompileAndInjectMenuItem];
        
    }
    
}

#pragma mark - Preferences

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    // TODO : We need correct checks, when we can use Ibject, and where we cannot
    // Validate when we need to be called
    //   if ([menuItem action] == @selector(recompileAndInject:)) {
    //      NSResponder * firstResponder = [[NSApp keyWindow] firstResponder];
    //
    //      NSLog(@"Validation check");
    //      while (firstResponder) {
    //         firstResponder = [firstResponder nextResponder];
    //         NSLog(@"firstResponder = %@", firstResponder);
    //      }
    //      return ([firstResponder isKindOfClass:NSClassFromString(@"DVTSourceTextView")] && [firstResponder isKindOfClass:[NSTextView class]]);
    //   }
    return YES;
}


- (void)recompileAndInject:(id)sender {
    NSResponder * firstResponder = [[NSApp keyWindow] firstResponder];
    // Searching our IDEEditorContext
    // This class has information about URL of file that being edited
    while (firstResponder) {
        firstResponder = [firstResponder nextResponder];
        if ([firstResponder isKindOfClass:NSClassFromString(@"IDEEditorContext")]) {
            // Resolving currently opened file
            NSURL * openedFileURL = [firstResponder valueForKeyPath:@"editor.document.fileURL"];
            NSString * path = [openedFileURL absoluteString];
            //只允许为代码
            if(!([path rangeOfString:@".m"].length != 0 || [path rangeOfString:@".mm"].length != 0)) return;
            NSLog(@"Opened file url is : %@", openedFileURL);
            // Setting up task, that we are going to call
            
            NSTask * mainTask = [[NSTask alloc] init];
            [mainTask setLaunchPath:@"/usr/bin/python"];
            NSString * dyciDirectoryPath = [@"~" stringByExpandingTildeInPath];
            dyciDirectoryPath = [dyciDirectoryPath stringByAppendingPathComponent:@".dyci"];
            dyciDirectoryPath = [dyciDirectoryPath stringByAppendingPathComponent:@"scripts"];
            [mainTask setCurrentDirectoryPath:dyciDirectoryPath];
            NSString * dyciRecompile = [dyciDirectoryPath stringByAppendingPathComponent:@"dyci-recompile.py"];
            NSArray * arguments = [NSArray arrayWithObjects:dyciRecompile, [openedFileURL path], nil];
            [mainTask setArguments:arguments];
            // Setting up pipes for standart and error outputs
            NSPipe * outputPipe = [NSPipe pipe];
            NSFileHandle * outputFile = [outputPipe fileHandleForReading];
            [mainTask setStandardOutput:outputPipe];
            
            NSPipe * errorPipe = [NSPipe pipe];
            NSFileHandle * errorFile = [errorPipe fileHandleForReading];
            [mainTask setStandardError:errorPipe];
            
            // Setting up termination handler
            [mainTask setTerminationHandler:^(NSTask * tsk) {
                NSData * outputData = [outputFile readDataToEndOfFile];
                NSString * outputString = [[NSString alloc] initWithData:outputData
                                                                encoding:NSUTF8StringEncoding];
                if (outputString && [outputString length]) {
                    NSLog(@"script returned OK:\n%@", outputString);
                }
                NSData * errorData = [errorFile readDataToEndOfFile];
                NSString * errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
                if (errorString && [errorString length]) {
                    NSLog(@"script returned ERROR:\n%@", errorString);
                }
                // TODO : Need to add correct notification if something went wrong
                if (mainTask.terminationStatus != 0) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        NSAlert * alert = [[NSAlert alloc] init];
                        [alert addButtonWithTitle:@"OK"];
                        [alert setMessageText:@"Failed to inject code"];
                        [alert setInformativeText:errorString];
                        [alert setAlertStyle:NSCriticalAlertStyle];
                        [alert runModal];
                    });
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self showResultViewWithSuccess:NO];
                    });
                }else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSTask * codesignTask = [[NSTask alloc] init];
                        [codesignTask setLaunchPath:@"/bin/bash"];
                        NSString *shellPath=[[NSBundle bundleForClass:[self class]] pathForResource:@"codesign" ofType:@"sh"];
                        NSArray * arguments = [NSArray arrayWithObjects:shellPath, [self dylibFilePath], nil];
                        [codesignTask setArguments:arguments];
                        // Setting up pipes for standart and error outputs
                        NSPipe * errorPipe = [NSPipe pipe];
                        NSFileHandle * errorFile = [errorPipe fileHandleForReading];
                        [codesignTask setStandardError:errorPipe];
                        // Setting up termination handler
                        [codesignTask setTerminationHandler:^(NSTask * tsk) {
                            NSData * errorData = [errorFile readDataToEndOfFile];
                            NSString * errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
                            if (errorString && [errorString length]) {
                                NSLog(@"script returned MESSAGE:\n%@", errorString);
                            }
                            // TODO : Need to add correct notification if something went wrong
                            if (codesignTask.terminationStatus != 0) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    NSLog(@"-------    code sign ERROR ------");
                                });
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [self showResultViewWithSuccess:NO];
                                });
                            }else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    NSLog(@"############  1. Generate dylib and sign dylib Done  ############");
                                    [self sendDylib];
                                    [self showResultViewWithSuccess:YES];
                                });
                            }
                            tsk.terminationHandler = nil;
                        }];
                        // Starting task
                        [codesignTask launch];
                    });
                }
                tsk.terminationHandler = nil;
            }];
            // Starting task
            [mainTask launch];
            return;
        }
    }
    NSLog(@"Coudln't find IDEEditorContext... Seems you've pressed somewhere in incorrect place");
}

- (void)showResultViewWithSuccess:(BOOL)success {
    /*
     SFDYCIResultView * resultView = [[[SFDYCIResultView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)] autorelease];
     resultView.success = success;
     
     // Adding result view on window
     [[[NSApp keyWindow] contentView] addSubview:resultView];
     
     
     // Performing animations
     resultView.alphaValue = 0.0;
     
     [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
     
     context.duration = 1;
     [[resultView animator] setAlphaValue:1.0];
     
     } completionHandler:^{
     
     [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
     context.duration = 1;
     [[resultView animator] setAlphaValue:0.0];
     } completionHandler:^{
     [resultView removeFromSuperview];
     }];
     }];
     */
}

#pragma mark -----------------   Net   ----------------
- (void)setupClient
{
    if(!_connected){
        if(self.serviceBrowser == nil){
            self.serviceBrowser = [[NSNetServiceBrowser alloc] init];
            [self.serviceBrowser setDelegate:self];
            [self.serviceBrowser searchForServicesOfType:@"_dyci._tcp." inDomain:@"local."];
        }else{
            if(self.serverService) [self.serverService stop];
            //            [self.serviceBrowser stop];
            [self.serviceBrowser searchForServicesOfType:@"_dyci._tcp." inDomain:@"local."];
        }
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender didNotSearch:(NSDictionary *)errorInfo
{
	NSLog(@"DidNotSearch: %@", errorInfo);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
           didFindService:(NSNetService *)netService
               moreComing:(BOOL)moreServicesComing
{
	NSLog(@"DidFindService: %@", [netService name]);
	// Connect to the first service we find
    NSLog(@"Resolving...");
    if(self.serverService == nil){
        [netService setDelegate:self];
        [netService resolveWithTimeout:5.0f];
        self.serverService = netService;
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)sender
         didRemoveService:(NSNetService *)netService
               moreComing:(BOOL)moreServicesComing
{
	NSLog(@"DidRemoveService: %@", [netService name]);
    if(self.serverService == netService){
        self.serverService = nil;
        if(self.asyncSocket){
            self.asyncSocket.delegate = nil;
            [self.asyncSocket disconnect];
            self.asyncSocket = nil;
        }
    }
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict
{
	NSLog(@"DidNotResolve : %@",errorDict);
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender
{
	NSLog(@"DidResolve: %@", [sender addresses]);
    if(self.serverAddresses == nil){
        self.serverAddresses = [[sender addresses] mutableCopy];
        if (self.asyncSocket == nil){
            self.asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
            [self connectToNextAddress];
        }
    }
}

- (void)connectToNextAddress
{
	BOOL done = NO;
	while (!done && ([self.serverAddresses count] > 0)){
		NSData *addr;
		// Note: The serverAddresses array probably contains both IPv4 and IPv6 addresses.
		//
		// If your server is also using GCDAsyncSocket then you don't have to worry about it,
		// as the socket automatically handles both protocols for you transparently.
        // Iterate forwards
		if (YES){
			addr = [self.serverAddresses objectAtIndex:0];
			[self.serverAddresses removeObjectAtIndex:0];
		}
        // Iterate backwards
		else{
			addr = [self.serverAddresses lastObject];
			[self.serverAddresses removeLastObject];
		}
		NSLog(@"Attempting connection to %@", addr);
		NSError *err = nil;
		if ([self.asyncSocket connectToAddress:addr error:&err]){
			done = YES;
		}
		else{
			NSLog(@"Unable to connect: %@", err);
		}
	}
	if (!done){
		NSLog(@"Unable to connect to any resolved address");
	}
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port
{
	NSLog(@"Socket:DidConnectToHost: %@ Port: %hu", host, port);
	_connected = YES;
    if(_askForSendData){
        _askForSendData = NO;
        [self sendDylib];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
	NSLog(@"SocketDidDisconnect:WithError: %@", err);
    self.asyncSocket.delegate = nil;
    [self.asyncSocket disconnect];
    self.asyncSocket = nil;
    self.serverService.delegate = nil;
    self.serverService = nil;
    self.serverAddresses = nil;
    _connected = NO;
}

/**
 * Called when a socket has completed writing the requested data. Not called if there is an error.
 **/
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag
{
    if(tag > 0){
        NSLog(@"############  3. Send dylib to device Done !  ############");
        
    }
}

/**
 * Called when a socket has written some data, but has not yet completed the entire write.
 * It may be used to for things such as updating progress bars.
 **/
- (void)socket:(GCDAsyncSocket *)sock didWritePartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    
}

- (void)sendDylib
{
    if(_connected){
        //由程序生成的结果是   ~/.dyci 目录下的 .dylib文件 或 resource文件
        NSString * filePath = [self dylibFilePath];
        NSError * error = nil;
        NSData * data = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
        unsigned int dylibSize = (unsigned int)data.length;
        if(data.length > 0){
            NSLog(@"############  2. Begin send dylib to device...  ############");
            char * ptr = (char *)&(dylibSize);
            [self.asyncSocket writeData:[NSData dataWithBytes:ptr length:4] withTimeout:-1 tag:0];
            [self.asyncSocket writeData:[@"<EOF>" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:0];
            [self.asyncSocket writeData:data withTimeout:-1 tag:1];
            [self.asyncSocket writeData:[@"<EOF>" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 tag:1];
        }else{
            NSLog(@"read dylib ERROR");
        }
    }else{
        _askForSendData = YES;
        [self setupClient];
    }
}

#pragma mark -----------------   Util   ----------------


- (NSString *)dylibFilePath
{
    NSFileManager * fileManager = [NSFileManager defaultManager];
    NSString * dyciPath = [NSString stringWithFormat:@"%@/.dyci",NSHomeDirectory()];
    NSError * error = nil;
    NSArray * filenames = [fileManager contentsOfDirectoryAtPath:dyciPath error:&error];
    if(error){
        NSLog(@"%@",error);
        return nil;
    }
    NSString * dylibFilename = nil;
    for (NSString * filename in filenames) {
        if([filename rangeOfString:@".dylib"].length != 0){
            dylibFilename = filename;
            break;
        }
    }
    if(dylibFilename == nil){
        NSLog(@"not found dylib");
        return nil;
    }
    NSString * filePath = [NSString stringWithFormat:@"%@/%@",dyciPath,dylibFilename];
    return filePath;
}

#pragma mark - Dealloc

- (void)dealloc {
    self.asyncSocket.delegate = nil;
    [self.asyncSocket disconnect];
    self.asyncSocket = nil;
    self.serverService.delegate = nil;
    self.serverService = nil;
    self.serverAddresses = nil;
    self.serviceBrowser .delegate = nil;
    self.serviceBrowser = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

@end







