#import <XCTest/XCTest.h>
#import <zip.h> // Required for libzip
#import "idFileSystem.h"
#import "idFile.h"
#import "UDWorkspaceManager.h"

@interface idFileSystemTests : XCTestCase
@property (nonatomic, strong) NSString *rootDir;
@property (nonatomic, strong) NSString *gameDir;
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) idFileSystem *fileSystem;
@property (nonatomic, copy) NSString *testFilePath;
@end

@implementation idFileSystemTests

// -----------------------------------------------------------------------------
// Helper: Dynamically generate a valid ZIP archive in memory
// -----------------------------------------------------------------------------
- (NSData *)makeZIPData {
    zip_source_t *src = zip_source_buffer_create(NULL, 0, 0, NULL);
    if (!src) {
        return nil;
    }
    zip_t *za = zip_open_from_source(src, ZIP_TRUNCATE, NULL);
    if (!za) {
        zip_source_free(src);
        return nil;
    }

    const char *payload1 = "hello zip";
    zip_source_t *s1 = zip_source_buffer(za, payload1, strlen(payload1), 0);
    if (zip_file_add(za, "maps/q3dm1.bsp", s1, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 0, ZIP_CM_DEFLATE, 0);

    const char *payload2 = "script data";
    zip_source_t *s2 = zip_source_buffer(za, payload2, strlen(payload2), 0);
    if (zip_file_add(za, "scripts/base.shader", s2, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 1, ZIP_CM_STORE, 0);

    zip_source_keep(src);
    if (zip_close(za) != 0) {
        zip_source_free(src);
        return nil;
    }

    zip_source_open(src);
    zip_source_seek(src, 0, SEEK_END);
    zip_int64_t size = zip_source_tell(src);
    zip_source_seek(src, 0, SEEK_SET);
    if (size <= 0) {
        zip_source_free(src);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)size];
    zip_source_read(src, data.mutableBytes, (zip_uint64_t)size);
    zip_source_close(src);
    zip_source_free(src);
    
    return data;
}

// -----------------------------------------------------------------------------
// Setup & Teardown
// -----------------------------------------------------------------------------
- (void)setUp {
    [super setUp];
    self.rootDir = NSTemporaryDirectory();
    self.gameDir = @"base";
    
    NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
                          self.rootDir, @"fs_basepath",
                          self.rootDir, @"fs_savepath",
                          self.rootDir, @"fs_cdpath",
                          self.gameDir, @"fs_game",
                          @"1", @"fs_debug",
                          @"0", @"fs_restrict",
                          @"0", @"fs_copyfiles",
                          @"1", @"fs_caseSensitiveOS",
                          nil];
    
    NSString *fullGameDirPath = [self.rootDir stringByAppendingPathComponent:self.gameDir];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:fullGameDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    
    // Write the dynamic .pk4 file BEFORE booting subsystems so the FileSystem mounts it
    NSData *pakData = [self makeZIPData];
    NSString *pakPath = [fullGameDirPath stringByAppendingPathComponent:@"test_archive.pk4"];
    [pakData writeToFile:pakPath atomically:YES];
    
    self.workspace = [[UDWorkspaceManager sharedManager] openWorkspace:self.rootDir withDictionary:dict];
    [self.workspace startup];
    self.fileSystem = self.workspace.fileSystem;

    // Use a temporary path for isolated testing
    self.testFilePath = [fullGameDirPath stringByAppendingPathComponent:@"test_decl_file.decl"];
}

