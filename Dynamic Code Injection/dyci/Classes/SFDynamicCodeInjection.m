//
//  SFDynamicCodeInjection
//  Dynamic Code Injection
//
//  Created by Paul Taykalo on 10/7/12.
//  Copyright (c) 2012 Stanfy LLC. All rights reserved.
//
#import <objc/runtime.h>
#import "SFDynamicCodeInjection.h"
#include <dlfcn.h>
#import "NSSet+ClassesList.h"
#import "NSObject+DyCInjection.h"
#import "SFInjectionsNotificationsCenter.h"
#import "GCDAsyncSocket.h"

@interface SFDynamicCodeInjection () <NSNetServiceDelegate>

@property(nonatomic, strong) GCDAsyncSocket * asyncSocket;
@property(nonatomic, strong) NSNetService * netService;
@property(nonatomic, strong) NSMutableData * receivedData;
@property(nonatomic, strong) GCDAsyncSocket * clientSocket;
@property(nonatomic, assign) unsigned int dylibSize;
@end

@implementation SFDynamicCodeInjection {
    BOOL _enabled;
}

+ (void)load {
    [self enable];
    NSLog(@"============================================");
    NSLog(@"DYCI : Dynamic Code Injection was started...");
    NSLog(@"To disable it, paste next line in your application:didFinishLaunching: method : \n\n"
          "[NSClassFromString(@\"SFDynamicCodeInjection\") performSelector:@selector(disable)];\n\n");
    NSLog(@"============================================");
}

+ (SFDynamicCodeInjection *)sharedInstance {
    static SFDynamicCodeInjection * _instance = nil;
    @synchronized (self) {
        if (_instance == nil) {
            _instance = [[self alloc] init];
        }
    }
    return _instance;
}

+ (void)enable {
    if (![self sharedInstance]->_enabled) {
        [self sharedInstance]->_enabled = YES;
        // Swizzling init and dealloc methods
        [NSObject allowInjectionSubscriptionOnInitMethod];
        // create Documents/dyci directory
        [self createDyciDirectory];
        // setup network
        [[self sharedInstance] startServer];
    }
}

+ (void)disable {
    if ([self sharedInstance]->_enabled) {
        [self sharedInstance]->_enabled = NO;
        // Re-swizzling init and dealloc methods
        [NSObject allowInjectionSubscriptionOnInitMethod];
        // remove dyci dylib directory
        [self removeDyciDirectory];
        // stop network
        [[self sharedInstance] stopServer];
        NSLog(@"============================================");
        NSLog(@"DYCI : Dynamic Code Injection was stopped   ");
        NSLog(@"============================================");
    }
}


#pragma mark - Injections

/*
 Injecting in all classes, that were found in specified set
 */
- (void)performInjectionWithClassesInSet:(NSMutableSet *)classesSet {
    for (NSValue * classWrapper in classesSet) {
        Class clz;
        [classWrapper getValue:&clz];
        NSString * className = NSStringFromClass(clz);
        if ([className hasPrefix:@"__"] && [className hasSuffix:@"__"]) {
            // Skip some O_o classes
        } else {
            [self performInjectionWithClass:clz];
            NSLog(@"Class was successfully injected");
        }
    }
}

- (void)performInjectionWithClass:(Class)injectedClass {
    // Parsing it's method
    
    // This is really fun
    // Even if we load two instances of classes with the same name :)
    // NSClassFromString Will return FIRST(Original) Instance. And this is cool!
    NSString * className = [NSString stringWithFormat:@"%s", class_getName(injectedClass)];
    Class originalClass = NSClassFromString(className);
    
    // Replacing instance methods
    [self replaceMethodsOfClass:originalClass withMethodsOfClass:injectedClass];
    
    // Additionally we need to update Class methods (not instance methods) implementations
    [self replaceMethodsOfClass:object_getClass(originalClass) withMethodsOfClass:object_getClass(injectedClass)];
    
    // Notifying about new classes logic
    NSLog(@"Class (%@) and their subclasses instances would be notified with", NSStringFromClass(originalClass));
    NSLog(@" - (void)updateOnClassInjection ");
    [[SFInjectionsNotificationsCenter sharedInstance] notifyOnClassInjection:originalClass];
}

