import EtherKit

enum WalletNotification: String {
    case AddedAccountNotification                 = "WalletAddedAccountNotification"
    case RemovedAccountNotification               = "WalletRemovedAccountNotification"
    case ReorderedAccountsNotification            = "WalletReorderedAccountsNotification"
    case BalanceChangedNotification               = "WalletBalanceChangedNotification"
    case TransactionChangedNotification           = "WalletTransactionChangedNotification"
    case AccountTransactionsUpdatedNotification   = "WalletAccountTransactionsUpdatedNotification"
    case ChangedNicknameNotification              = "WalletChangedNicknameNotification"
    case ChangedActiveAccountNotification         = "WalletChangedActiveAccountNotification"
    case DidSyncNotification                      = "WalletDidSyncNotification"
    case DidChangeNetwork                         = "WalletDidChangeNetwork"
    
    var notification : Notification.Name  {
        return Notification.Name(rawValue: self.rawValue )
    }
}

enum ProviderNotification: String {
    case DidReceiveNewBlockNotification           = "ProviderDidReceiveNewBlockNotification"
    case EtherPriceChangedNotification            = "ProviderEtherPriceChangedNotification"
    
    var notification : Notification.Name  {
        return Notification.Name(rawValue: self.rawValue )
    }
}

enum DataStoreKey: String {
    case AccountPrefix              = "ACCOUNT_"
    case AccountBalancePrefix       = "ACCOUNT_BALANCE_"
    case AccountNicknamePrefix      = "ACCOUNT_NAME_"
    case AccountNoncePrefix         = "ACCOUNT_NONCE_"
    case AccountTxBlockNoncePrefix  = "ACCOUNT_TX_BLOCK_"
    case AccountTxsPrefix           = "ACCOUNT_TXS_"
    case NetworkPrefix              = "NETWORK_"
    case NetworkGasPrice            = "NETWORK_GAS_PRICE"
    case NetworkBlockNumber         = "NETWORK_BLOCK_NUMBER"
    case NetworkEtherPrice          = "NETWORK_ETHER_PRICE"
    case NetworkSyncDate            = "NETWORK_SYNC_DATE"
    case UserPrefix                 = "USER_"
    case UserActiveAccount          = "USER_ACTIVE_ACCOUNT"
    case UserAccounts               = "USER_ACCOUNTS"
    case UserEnableTestnet          = "USER_ENABLE_TESTNET"
    case UserEnableLightClient      = "USER_ENABLE_LIGHTCLIENT"
    case UserDisableFallback        = "USER_DISABLE_FALLBACK"
    case UserCustomNode             = "USER_CUSTOM_NODE"
    case RegistryFileName           = "REGISTRY_FILE_NAME"
}

class AccountManager
{
    //static let sharedInstance = AccountManager("us.proviv.claim")
    var keyChainKey = ""
    var jsonWallets = NSMutableDictionary(dictionary: [Address:String]())
    var accounts = NSMutableDictionary(dictionary: [Address:Account]())
    var orderedAddresses = NSMutableArray()
    var activeAccount:Address?
    var transactions = NSMutableDictionary(dictionary: [Address:[TransactionInfo]]())
    
    var dataStore = CachedDataStore()
    
    var firstRefreshDone = false
    
    // let keychainKey
    init?(_ keyChainKey: String) {
        self.keyChainKey = keyChainKey
        dataStore = CachedDataStore(key: keyChainKey)
        
        if let addressStrings = dataStore.array(forKey: DataStoreKey.UserAccounts.rawValue) {
            
            //print("KeyChain stored addressStrings",addressStrings)
            for addressString in addressStrings {
                let address = Address(string: addressString as! String)
                orderedAddresses.add(address!)
                //orderedAddresses.append(address!)
                //print("transactionsForAddress(",address!,") = ", transactionsForAddress(address!))
                transactions.setObject(transactionsForAddress(address!), forKey: address!)
            }
        } else {
            print("No addresses in DataStore")
        }
        
        if let active = dataStore.object(forKey: DataStoreKey.UserActiveAccount.rawValue)  {
            activeAccount = Address(string:active as! String)
        } else if orderedAddresses.count > 0 {
            activeAccount = orderedAddresses[0] as? Address
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(notifyApplicationActive) , name: NSNotification.Name(rawValue: NSNotification.Name.UIApplicationDidBecomeActive.rawValue), object: nil)
        /*
         
         let refreshKeychainTimer = Timer.scheduledTimer(withTimeInterval: <#T##TimeInterval#>, repeats: <#T##Bool#>, block: <#T##(Timer) -> Void#>)
         _refreshKeychainTimer = [NSTimer scheduledTimerWithTimeInterval:60.0f
         target:self
         selector:@selector(refreshKeychainValues)
         userInfo:@{}
         repeats:YES];
         */
        
        refreshKeychainValues()
        
    }
    