- (void)tearDown {
    // Clean up the disk after every test
    [[NSFileManager defaultManager] removeItemAtPath:self.testFilePath error:nil];
    
    // Clean up the pak and scripts directory created during tests
    NSString *fullGameDirPath = [self.rootDir stringByAppendingPathComponent:self.gameDir];
    [[NSFileManager defaultManager] removeItemAtPath:[fullGameDirPath stringByAppendingPathComponent:@"test_archive.pak"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[fullGameDirPath stringByAppendingPathComponent:@"scripts"] error:nil];
    
    self.workspace = nil;
    self.fileSystem = nil;
    [super tearDown];
}

// -----------------------------------------------------------------------------
// Existing Tests
// -----------------------------------------------------------------------------
- (void)testFileWriteAndRead {
    const char *testString = "material textures/test { map _default }";
    int length = (int)strlen(testString);
    NSError *error = nil;
    
    // 1. Test Writing
    idFile *writeFile = [self.fileSystem openFileWrite:self.testFilePath basePath:@"fs_basepath" error:&error];
    XCTAssertNotNil(writeFile, @"FileSystem should successfully open a file for writing");
    XCTAssertNil(error);
    
    int bytesWritten = [writeFile write:testString length:length error:&error];
    XCTAssertEqual(bytesWritten, length);
    XCTAssertNil(error);
    BOOL closed = [self.fileSystem closeFile:writeFile error:&error];
    XCTAssertTrue(closed);
    XCTAssertNil(error);
    writeFile = nil;
    
    // 2. Test Reading
    idFile *readFile = [self.fileSystem openFileRead:self.testFilePath allowCopyFiles:YES gamedir:nil error:&error];
    XCTAssertNotNil(readFile, @"FileSystem should successfully open the existing file");
    XCTAssertEqual([readFile length], length, @"File length should match the written bytes");
    XCTAssertNil(error);
    
    // 3. Verify Buffer Contents
    NSMutableData *readBuffer = [NSMutableData dataWithLength:[readFile length] + 1]; // +1 for null terminator
    int bytesRead = [readFile read:readBuffer.mutableBytes length:[readFile length] error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(bytesRead, bytesWritten, @"Bytes read and written should be the same");
    BOOL closedAgain = [self.fileSystem closeFile:readFile error:&error];
    XCTAssertNil(error);
    XCTAssertTrue(closedAgain);
    
    NSString *result = [NSString stringWithUTF8String:readBuffer.bytes];
    XCTAssertEqualObjects(result, @"material textures/test { map _default }", @"Read text should perfectly match written text");
}

- (void)testFileNotFound {
    NSError *error = nil;
    idFile *readFile = [self.fileSystem openFileRead:@"/path/to/absolute/garbage.decl" allowCopyFiles:YES gamedir:nil error:&error];
    XCTAssertNil(readFile, @"FileSystem should gracefully return NULL for missing files");
    // Ensure that your file system explicitly sets the error pointer when returning nil
    XCTAssertNil(error, @"FileSystem should NOT return an NSError when file is not found");
}

// -----------------------------------------------------------------------------
// Pak Tests
// -----------------------------------------------------------------------------
- (void)testTransparentPakRead {
    NSError *error = nil;
    
    // 1. Ask for the file by its internal path inside the ZIP
    idFile *readFile = [self.fileSystem openFileRead:@"scripts/base.shader" allowCopyFiles:NO gamedir:nil error:&error];
    XCTAssertNotNil(readFile, @"FileSystem should successfully locate and open the file from inside the mounted .pak");
    XCTAssertNil(error);
    
    // 2. Verify length and read
    int length = [readFile length];
    XCTAssertTrue(length > 0, @"File inside pak should have a valid length");
    
    NSMutableData *readBuffer = [NSMutableData dataWithLength:length + 1];
    int bytesRead = [readFile read:readBuffer.mutableBytes length:length error:&error];
    XCTAssertNil(error);
    XCTAssertEqual(bytesRead, length);
    
    [self.fileSystem closeFile:readFile error:nil];
    
    // 3. Verify contents match the libzip payload
    NSString *result = [NSString stringWithUTF8String:readBuffer.bytes];
    XCTAssertEqualObjects(result, @"script data", @"The decompressed text must perfectly match the payload in makeZIPData");
}

- (void)testPakShadowing {
    // In idTech, a loose file on the hard drive overrides a file of the same name inside a .pak.
    NSError *error = nil;
    
    // 1. Create the loose "scripts" directory and write a shadow file directly to disk
    NSString *fullGameDirPath = [self.rootDir stringByAppendingPathComponent:self.gameDir];
    NSString *shadowDir = [fullGameDirPath stringByAppendingPathComponent:@"scripts"];
    [[NSFileManager defaultManager] createDirectoryAtPath:shadowDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *shadowFilePath = [shadowDir stringByAppendingPathComponent:@"base.shader"];
    NSString *shadowText = @"loose file override data";
    [shadowText writeToFile:shadowFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    // 2. In most idTech ports, openFileRead naturally checks the local OS directory before the pak list.
    // (If your engine caches search paths aggressively, you might need to call a re-init method here).
    idFile *readFile = [self.fileSystem openFileRead:@"scripts/base.shader" allowCopyFiles:NO gamedir:nil error:&error];
    XCTAssertNotNil(readFile, @"FileSystem should successfully open the shadow file");
    XCTAssertNil(error);
    
    // 3. Verify the engine read the loose file and NOT the "script data" from the .pak
    int length = [readFile length];
    NSMutableData *readBuffer = [NSMutableData dataWithLength:length + 1];
    [readFile read:readBuffer.mutableBytes length:length error:nil];
    [self.fileSystem closeFile:readFile error:nil];
    
    NSString *result = [NSString stringWithUTF8String:readBuffer.bytes];
    XCTAssertEqualObjects(result, shadowText, @"FileSystem must prioritize loose files on disk over archived .pak files");
}

@end