- (void)replaceMethodsOfClass:(Class)originalClass withMethodsOfClass:(Class)injectedClass {
    if (originalClass != injectedClass) {
        NSLog(@"Injecting %@ class : %@", class_isMetaClass(injectedClass) ? @"meta" : @"", NSStringFromClass(injectedClass));
        // Original class methods
        int i = 0;
        unsigned int mc = 0;
        Method * injectedMethodsList = class_copyMethodList(injectedClass, &mc);
        for (i = 0; i < mc; i++) {
            Method m = injectedMethodsList[i];
            SEL selector = method_getName(m);
            const char * types = method_getTypeEncoding(m);
            IMP injectedImplementation = method_getImplementation(m);
            //  Replacing old implementation with new one
            class_replaceMethod(originalClass, selector, injectedImplementation, types);
        }
    }
}

#pragma mark - SFLibWatcherDelegate

- (void)newFileWasFoundAtPath:(NSString *)filePath {
    // If its library
    NSString * dciDynamicLibraryPath = filePath;
    if (![[dciDynamicLibraryPath pathExtension] isEqualToString:@"dylib"]) {
        dciDynamicLibraryPath = [dciDynamicLibraryPath stringByDeletingPathExtension];
    }
    if ([[dciDynamicLibraryPath pathExtension] isEqualToString:@"dylib"]) {
        NSMutableSet * classesSet = [NSMutableSet currentClassesSet];
        void * libHandle = dlopen([dciDynamicLibraryPath cStringUsingEncoding:NSUTF8StringEncoding],
                                  RTLD_NOW | RTLD_GLOBAL);
        char * err = dlerror();
        if (libHandle) {
            NSLog(@"###   DYCI was successfully loaded");
            NSLog(@"###   Searching classes to inject");
            // Retrieving difference between old classes list and
            // current classes list
            NSMutableSet * currentClassesSet = [NSMutableSet currentClassesSet];
            [currentClassesSet minusSet:classesSet];
            if(currentClassesSet.count == 0) {
                NSLog(@"###   No new Class found ~");
            }else{
                [self performInjectionWithClassesInSet:currentClassesSet];
            }
        } else {
            NSLog(@"###   Couldn't load file Error : %s", err);
        }
        NSLog(@"===========================================================");
        dlclose(libHandle);
    }
}

#pragma mark -----------------   Network   ----------------

- (void)startServer
{
    if(self.asyncSocket == nil){
        // Create our socket.
        // We tell it to invoke our delegate methods on the main thread.
        self.asyncSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
        // Create an array to hold accepted incoming connections.
        // Now we tell the socket to accept incoming connections.
        // We don't care what port it listens on, so we pass zero for the port number.
        // This allows the operating system to automatically assign us an available port.
        NSError *err = nil;
        if ([self.asyncSocket acceptOnPort:0 error:&err]){
            // So what port did the OS give us?
            UInt16 port = [self.asyncSocket localPort];
            // Create and publish the bonjour service.
            // Obviously you will be using your own custom service type.
            self.netService = [[NSNetService alloc] initWithDomain:@"local."
                                                              type:@"_dyci._tcp."
                                                              name:@""
                                                              port:port];
            [self.netService setDelegate:self];
            [self.netService publish];
        }
        else{
            NSLog(@"###   Error in acceptOnPort:error: -> %@", err);
        }
    }
}

- (void)stopServer
{
    self.clientSocket.delegate = nil;
    [self.clientSocket disconnect];
    self.clientSocket = nil;
    self.asyncSocket.delegate = nil;
    [self.asyncSocket disconnect];
    self.asyncSocket = nil;
}

- (void)netServiceDidPublish:(NSNetService *)ns
{
	NSLog(@"###   Bonjour Service Published: domain(%@) type(%@) name(%@) port(%i)",
          [ns domain], [ns type], [ns name], (int)[ns port]);
}

- (void)netService:(NSNetService *)ns didNotPublish:(NSDictionary *)errorDict
{
	// Override me to do something here...
	//
	// Note: This method in invoked on our bonjour thread.
	NSLog(@"###   Failed to Publish Service: domain(%@) type(%@) name(%@) - %@",
          [ns domain], [ns type], [ns name], errorDict);
}


- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket
{
	NSLog(@"###   Accepted new socket from %@:%hu", [newSocket connectedHost], [newSocket connectedPort]);
	// The newSocket automatically inherits its delegate & delegateQueue from its parent.
    if(self.clientSocket == nil){
        self.clientSocket = newSocket;
        self.clientSocket.delegate = self;
        [self readyForData];
    }
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err
{
    if(sock == self.clientSocket){
        self.clientSocket .delegate = nil;
        self.clientSocket = nil;
    }
}

/**
 * Called when a socket has completed reading the requested data into memory.
 * Not called if there is an error.
 **/
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    if(tag == 0){
        //接收完毕  filesize
        long length = self.receivedData.length;
        if(length == (4 + @"<EOF>".length)){
            NSRange range;
            range.location = 0;
            range.length = 4;
            NSData * sizeData = [self.receivedData subdataWithRange:range];
            int ptr = 0;
            [sizeData getBytes:&ptr length:4];
            self.dylibSize = ptr;
            NSLog(@"===========================================================");
            NSLog(@"###   Received dylib size : %d bytes",self.dylibSize);
            [self readyForDylibData];
        }
    }else{
        long length = self.receivedData.length;
        if(length > (@"<EOF>".length)){
            NSLog(@"###   Received dylib Done!");
            NSRange range;
            range.location = 0;
            range.length = length - @"<EOF>".length;
            NSData * data = [self.receivedData subdataWithRange:range];
            //remove old dyci dylib
            [SFDynamicCodeInjection clearExsitedDylib];
            int random = arc4random() % 10000;
            NSError * error = nil;
            // path name should be random, if not , the dylib will not be loaded(cache will be used)
            NSString * dyciPath = [[SFDynamicCodeInjection dyciDirectoryPath] stringByAppendingPathComponent:[NSString stringWithFormat:@"%d.dylib",random]];
            NSFileManager * fileManager = [NSFileManager defaultManager];
            if(![fileManager fileExistsAtPath:dyciPath isDirectory:NO]){
                [fileManager createFileAtPath:dyciPath contents:nil attributes:0];
            }
            if(![data writeToFile:dyciPath options:0 error:&error]){
                NSLog(@"###   save to $(random).dyci ERROR : %@",error);
            }else{
                [self newFileWasFoundAtPath:dyciPath];
            }
        }
        [self readyForData];
    }
}

/**
 * Called when a socket has read in data, but has not yet completed the read.
 * This would occur if using readToData: or readToLength: methods.
 * It may be used to for things such as updating progress bars.
 **/
- (void)socket:(GCDAsyncSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag
{
    if(tag != 0){
        int receivedLength = self.receivedData.length;
        NSLog(@"      Received dylib: %.2f",receivedLength/(float)self.dylibSize);
    }
}
//read dylib size first
- (void)readyForData
{
    self.receivedData = nil;
    self.receivedData = [NSMutableData data];
    [self.clientSocket readDataToData:[@"<EOF>" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 buffer:self.receivedData bufferOffset:0 tag:0];
}

//read real data
- (void)readyForDylibData
{
    self.receivedData = nil;
    self.receivedData = [NSMutableData data];
    [self.clientSocket readDataToData:[@"<EOF>" dataUsingEncoding:NSUTF8StringEncoding] withTimeout:-1 buffer:self.receivedData bufferOffset:0 tag:1];
}

- (void)dealloc
{
    [self stopServer];
    self.netService .delegate = nil;
    [self.netService stop];
    self.netService = nil;
}

#pragma mark -----------------   util   ----------------
+ (NSString *)dyciDirectoryPath{
    return [NSString stringWithFormat:@"%@/Documents/dyci",NSHomeDirectory()];
}

+ (void)createDyciDirectory
{
    NSFileManager * defaultManager = [NSFileManager defaultManager];
    NSError * error = nil;
    if(![defaultManager createDirectoryAtPath:[self dyciDirectoryPath] withIntermediateDirectories:NO attributes:0 error:&error]){
        NSLog(@"###   create Dyci Directory ERROR : %@",error);
    }
}

+ (void)removeDyciDirectory
{
    NSFileManager * defaultManager = [NSFileManager defaultManager];
    [self clearExsitedDylib];
    NSError * error = nil;
    if(![defaultManager removeItemAtPath:[self dyciDirectoryPath] error:&error]){
        NSLog(@"###   remove Dyci Directory ERROR : %@",error);
    }
}

+ (void)clearExsitedDylib
{
    //由程序生成的结果是   ~/.dyci 目录下的 .dylib文件 或 resource文件
    NSFileManager * fileManager = [NSFileManager defaultManager];
    NSError * error = nil;
    NSArray * filenames = [fileManager contentsOfDirectoryAtPath:[SFDynamicCodeInjection dyciDirectoryPath] error:&error];
    if(error){
        NSLog(@"###   %@",error);
        return;
    }
    for (NSString * filename in filenames) {
        if([filename rangeOfString:@".dylib"].length != 0){
            [fileManager removeItemAtPath:filename error:&error];
        }
    }
}

@end