    @objc func notifyApplicationActive(note: Notification) {
        Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { (timer) in
            self.refreshKeychainValues()
        }
    }
    
    
    func sortTransactions(transactionInfos: [TransactionInfo]) -> Void
    {
        
        _ = transactionInfos.sorted { (a, b) -> Bool in
            
            if a.timestamp > b.timestamp {
                return  true
            } else if a.timestamp < b.timestamp {
                return false
            } else if a.timestamp == b.timestamp {
                
                if a.hash < b.hash {
                    return true
                } else if a.hash > b.hash {
                    return false
                }
                
            }
            return true
        }
    }
    
    func transactionsForAddress(_ address: Address) -> [TransactionInfo]
    {
        let transactionsByHash = objectForKeyPrefix(keyPrefix: DataStoreKey.AccountTxsPrefix.rawValue, address: address)
        
        if transactionsByHash == nil {
            return NSMutableArray(capacity: 4) as! [TransactionInfo]
        }
        
        let transactionsDict = transactionsByHash as! [String:[AnyHashable:Any]]
        let transactionInfos = NSMutableArray(capacity: transactionsDict.count)
        
        
        for info in transactionsDict.array {
            let transactionInfo = TransactionInfo(from: info.value)
            
            //print("transactionInfo",info, transactionInfo)
            
            if transactionInfo == nil {
                print("Bad Transaction: ", info)
                continue
            }
            transactionInfos.add(transactionInfo!)
        }
        sortTransactions(transactionInfos: transactionInfos as! [TransactionInfo])
        
        return transactionInfos as! [TransactionInfo]
    }
    
    
    func objectForKeyPrefix(keyPrefix:String,address:Address) -> Any?
    {
        return dataStore.object(forKey: keyPrefix+address.checksumAddress)
    }
    
    func uIntegerForKeyPrefix(keyPrefix:String,address:Address) -> UInt?
    {
        return UInt(dataStore.integer(forKey: keyPrefix+address.checksumAddress))
    }
    
    func setObject(object: NSObject, keyPrefix: String, address: Address)
    {
        dataStore.setObject(object , forKey: keyPrefix+address.checksumAddress)
    }
    
    func setInteger(value: Int, keyPrefix: String, address: Address)
    {
        dataStore.setInteger(value , forKey: keyPrefix+address.checksumAddress)
    }
    
    
    
    func createAccount(_ completion: @escaping ( _ account: Account) -> Void ) {
        let newAccount = Account.randomMnemonic()
        let password = "secret"
        
        _ = newAccount?.encryptSecretStorageJSON(password, callback: { (json) in
            
            self.accounts.setObject(newAccount!, forKey: (newAccount?.address)!)
            self.addAccount(account: newAccount!, json: json!)
            completion(newAccount!)
        })
        
    }
    
    
    func unlockAccount(_ address: Address, completion: @escaping ( _ account: Account?) -> Void ) {
        
        let json = getJSON(address: address)
        let password = "secret"
        
        Account.decryptSecretStorageJSON(json, password: password) { (account, error) in
            if  account != nil {
                self.accounts.setObject(account!, forKey: (account?.address)!)
                completion(account!)
            } else {
                completion(nil)
            }
        }
    }
    
    func addAccount(account:Account, json: String) {
        addKeychainVaue(keyChainKey, account.address, "xclaim.proviv.us", json)
        setObject(object: json as NSObject, keyPrefix: DataStoreKey.AccountNicknamePrefix.rawValue, address: account.address)
        
        jsonWallets.setObject(json, forKey: account.address)
        transactions.setObject(transactionsForAddress(account.address), forKey: account.address)
        orderedAddresses.add(account.address)
        saveAccountOrder()
        refreshActiveAccount()
        
        
        DispatchQueue.main.async {
            let userInfo = ["addAccount address": account.address as Any]
            NotificationCenter.default.post(name: WalletNotification.AddedAccountNotification.notification , object: self, userInfo: userInfo)
            self.refreshActiveAccount()
        }
        
    }
    
    func setActiveAccount(address: Address) {
        if activeAccount == address || address.isEqual(to: activeAccount) {
            return
        }
        
        activeAccount = address
        DispatchQueue.main.async {
            let userInfo = ["address" : self.activeAccount as Any]
            NotificationCenter.default.post(name: WalletNotification.ChangedActiveAccountNotification.notification , object: self, userInfo: userInfo)
        }
        
        let checksumAddress = activeAccount?.checksumAddress!
        
        dataStore.setObject(checksumAddress! as NSObject, forKey: DataStoreKey.UserActiveAccount.rawValue)
    }
    
