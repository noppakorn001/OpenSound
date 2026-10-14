#import "WFTransport.h"
#include <sys/stat.h>
#include <unistd.h>
#include <cstdlib>
#include <cstdio>
@interface WFTransport (DiagnosticTest)
- (void)log:(NSString *)kind payload:(const wf::Bytes&)bytes;
@end
static void require(bool passed) { if(!passed) { fprintf(stderr,"Diagnostic log regression failed\n"); exit(1); } }
int main(){ @autoreleasepool {
    char pattern[]="/tmp/opensound-log-test.XXXXXX";
    const char *directory=mkdtemp(pattern); require(directory);
    NSString *root=@(directory), *file=[root stringByAppendingPathComponent:@"private.jsonl"];
    setenv("WF_PROTOCOL_LOG",file.fileSystemRepresentation,1);
    WFTransport *transport=[WFTransport new];
    struct stat info{}; require(lstat(file.fileSystemRepresentation,&info)==0 && (info.st_mode&0777)==0600);
    wf::Bytes bytes(4096,0xaa);
    for(unsigned i=0;i<1100;++i) [transport log:@"test" payload:bytes];
    require(stat(file.fileSystemRepresentation,&info)==0 && info.st_size>0 && info.st_size<=8*1024*1024);
    off_t original=info.st_size;
    WFTransport *existing=[WFTransport new]; [existing log:@"test" payload:wf::Bytes{1}];
    require(stat(file.fileSystemRepresentation,&info)==0 && info.st_size==original);
    NSString *target=[root stringByAppendingPathComponent:@"target.txt"], *link=[root stringByAppendingPathComponent:@"link.jsonl"];
    [@"unchanged" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil];
    require(symlink(target.fileSystemRepresentation,link.fileSystemRepresentation)==0);
    setenv("WF_PROTOCOL_LOG",link.fileSystemRepresentation,1);
    WFTransport *linked=[WFTransport new]; [linked log:@"test" payload:wf::Bytes{1}];
    require([[NSString stringWithContentsOfFile:target encoding:NSUTF8StringEncoding error:nil] isEqual:@"unchanged"]);
    unsetenv("WF_PROTOCOL_LOG");
    printf("Diagnostic log privacy, size, overwrite and symlink tests passed\n");
    [NSFileManager.defaultManager removeItemAtPath:root error:nil];
}}
