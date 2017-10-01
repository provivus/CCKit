//
//  KeyChain.h
//  Claims
//
//  Created by Johan Sellström on 2017-08-20.
//  Copyright © 2017 ethers.io. All rights reserved.
//

#ifndef KeyChain_h
#define KeyChain_h

@class Address;

NSString *getNickname(NSString *label);
NSString* getKeychainValue(NSString *keychainKey, Address *address);
BOOL addKeychainVaue(NSString *keychainKey, Address *address, NSString *nickname, NSString *value);
BOOL removeKeychainValue(NSString *keychainKey, Address *address);
NSDictionary<Address*, NSString*> *getKeychainNicknames(NSString *keychainKey);
void resetKeychain(NSString *keychainKey);


#endif /* KeyChain_h */