    func removeAccount(account:Account) {
        removeKeychainValue(keyChainKey, account.address)
        accounts.removeObject(forKey: account.address)
        jsonWallets.removeObject(forKey: account.address)
        transactions.removeObject(forKey: account.address)
        var i = 0
        for address  in orderedAddresses  {
            if address as? Address == account.address {
                break
            }
            i = i + 1
        }
        
        orderedAddresses.remove(i)
        
        refreshActiveAccount()
        
        DispatchQueue.main.async {
            let userInfo = ["address" : account.address as Any]
            NotificationCenter.default.post(name: WalletNotification.ChangedActiveAccountNotification.notification , object: self, userInfo: userInfo)
        }
    }
    
    
    func getJSON(address:Address) -> String {
        var json = jsonWallets[address]
        
        if json == nil {
            json = getKeychainValue(keyChainKey, address)
            if json == nil {
                print("ERROR: Missing JSON ", address)
            }
            jsonWallets.setObject(json!, forKey: address)
        }
        return json! as! String
    }
    
    func saveAccountOrder() {
        var addresses = [String]()
        for address in orderedAddresses {
            addresses.append((address as! Address).checksumAddress)
        }
        dataStore.setArray(addresses, forKey: DataStoreKey.UserAccounts.rawValue)
    }
    
    func refreshActiveAccount() {
        var account = activeAccount
        if account != nil && account != Address.zero() {
            if orderedAddresses.contains(account!) {
                return
            } else {
                account = Address.zero()
            }
        }
        
        if orderedAddresses.count > 0 {
            account = orderedAddresses[0] as! Address
            setActiveAccount(address: account!)
        }
        
    }
    
    func debugTransactions()
    {
        if self.activeAccount != nil {
            let transactionInfos = transactionsForAddress(self.activeAccount!)
            for transactionInfo in transactionInfos {
                print(self.activeAccount!,":",transactionInfo)
            }
        }
    }
    
    func refreshKeychainValues() {
        let accountNicknames = getKeychainNicknames(keyChainKey)! as NSDictionary
        if accountNicknames.count > 0 {
            let newAccounts = NSMutableSet(capacity: jsonWallets.count)
            
            for accountNickname in accountNicknames {
                let address = accountNickname.key as! Address
                
                if jsonWallets.object(forKey: address) != nil {
                    newAccounts.add(address)
                } else {
                    let json = getKeychainValue(keyChainKey, address )
                    if json == nil {
                        print("Error - Refresh Keychain Values: Missing JSON (%@)", address);
                        continue;
                    }
                    
                    let jsonData = json?.data(using: .utf8)
                    
                    do {
                        let account = try JSONSerialization.jsonObject(with: jsonData!, options: []) as! NSDictionary
                        
                        let jsonAddress = Address(string: account.object(forKey: "address") as! String)
                        
                        if jsonAddress == nil || !address.isEqual(to: jsonAddress) {
                            print("Error - Refresh Keychain Values: Missing JSON (%@)", address);
                            continue;
                        }
                        
                        jsonWallets.setObject(json!, forKey: address)
                        
                        transactions.setObject(transactionsForAddress(address), forKey: address)
                        newAccounts.add(address)
                    } catch {
                        
                    }
                }
                let nickname = accountNicknames.object(forKey: address) as! String
                
                if nickname != nicknameForAccount(address: address) {
                    setNickname(nickname: nickname, address: address)
                }
            }
        }
    }
    
    func setNickname(nickname:String, address:Address) {
        setObject(object: nickname as NSObject, keyPrefix: DataStoreKey.AccountNicknamePrefix.rawValue, address: address)
        
        DispatchQueue.main.async {
            let userInfo = ["address":address,"nickname":nickname] as [String : Any]
            NotificationCenter.default.post(name: WalletNotification.ChangedNicknameNotification.notification , object: self, userInfo: userInfo)
        }
        
    }
    
