/**
 * Copyright 2016 Boundless http://boundlessgeo.com
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License
 */
#import "SCConfig.h"
#import "SCConfigService.h"
#import "SCDataService.h"
#import "SCFileUtils.h"
#import "SCFormConfig.h"
#import "SCStoreConfig.h"
#import "SpatialConnect.h"

@interface SCConfigService ()
- (void)setupSignals;
@end

@implementation SCConfigService

@synthesize remoteUri;

- (id)init {
  self = [super init];
  if (self) {
    configPaths = [NSMutableArray new];
  }
  return self;
}

- (void)setupSignals {
}

- (void)start {
  [super start];
  [self sweepDataDirectory];
  [self loadConfigs];
}

- (void)stop {
  [super stop];
}

- (void)addConfigFilepath:(NSString *)fp {
  [configPaths addObject:fp];
}

- (void)addConfigFilepaths:(NSArray *)fps {
  [configPaths addObjectsFromArray:fps];
}

- (void)sweepDataDirectory {
  NSString *path = [NSSearchPathForDirectoriesInDomains(
      NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
  NSArray *dirs =
      [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path
                                                          error:NULL];

  [dirs enumerateObjectsUsingBlock:^(NSString *filename, NSUInteger idx,
                                     BOOL *stop) {
    if ([filename.pathExtension.lowercaseString isEqualToString:@"scfg"]) {
      [configPaths
          addObject:[NSString stringWithFormat:@"%@/%@", path, filename]];
    }
  }];
}

- (void)loadConfigs {
  [configPaths enumerateObjectsUsingBlock:^(NSString *fp, NSUInteger idx,
                                            BOOL *_Nonnull stop) {
    NSError *error;
    NSMutableDictionary *cfg = [NSMutableDictionary
        dictionaryWithDictionary:[SCFileUtils jsonFileToDict:fp
                                                       error:&error]];
    if (error) {
      NSLog(@"%@", error.description);
    }
    NSString *uri;
    if ((uri = [cfg objectForKey:@"remote"])) {
      [cfg removeObjectForKey:@"remote"];
      self.remoteUri = uri;
      SpatialConnect *sc = [SpatialConnect sharedInstance];
      SCAuthService *as = sc.authService;
      //You have the url to the server. Wait for someone to properly
      //authenticate before fetching the config
      [[as loginStatus] subscribeNext:^(NSNumber *n) {
        SCAuthStatus s = [n integerValue];
        if (s == SCAUTH_AUTHENTICATED) {
          [self registerAndFetchConfig];
        }
      }];

    }
    if (cfg.count > 0) {
      SCConfig *s = [[SCConfig alloc] initWithDictionary:cfg];
      [self loadConfig:s];
    }
  }];
}

- (void)registerAndFetchConfig {
  SCNetworkService *ns = [[SpatialConnect sharedInstance] networkService];
  SCAuthService *as = [[SpatialConnect sharedInstance] authService];
  NSURL *regUrl =
  [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/devices/register?token=%@",self.remoteUri,[as xAccessToken]]];

  NSString *ident =
  [[NSUserDefaults standardUserDefaults] stringForKey:@"UNIQUE_ID"];
  if (!ident) {
    ident = [[UIDevice currentDevice].identifierForVendor UUIDString];
    [[NSUserDefaults standardUserDefaults] setObject:ident
                                              forKey:@"UNIQUE_ID"];
  }
  NSDictionary *regDict = @{
                            @"identifier" : ident,
                            @"device_info" : @{
                                @"os" : @"ios"
                                }
                            };
  [ns postDictRequestBLOCKING:regUrl body:regDict];
  NSURL *cfgUrl = [NSURL URLWithString: [NSString stringWithFormat:@"%@/api/config?token=%@",self.remoteUri,as.xAccessToken]];
  NSDictionary *dict = [ns getRequestURLAsDictBLOCKING:cfgUrl];
  [self loadConfig:[[SCConfig alloc] initWithDictionary:dict]];
}

- (void)loadConfig:(SCConfig *)c {
  SpatialConnect *sc = [SpatialConnect sharedInstance];
  [c.forms enumerateObjectsUsingBlock:^(SCFormConfig *f, NSUInteger idx,
                                        BOOL *stop) {
    [sc.dataService registerFormByConfig:f];
  }];
  [c.dataServiceStores enumerateObjectsUsingBlock:^(
                           SCStoreConfig *c, NSUInteger idx, BOOL *stop) {
    [sc.dataService registerStoreByConfig:c];
  }];
}

@end
