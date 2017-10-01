//
//  Client.swift
//  Claims
//
//  Created by Johan Sellström on 2017-08-12.
//  Copyright © 2017 ethers.io. All rights reserved.
//

import EtherKit
import PromiseKit
import Alamofire
import PMKAlamofire
import IpfsKit
import IpcKit
import SwiftMultihash
import SwiftHex
import SwiftBase58
import SwiftBaseX
import SwiftKeccak
import ABIKit

class CCKClient {
    
    let accountManager:AccountManager
    let ipfsClient:IpfsClient
    let ipcClient:IpcClient
    let networkId: NetworkId
    
    init?(ipfsHost: String, networkId: NetworkId, accountManager: AccountManager) {
        self.accountManager = accountManager
        self.ipfsClient = IpfsClient(ipfsHost:"ipfs.carechain.io" )!
        self.ipcClient = IpcClient()!
        self.networkId = networkId
    }
    
    public func waitForTransactionReceipt(netId: NetworkId, hash: Hash) -> Promise<TransactionReceipt>
    {
        if hash.isZeroHash() {
            return Promise(value: TransactionReceipt())
        }
        return Promise<TransactionReceipt> { fulfill, reject in
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { (timer) in
                Alamofire.request(networkInterface(netId)[0], method: .post,  parameters: [
                    "jsonrpc": "2.0" ,
                    "method": "eth_getTransactionReceipt",
                    "id": NSNumber(value: 42),
                    "params": [hash.hexString]
                    ], encoding: JSONEncoding.default )
                    .validate()
                    .responseJSON { response in
                        switch response.result {
                        case .success:
                            let jdata = queryPath(response.data! as NSObject,"json/json") as? NSDictionary
                            
                            let result = jdata?["result"]
                            
                            if result is NSNull {
                                print(".")
                                //reject(NSError.cancelledError())
                            } else if let transactionReceipt = TransactionReceipt(from: result as! [AnyHashable : Any]) {
                                if (transactionReceipt.blockNumber)>0 {
                                    print("waitForTransactionReceipt:",transactionReceipt)
                                    timer.invalidate()
                                    fulfill(transactionReceipt)
                                }
                            }
                        case .failure(let error):
                            reject(error)
                        }
                }
            })
        }
    }
    
    public func sendMetaTransaction(netId: NetworkId, address: Address, contractName: String, methodName: String, parameterValues: [String], contractAddress: Address?) -> Promise<Array<String>>
    {
        //print("sendMetaTransaction ",address, "parameterValues ", parameterValues)
        return Promise<Transaction> { fulfill, reject in
            if let contractData = readJson(fileName: "contracts/"+contractName) , let contractInterface = Contract(data: contractData) {
                
                let trans = Transaction(from: address )
                
                if contractAddress != nil { // transact with an already deployed contract
                    trans.toAddress = contractAddress
                    if let method = contractInterface.find(name: methodName) {
                        let str = method.encode(values: parameterValues)
                        //print("Encoded method call", str)
                        let sec = SecureData(hexString: str)
                        trans.data = (sec?.data())!
                    }
                } else { // deploy a contract
                    trans.toAddress = trans.fromAddress
                    let code = contractInterface.unlinkedBinary
                    let sec = SecureData(hexString: code)
                    trans.data = (sec?.data())!
                }
                fulfill(trans)
            } else {
                let error = NSError(domain: "XClaim", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deploy contract"])
                reject(error)
            }
            }.then { transaction in
                // print("sendMetaTransaction ",transaction)
                self.ipcClient.eth_sendTransaction(netId: netId, transaction: transaction)
            }.then { hash in
                self.waitForTransactionReceipt(netId:netId, hash: hash)
            }.then { transReceipt in
                
                
                if let logs = transReceipt.logs {
                    
                    let dictArray = logs  as! [Dictionary<String, Any>]
                    
                    //                   print("metaTransaction:", dictArray)
                    
                    
                    for obj in dictArray {
                        // The addresses we need are possibly encoded in data??
                        let encoded = obj["data"] as! String
                        
                        //                       print(encoded)
                        
                        let addressStrings = encoded.decodeABI()
                        return Promise(value: addressStrings)
                    }
                }
                return Promise(value: [])
        }
    }
    
    
    public func sendTransaction(netId: NetworkId, address: Address, contractName: String, methodName: String, parameterValues: [String], contractAddress: Address?) -> Promise<Array<String>>
    {
        return Promise<Transaction> { fulfill, reject in
            if let contractData = readJson(fileName: "contracts/"+contractName) , let contractInterface = Contract(data: contractData) {
                
                let trans = Transaction(from: address )
                if contractAddress != nil { // transact with an already deployed contract
                    trans.toAddress = contractAddress
                    if let method = contractInterface.find(name: methodName) {
                        let str = method.encode(values: parameterValues)
                        let sec = SecureData(hexString: str)
                        trans.data = (sec?.data())!
                    }
                } else { // deploy a contract
                    trans.toAddress = trans.fromAddress
                    let code = contractInterface.unlinkedBinary
                    let sec = SecureData(hexString: code)
                    trans.data = (sec?.data())!
                }
                trans.gasLimit = BigNumber(decimalString: "350000") // This should be pre-estimated and/or known beforehand
                fulfill(trans)
            } else {
                let error = NSError(domain: "XClaim", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deploy contract"])
                reject(error)
            }
            }.then {transaction in
                self.ipcClient.eth_sendRawTransaction(netId:netId, address:address, transaction:transaction)
            }.then { hash in
                self.waitForTransactionReceipt(netId:netId,hash: hash)
            }.then { transReceipt in
                if let logs = transReceipt.logs {
                    let dictArray = logs  as! [Dictionary<String, Any>]
                    for obj in dictArray {
                        // The addresses we need are possibly encoded in data??
                        let encoded = obj["data"] as! String
                        let addressStrings = encoded.decodeABI()
                        return Promise(value: addressStrings)
                    }
                } else {
                    print("sendTransaction:", transReceipt)
                }
                
                return Promise(value: ["-1","-1"])
        }
    }
    
    public func createIdentityTransaction(netId: NetworkId, address: Address, contractName: String, methodName: String, parameterValues: [String], contractAddress: Address?) -> Promise<Array<Address>>
    {
        return Promise<Transaction> { fulfill, reject in
            if let contractData = readJson(fileName: "contracts/"+contractName) , let contractInterface = Contract(data: contractData) {
                
                let trans = Transaction(from: address )
                
                if contractAddress != nil { // transact with an already deployed contract
                    trans.toAddress = contractAddress
                    if let method = contractInterface.find(name: methodName) {
                        let str = method.encode(values: parameterValues)
                        let sec = SecureData(hexString: str)
                        trans.data = (sec?.data())!
                    }
                } else { // deploy a contract
                    trans.toAddress = trans.fromAddress
                    let code = contractInterface.unlinkedBinary
                    let sec = SecureData(hexString: code)
                    trans.data = (sec?.data())!
                }
                trans.gasLimit = BigNumber(decimalString: "350000") // This should be pre-estimated and/or known beforehand
                fulfill(trans)
            } else {
                let error = NSError(domain: "XClaim", code: 1, userInfo: [NSLocalizedDescriptionKey: "Deploy contract"])
                reject(error)
            }
        }.then {transaction in
            self.ipcClient.eth_sendRawTransaction(netId:netId, address:address, transaction: transaction)
        }.then { hash in
            self.waitForTransactionReceipt(netId:netId,hash: hash)
        }.then { transReceipt in
            if let logs = transReceipt.logs {
                let dictArray = logs  as! [Dictionary<String, Any>]
                for obj in dictArray {
                    if let topics = obj["topics"] as? [String] {
                        let addressStrings = topics[1].decodeABI()
                        return Promise(value: [address, Address(string: addressStrings[0]) ])
                    }
                }
            }
            return Promise(value: [Address.zero()])
        }
        
        /*.catch(policy: .allErrors)  {error in
         print(" Caught error", error.localizedDescription)
         }*/
    }
    
    public func fundAddress(netId: NetworkId, address: Address) -> Promise<TransactionReceipt>
    {
        
        let endpoint = networkInterface(netId)[3].replacingOccurrences(of: "$ADDRESS", with: address.checksumAddress)
        
        let method = networkInterface(netId)[4]
        var httpMethod:HTTPMethod?
        
        switch method
        {
        case ".post":
            httpMethod = .post
            break
        case ".get":
            httpMethod = .post
            break
        default:
            httpMethod = .post
            break
        }
        
        print("endpoint", endpoint)
        
        return Promise<Hash> { fulfill, reject in
            Alamofire.request(endpoint , method: httpMethod!)
                .validate()
                .responseJSON { response in
                    switch response.result {
                    case .success:
                        if let jdata = queryPath(response.data! as NSObject,"json/json") as? NSDictionary
                        {
                            if let status = jdata["status"] as? String
                            {
                                if status == "OK" && jdata["tx"] != nil
                                {
                                    let hash = Hash(hexString: jdata["tx"] as! String)
                                    fulfill(hash!)
                                } else {
                                    //let err = NSError(domain: "XClaim", code: 1, userInfo: [NSLocalizedDescriptionKey:jdata["status"]! ])
                                    //reject(NSError.cancelledError())
                                    fulfill(Hash.zero())
                                }
                            }
                        }
                    case .failure(let error):
                        reject(error)
                    }
            }
            }.then { hash in
                self.waitForTransactionReceipt(netId:netId, hash: hash)
            }.catch(policy: .allErrors)  {error in
                print(" Caught error", error.localizedDescription)
        }
    }
    
    public func unlock(address: Address) -> Promise<Address>
    {
        return Promise<Address> { fulfill, reject in
            self.accountManager.unlockAccount(address, completion: { (unlockedAccount) in
                if unlockedAccount != nil {
                    fulfill((unlockedAccount?.address)!)
                } else {
                    let error = NSError(domain: "XClaim", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unlock account failed"])
                    reject(error)
                }
            })
        }
    }
    
    public func makeProfileObject(name:String, imgData: Data, sender: Address, identity: Address) -> Promise<Multihash>
    {
        let fileName = UUID().uuidString
        let dirURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = dirURL.appendingPathComponent(fileName).appendingPathExtension("png")
        
        do {
            try imgData.write(to: fileURL, options: .atomicWrite)
        } catch {
            print(error.localizedDescription)
        }
        
        return self.ipfsClient.putFile(fileURL: fileURL).then { imgMultiHash in
            return Promise<Data> { fulfill, reject in
                let dict = NSMutableDictionary(capacity: 10)
                
                //var dict = [String:String]()
                let identityMNID = identity.encodeMNID(chainID: "0x00")
                let publicKey = sender.publicKey!
                
                let imgObj = ["@type":"ImageObject",
                              "name":"avatar",
                              "contentURL": "/ipfs/" + b58String(imgMultiHash)]
                
                dict.addEntries(from: ["@context":"http://schema.org",
                                       "@type":"Person",
                                       "name": name,
                                       "address": identityMNID,
                                       "publicKey": publicKey,
                                       "network": "carechain",
                                       "image": imgObj])
                
                
                do {
                    let jsonData: Data = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions.prettyPrinted)
                    fulfill(jsonData)
                } catch {
                    print(error.localizedDescription)
                }
                }.then { object in
                    let jsonString = String(data: object, encoding: .utf8 )
                    
                    let fileName = UUID().uuidString
                    let dirURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    let fileURL = dirURL.appendingPathComponent(fileName).appendingPathExtension("json")
                    
                    do {
                        try jsonString?.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
                    } catch {
                        print(error.localizedDescription)
                    }
                    
                    return self.ipfsClient.putFile(fileURL: fileURL)
                    
                }.catch { error in
                    print(error.localizedDescription)
            }
            }.catch { error in
                print(error.localizedDescription)
        }
    }
    
    public func updateNonce(netId: NetworkId, address: Address) -> Promise<Int>
    {
        return self.ipcClient.eth_getTransactionCount(netId:netId, address: address, tag: .pending).then { nonce in
            self.transactionNonce = UInt(nonce)
            //self.addressNonces.setValue(UInt(nonce), forKey: address.checksumAddress)
            return Promise(value: nonce)
        }
    }
    
    public func forwardTo(netId: NetworkId, sender: Address, identity: Address, destination: Address, value: UInt32, registryDigest: String)  -> Promise<Array<String>>
    {
        var dataStr:String?
        let registrationIdentifier = "uPortProfileIPFS1220"
        let data = registrationIdentifier.data(using: .utf8)!
        let key = "0x"+data.map{ String(format:"%02x", $0) }.joined()
        
        if let contractData = readJson(fileName: "contracts/UportRegistry") , let contractInterface = Contract(data: contractData) {
            if let method = contractInterface.find(name: "set") {
                dataStr = method.encode(values: [key.lowercased(), identity.checksumAddress.lowercased(), registryDigest.lowercased()])?.lowercased()
            }
        }
        let valStr = String(value)
        
        // Debugging
        if let contractData = readJson(fileName: "contracts/MetaIdentityManager") , let contractInterface = Contract(data: contractData) {
            if let method = contractInterface.find(name: "forwardTo") {
                
                print("encode call to UportRegistry:set")
                print("key: ",key.lowercased())
                print("identity :", identity.checksumAddress.lowercased())
                print("registryValue: ", registryDigest.lowercased())
                print("encoded: ", dataStr!)
                
                print("encode call to MetaIdentityManager:forwardTo")
                print("sender: ",sender.checksumAddress.lowercased())
                print("identity :", identity.checksumAddress.lowercased())
                print("destination (registry): ", destination.checksumAddress.lowercased())
                print("value: ", valStr)
                print("data: ", dataStr!)
                
                let forwardTo = method.encode(values: [sender.checksumAddress, identity.checksumAddress, destination.checksumAddress, valStr, dataStr!])?.lowercased()
                print("encoded", forwardTo!)
            }
        }
        return self.sendTransaction(netId:netId, address:sender, contractName: "MetaIdentityManager",
                                    methodName: "forwardTo",
                                    parameterValues:  [sender.checksumAddress.lowercased(), identity.checksumAddress.lowercased(), destination.checksumAddress.lowercased(),valStr, dataStr!],
                                    contractAddress: Address(string: networkInterface(netId)[1]))
    }
    
    public func connectRegistry(netId: NetworkId, sender: Address, identity: Address, registryAddress: Address, objectHash: Multihash) -> Promise<Array<Address>>
    {
        print("\n\n\n=======================================")
        
        let profileHash = b58String(objectHash)
        do {
            
            let hex = try profileHash.decodeBase58().hexEncodedString()
            let profileHashStartIndex = hex.startIndex
            let startIndex = hex.index(profileHashStartIndex, offsetBy: 4)
            let registryDigest = "0x" + hex.substring(from: startIndex)
            print("ipfs ", profileHash, " hash", hex)
            return self.updateNonce(netId:netId, address: sender).then { nonce in
                self.forwardTo(netId:netId, sender: sender, identity: identity, destination: registryAddress , value: 0, registryDigest: registryDigest)
                //print("=======================================\n\n\n")
                }.then { _ in
                    return Promise(value: [sender,identity])
            }
        } catch {
            print(error.localizedDescription)
            return Promise(value: [])
        }
    }
    
    public func getIdentityProfile(netId: NetworkId, sender: Address, identity: Address) -> Promise<Dictionary<String, Any>>
    {
        let registrationIdentifier = "uPortProfileIPFS1220"
        let data = registrationIdentifier.data(using: .utf8)!
        let hexString = "0x"+data.map{ String(format:"%02x", $0) }.joined()
        
        return self.ipcClient.callContract(netId:netId, address: sender, contractName: "UportRegistry", methodName: "get", parameterValues: [hexString,identity.checksumAddress,identity.checksumAddress], contractAddress: Address(string:networkInterface(netId)[2]) ).then { str in
            
            let bn = BigNumber(hexString: str)
            
            if bn != BigNumber.constantZero() {
                let start = str.startIndex
                let ind = str.index(start, offsetBy: 2)
                let addr = "1220"+str.substring(from: ind)
                
                let stringBuf   = try SwiftHex.decodeString(hexString: addr)
                let ipfsHash = SwiftBase58.encode(stringBuf)
                //print(ipfsHash)
                return self.ipfsClient.getFile(hash: ipfsHash)
            } else {
                print("Error: ipfs hash is zero, i.e profile not found in registry")
                return Promise(value: Dictionary())
            }
        }
    }
    
    public func newIdentity(netId: NetworkId) -> Promise<Array<Address>>
    {
        var sender:Address?
        
        return Promise<Account> { fulfill, reject in
            self.accountManager.createAccount({ (account) in
                if account.address != nil {
                    sender = account.address
                    fulfill(account)
                } else {
                    let error = NSError(domain: "XClaim", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not create a new account"])
                    reject(error)
                }
            })
            }.then {  account in
                self.unlock(address: account.address)
            }.then { address in
                self.fundAddress(netId:netId,address: address)
            }.then { _ in
                self.createIdentityTransaction(netId:netId, address:sender!, contractName: "MetaIdentityManager",
                                               methodName: "createIdentity",
                                               parameterValues:  [sender!.checksumAddress, sender!.checksumAddress],
                                               contractAddress: Address(string: networkInterface(netId)[1]) )
        }
    }
    
    public func setupIdentity(netId: NetworkId, name: String, imgData: Data) -> Promise<Array<Address>>
    {
        var sender:Address?
        var identity:Address?
        
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        return self.newIdentity(netId:netId).then { addresses -> Void in
            sender = addresses[0] ; identity = addresses[1]
            self.updateNonce(netId:netId, address: sender!)
            }.then { nonce in
                self.makeProfileObject(name: name, imgData: imgData, sender: sender!, identity: identity!)
            }.then { objectHash in
                self.connectRegistry(netId:netId,  sender: sender!, identity: identity!, registryAddress: Address(string:networkInterface(netId)[2]), objectHash: objectHash)
            }.catch { error in
                print(error.localizedDescription)
            }.always {
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
        }
    }
}

public func checksum(payload: ArraySlice<UInt8>) -> ArraySlice<UInt8>
{
    let payloadData = Data(bytes: payload)
    let hashData = payloadData.sha3Final() // [236, 174, 187, 181]
    let hashArraySlice = [UInt8](hashData)[0...3]
    return hashArraySlice
}

extension Address {
    func encodeMNID(chainID: String) -> String
    {
        do {
            
            var versionArray = [UInt8]()
            versionArray.append(1 as UInt8)
            
            var chainArray = [UInt8]()
            let chainBytes = try chainID.decodeHex()
            
            for byte in chainBytes {
                chainArray.append(byte)
            }
            
            var addrArray = [UInt8]()
            let checksumAddress = self.checksumAddress.lowercased()
            
            let addrBytes = try checksumAddress.decodeHex()
            
            for byte in addrBytes {
                addrArray.append(byte)
            }
            
            let len = versionArray.count + chainArray.count + addrArray.count
            let payload = (versionArray + chainArray + addrArray)[0...(len-1)]
            let withChecksum = payload + checksum(payload: payload)
            
            let plain = [UInt8](withChecksum)
            
            let data = Data(plain)
            let base58 = data.base58EncodedString()
            
            return base58
            
        } catch {
            print("Can not encode MNID",error)
        }
        return ""
    }
}

extension String {
    func decodeMNID() -> [String]
    {
        do {
            let data = try self.decodeBase58()
            
            let buf = [UInt8](data)
            let chainLength = data.count-24
            let versionArray = [buf[0]]
            let chainArray = buf[1...(chainLength-1)]
            let addrArray = buf[chainLength...(20 + chainLength - 1)]
            let checkArray = buf[(20 + chainLength)...(data.count-1)]
            let len = versionArray.count + chainArray.count + addrArray.count
            let payload = (versionArray + chainArray + addrArray)[0...(len-1)]
            
            if checkArray == checksum(payload: payload) {
                // Now get back to hex strings again
                let x = chainArray.reduce("", { $0 + String(format: "%02x", $1)})
                let y = addrArray.reduce("", { $0 + String(format: "%02x", $1)})
                return [x,y]
            }
        } catch {
            print(error)
        }
        
        return []
    }
    
    func isMNID() -> Bool {
        do {
            let decoded = try self.decodeBase58()
            return decoded.count > 24 && decoded.first == 1
        } catch {
            return false
        }
    }
    
    func toDictionary() -> [String: Any]? {
        if let data = self.data(using: .utf8) {
            do {
                return try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            } catch {
                print(error.localizedDescription)
            }
        }
        return nil
    }
    
}