    func nicknameForAccount(address:Address) -> String
    {
        var nickname = objectForKeyPrefix(keyPrefix: DataStoreKey.AccountNicknamePrefix.rawValue, address: address)
        
        if nickname == nil {
            nickname = "XClaim"
        }
        
        return nickname as! String
    }
    
    
    func refresh(netId: NetworkId, _ callback: @escaping (_: Bool) -> Void)
    {
        print("refresh")
        
        let client = CCKClient(accountManager: self)
        
        for address in self.orderedAddresses {
            
            _ = client?.eth_getBalance(netId:netId, address: address as! Address, tag: .pending).then { balance -> Void in
                //print("getBalance ",balance)
                self.setSyncDate()
                _ = self.setBalance(address: address as! Address, balanceWei: balance)
            }
            
            _ = client?.eth_getTransactionCount(netId:netId,address: address as! Address, tag: .pending).then { nonce -> Void in
                
                //print("getTransactionCount: ",nonce, "address ", address)
                
                self.setSyncDate()
                self.setNonce(nonce: UInt(nonce), address: address as! Address)
            }
            
            /*
             _ = client?.eth_getTransactions(netId:netId,address: address, startBlock: 0).then { transactions -> Void in
             
             print("getTransactions",transactions)
             let highestBlock = self.addTransactionInfos(transactionInfos: transactions, address: address)
             
             self.setTxBlock(txBlock: highestBlock, forAddress: address)
             }
             */
            
            _ = client?.eth_getGasPrice(netId:netId).then { gasPrice -> Void in
                //print("getGasPrice",gasPrice)
                self.setGasPrice(gasPrice: gasPrice)
            }
            
            _ = client?.eth_getBlockNumber(netId:netId).then { blockNumber -> Void in
                //print("getBlockNumber",blockNumber)
                self.setBlocknumber(blockNumber: blockNumber)
            }
        }
        
        callback(true)
    }
    
    func numberOfAccounts() -> Int {
        return orderedAddresses.count;
    }
    
    func setBalance(address:Address,balanceWei:BigNumber) -> Bool
    {
        
        if balanceWei.isEqual(balance(address)) {
            return false
        }
        
        setObject(object: balanceWei.hexString! as NSObject, keyPrefix: DataStoreKey.AccountBalancePrefix.rawValue, address: address)
        
        
        DispatchQueue.main.async {
            let userInfo = ["address":address as Any, "balance": balanceWei as Any]
            NotificationCenter.default.post(name: WalletNotification.BalanceChangedNotification.notification , object: self, userInfo: userInfo)
        }
        
        return true
    }
    
    func balance(_ address:Address) -> BigNumber
    {
        let balanceHex = objectForKeyPrefix(keyPrefix: DataStoreKey.AccountBalancePrefix.rawValue, address:address)
        
        if balanceHex != nil
        {
            return BigNumber(hexString: balanceHex as! String)
        } else {
            return BigNumber.constantZero()
        }
    }
    
    func setNonce(nonce: UInt, address: Address)
    {
        setInteger(value: Int(nonce), keyPrefix: DataStoreKey.AccountNoncePrefix.rawValue, address: address)
    }
    
    func nonce(_ address:Address) -> UInt
    {
        return uIntegerForKeyPrefix(keyPrefix: DataStoreKey.AccountNoncePrefix.rawValue, address: address)!
    }
    
    
    func setSyncDate() {
        
        let syncDate = Date.timeIntervalSinceReferenceDate
        let changed = dataStore.setTimeInterval(syncDate, forKey: DataStoreKey.NetworkSyncDate.rawValue)
        
        if changed {
            DispatchQueue.main.async {
                let userInfo = ["syncDate": syncDate]
                NotificationCenter.default.post(name: WalletNotification.DidSyncNotification.notification , object: self, userInfo: userInfo)
            }
        }
        
    }
    
    func syncDate() -> TimeInterval
    {
        return dataStore.timeInterval(forKey: DataStoreKey.NetworkSyncDate.rawValue)
    }
    
    
    func setBlocknumber(blockNumber: Int)
    {
        dataStore.setInteger(blockNumber, forKey: DataStoreKey.NetworkBlockNumber.rawValue)
        
        if activeAccount != nil  && transactionsForAddress(activeAccount!).count > 0
        {
            DispatchQueue.main.async {
                let userInfo = ["address": self.activeAccount!, "highestBlockNumber" : self.txBlockForAddress(address: self.activeAccount!)!] as [String : Any]
                NotificationCenter.default.post(name: WalletNotification.DidSyncNotification.notification , object: self, userInfo: userInfo)
            }
            
        }
    }
    
    func blockNumber() -> BlockTag
    {
        return dataStore.integer(forKey: DataStoreKey.NetworkBlockNumber.rawValue)
    }
    
    func etherPrice() -> Float
    {
        return dataStore.float(forKey: DataStoreKey.NetworkEtherPrice.rawValue)
    }
    
