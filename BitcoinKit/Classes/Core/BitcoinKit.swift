import BitcoinCore
import HdWalletKit
import Hodler
import BigInt
import RxSwift

public class BitcoinKit: AbstractKit {
    private static let heightInterval = 2016                                    // Default block count in difficulty change circle ( Bitcoin )
    private static let targetSpacing = 10 * 60                                  // Time to mining one block ( 10 min. Bitcoin )
    private static let maxTargetBits = 0x1d00ffff                               // Initially and max. target difficulty for blocks

    private static let name = "BitcoinKit"

    public enum NetworkType: String, CaseIterable { case mainNet, testNet, regTest }

    public weak var delegate: BitcoinCoreDelegate? {
        didSet {
            bitcoinCore.delegate = delegate
        }
    }

    public init(withWords words: [String], bip: Bip, walletId: String, syncMode: BitcoinCore.SyncMode = .api, networkType: NetworkType = .mainNet, confirmationsThreshold: Int = 6, minLogLevel: Logger.Level = .verbose) throws {
        let network: INetwork
        let initialSyncApiUrl: String

        switch networkType {
            case .mainNet:
                network = MainNet()
                initialSyncApiUrl = "https://btc.horizontalsystems.xyz/apg"
            case .testNet:
                network = TestNet()
                initialSyncApiUrl = "http://btc-testnet.horizontalsystems.xyz/apg"
            case .regTest:
                network = RegTest()
                initialSyncApiUrl = ""
        }
        let initialSyncApi = BCoinApi(url: initialSyncApiUrl)

        let databaseFilePath = try DirectoryHelper.directoryURL(for: BitcoinKit.name).appendingPathComponent(BitcoinKit.databaseFileName(walletId: walletId, networkType: networkType, bip: bip, syncMode: syncMode)).path
        let storage = GrdbStorage(databaseFilePath: databaseFilePath)

        let paymentAddressParser = PaymentAddressParser(validScheme: "bitcoin", removeScheme: true)
        let scriptConverter = ScriptConverter()
        let bech32AddressConverter = SegWitBech32AddressConverter(prefix: network.bech32PrefixPattern, scriptConverter: scriptConverter)
        let base58AddressConverter = Base58AddressConverter(addressVersion: network.pubKeyHash, addressScriptVersion: network.scriptHash)

        let bitcoinCoreBuilder = BitcoinCoreBuilder(minLogLevel: minLogLevel)

        let difficultyEncoder = DifficultyEncoder()

        let blockValidatorSet = BlockValidatorSet()
        blockValidatorSet.add(blockValidator: ProofOfWorkValidator(difficultyEncoder: difficultyEncoder))

        let blockValidatorChain = BlockValidatorChain()
        let blockHelper = BlockValidatorHelper(storage: storage)

        switch networkType {
        case .mainNet:
            blockValidatorChain.add(blockValidator: LegacyDifficultyAdjustmentValidator(encoder: difficultyEncoder, blockValidatorHelper: blockHelper, heightInterval: BitcoinKit.heightInterval, targetTimespan: BitcoinKit.heightInterval * BitcoinKit.targetSpacing, maxTargetBits: BitcoinKit.maxTargetBits))
            blockValidatorChain.add(blockValidator: BitsValidator())
        case .regTest, .testNet:
            blockValidatorChain.add(blockValidator: LegacyDifficultyAdjustmentValidator(encoder: difficultyEncoder, blockValidatorHelper: blockHelper, heightInterval: BitcoinKit.heightInterval, targetTimespan: BitcoinKit.heightInterval * BitcoinKit.targetSpacing, maxTargetBits: BitcoinKit.maxTargetBits))
            blockValidatorChain.add(blockValidator: LegacyTestNetDifficultyValidator(blockHelper: blockHelper, heightInterval: BitcoinKit.heightInterval, targetSpacing: BitcoinKit.targetSpacing, maxTargetBits: BitcoinKit.maxTargetBits))
        }

        blockValidatorSet.add(blockValidator: blockValidatorChain)

        let hodler = HodlerPlugin(addressConverter: bitcoinCoreBuilder.addressConverter, blockMedianTimeHelper: BlockMedianTimeHelper(storage: storage), publicKeyStorage: storage)
        
        let bitcoinCore = try bitcoinCoreBuilder
                .set(network: network)
                .set(initialSyncApi: initialSyncApi)
                .set(words: words)
                .set(bip: bip)
                .set(paymentAddressParser: paymentAddressParser)
                .set(walletId: walletId)
                .set(confirmationsThreshold: confirmationsThreshold)
                .set(peerSize: 10)
                .set(syncMode: syncMode)
                .set(storage: storage)
                .set(blockValidator: blockValidatorSet)
                .add(plugin: hodler)
                .build()

        super.init(bitcoinCore: bitcoinCore, network: network)

        // extending BitcoinCore

        bitcoinCore.prepend(addressConverter: bech32AddressConverter)

        switch bip {
        case .bip44:
            bitcoinCore.add(restoreKeyConverter: Bip44RestoreKeyConverter(addressConverter: base58AddressConverter))
            bitcoinCore.add(restoreKeyConverter: Bip49RestoreKeyConverter(addressConverter: base58AddressConverter))
            bitcoinCore.add(restoreKeyConverter: Bip84RestoreKeyConverter(addressConverter: bech32AddressConverter))
        case .bip49:
            bitcoinCore.add(restoreKeyConverter: Bip49RestoreKeyConverter(addressConverter: base58AddressConverter))
        case .bip84:
            bitcoinCore.add(restoreKeyConverter: Bip84RestoreKeyConverter(addressConverter: bech32AddressConverter))
        }
    }

}

extension BitcoinKit {

    public static func clear(exceptFor walletIdsToExclude: [String] = []) throws {
        try DirectoryHelper.removeAll(inDirectory: BitcoinKit.name, except: walletIdsToExclude)
    }

    private static func databaseFileName(walletId: String, networkType: NetworkType, bip: Bip, syncMode: BitcoinCore.SyncMode) -> String {
        "\(walletId)-\(networkType.rawValue)-\(bip.description)-\(syncMode)"
    }

}