    func setEtherPrice(etherPrice:Float) -> Bool
    {
        return dataStore.setFloat(etherPrice, forKey: DataStoreKey.NetworkEtherPrice.rawValue)
        
    }
    
    func setTxBlock(txBlock: Int, forAddress: Address)
    {
        setInteger(value: txBlock, keyPrefix: DataStoreKey.AccountTxBlockNoncePrefix.rawValue, address: forAddress)
    }
    
    func txBlockForAddress(address:Address) -> UInt?
    {
        return uIntegerForKeyPrefix(keyPrefix: DataStoreKey.AccountTxBlockNoncePrefix.rawValue, address: address)
    }
    
    func setGasPrice(gasPrice:BigNumber)
    {
        dataStore.setString(gasPrice.hexString, forKey: DataStoreKey.NetworkGasPrice.rawValue)
    }
    
    func gasPrice() -> BigNumber {
        let gasPrice = dataStore.string(forKey: DataStoreKey.NetworkGasPrice.rawValue)
        
        if gasPrice != nil {
            return BigNumber(hexString: gasPrice)
        } else {
            return BigNumber(decimalString: "18000000000")
        }
    }
    
    func addTransactionInfos(transactionInfos: [TransactionInfo], address: Address) -> Int
    {
        var transactionsByHash = objectForKeyPrefix(keyPrefix: DataStoreKey.AccountTxsPrefix.rawValue, address: address) as! NSMutableDictionary
        
        if transactionsByHash.count == 0 {
            transactionsByHash = NSMutableDictionary(capacity: 4)
        }
        
        let currentTransactionInfos = transactions.object(forKey: address) as! [TransactionInfo]
        var changedTransactions =  [TransactionInfo]()
        
        var changed = transactionInfos == currentTransactionInfos
        
        
        for transactionInfo in transactionInfos {
            let transactionHash = transactionInfo.transactionHash.hexString as NSObject
            let info = transactionsByHash.object(forKey: transactionHash) as! TransactionInfo
            
            transactionsByHash.setObject(transactionInfo.dictionaryRepresentation(), forKey: transactionHash as! NSCopying)
            
            //
            if info.isEqual(transactionInfo)
            {
                continue
            }
            changedTransactions.append(transactionInfo)
            changed = true
        }
        
        setObject(object: transactionsByHash, keyPrefix: DataStoreKey.AccountTxsPrefix.rawValue, address: address)
        if changed {
            transactions.setObject(transactionsForAddress(address), forKey: address)
        }
        
        var highestBlockNumber = -1
        
        if transactions.count > 0 {
            let lastTransactionInfo = transactions.allValues.last as! TransactionInfo
            highestBlockNumber = lastTransactionInfo.blockNumber
        }
        
        if changed {
            
            DispatchQueue.main.async {
                let userInfo = ["address": address,"highestBlockNumber": highestBlockNumber] as [String : Any]
                NotificationCenter.default.post(name: WalletNotification.AccountTransactionsUpdatedNotification.notification , object: self, userInfo: userInfo)
                for transactionInfo in changedTransactions {
                    let userInfo = ["transaction": transactionInfo] as [String : Any]
                    NotificationCenter.default.post(name: WalletNotification.TransactionChangedNotification.notification , object: self, userInfo: userInfo)
                    
                }
            }
            
        }
        
        return highestBlockNumber
    }
    /*
     func
     NSMutableArray *pending = [NSMutableArray array];
     NSMutableArray *inProgress = [NSMutableArray array];
     NSMutableArray *confirmed = [NSMutableArray array];
     
     Address *activeAccount = _wallet.activeAccount;
     NSUInteger blockNumber = _wallet.blockNumber;
     
     int minInProgressConfirmations = CONFIRMED_COUNT;
     int maxInProgressConfirmations = 0;
     
     NSUInteger transactionCount = [_wallet transactionCountForAddress:activeAccount];
     for (NSUInteger i = 0; i < transactionCount; i++) {
     TransactionInfo *transactionInfo = [_wallet transactionForAddress:activeAccount index:i];
     
     if (transactionInfo.blockNumber == -1) {
     [pending addObject:transactionInfo];
     
     } else {
     int confirmations = (int)(blockNumber - transactionInfo.blockNumber + 1);
     if (confirmations < CONFIRMED_COUNT) {
     [inProgress addObject:transactionInfo];
     if (confirmations < minInProgressConfirmations) {
     minInProgressConfirmations = confirmations;
     }
     if (confirmations > maxInProgressConfirmations) {
     maxInProgressConfirmations = confirmations;
     }
     } else {
     [confirmed addObject:transactionInfo];
     }
     }
     }
     */
    
}


