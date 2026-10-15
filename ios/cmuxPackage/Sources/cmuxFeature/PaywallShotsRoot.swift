#if os(iOS)
// THROWAWAY (never merged): simulator screenshot harness for the paywall PR.
// Renders the real paywall, upgrade card, Cloud section and Paywall Lab over
// real BillingModel / CloudSessionController instances whose network and
// StoreKit seams return fixed data (StoreKit cannot load products on the
// fleet simulator). Slides advance on a timer so one recording captures all.
import CMUXMobileCore
import CmuxMobileBilling
import CmuxMobileBillingUI
import CmuxMobileCloud
import CmuxMobileCloudUI
import Foundation
import SwiftUI

public struct PaywallShotsRoot: View {
    @State private var index = 0

    public init() {}

    private static let slides: [ShotSlide] = {
        var slides: [ShotSlide] = []
        for scheme in [ColorScheme.light, .dark] {
            slides.append(.init(name: "settings-upgrade-card", scheme: scheme, kind: .settings))
            slides.append(.init(name: "cloud-banner", scheme: scheme, kind: .cloud))
            slides.append(.init(name: "paywall-cards", scheme: scheme, kind: .paywall(.cards, trial: false)))
            slides.append(.init(name: "paywall-comparison", scheme: scheme, kind: .paywall(.comparison, trial: false)))
            slides.append(.init(name: "paywall-focus", scheme: scheme, kind: .paywall(.focus, trial: false)))
            slides.append(.init(name: "paywall-trial", scheme: scheme, kind: .paywall(.cards, trial: true)))
        }
        slides.append(.init(name: "paywall-cards-action-monthly", scheme: .light, kind: .paywallAction))
        slides.append(.init(name: "paywall-ineligible-web", scheme: .light, kind: .ineligible))
        slides.append(.init(name: "paywall-lab", scheme: .light, kind: .lab))
        slides.append(.init(name: "se-paywall-cards", scheme: .light, kind: .paywall(.cards, trial: false), small: true))
        slides.append(.init(name: "se-paywall-comparison", scheme: .dark, kind: .paywall(.comparison, trial: false), small: true))
        slides.append(.init(name: "se-settings-upgrade-card", scheme: .light, kind: .settings, small: true))
        slides.append(.init(name: "ax-paywall-cards", scheme: .light, kind: .paywall(.cards, trial: false), dynamicType: .accessibility2))
        slides.append(.init(name: "ax-paywall-comparison", scheme: .dark, kind: .paywall(.comparison, trial: false), dynamicType: .accessibility2))
        return slides
    }()

    public var body: some View {
        let slide = Self.slides[min(index, Self.slides.count - 1)]
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            Group {
                if slide.small {
                    ShotSlideView(slide: slide)
                        .frame(width: 375, height: 667)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ShotSlideView(slide: slide)
                }
            }
            .id(index)
            Text(verbatim: "\(index + 1) \(slide.name)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.gray)
                .padding(.leading, 6)
                .allowsHitTesting(false)
        }
        .preferredColorScheme(slide.scheme)
        .task {
            // Pacing for the recording only; this harness is never merged.
            for next in Self.slides.indices.dropFirst() {
                try? await Task.sleep(for: .seconds(5))
                index = next
            }
        }
    }
}

struct ShotSlide {
    enum Kind {
        case settings
        case cloud
        case paywall(BillingPaywallLayout, trial: Bool)
        case paywallAction
        case ineligible
        case lab
    }

    let name: String
    let scheme: ColorScheme
    let kind: Kind
    var small = false
    var dynamicType: DynamicTypeSize = .large
}

struct ShotSlideView: View {
    let slide: ShotSlide
    @State private var model: BillingModel
    @State private var cloud: CloudSessionController?

    init(slide: ShotSlide) {
        self.slide = slide
        var config = BillingPaywallConfig.control
        var trial = false
        var eligible = true
        var staff = false
        switch slide.kind {
        case .paywall(let layout, let withTrial):
            trial = withTrial
            config = ShotFixtures.config(layout: layout)
        case .paywallAction:
            config = BillingPaywallConfig(
                experiment: "ios-paywall-v1", variant: "action-monthly", layout: .cards,
                headline: "Keep your agents running", subheadline: "Cloud VMs keep working when your Mac sleeps.",
                bullets: [], highlightedPlanID: .max, defaultBillingPeriod: .monthly, ctaStyle: .action,
                showYearlySavings: false
            )!
        case .ineligible:
            eligible = false
        case .lab, .settings:
            staff = true
        case .cloud:
            break
        }
        _model = State(initialValue: BillingModel(
            api: ShotBillingAPI(config: config, trial: trial, eligible: eligible, staff: staff),
            store: ShotStoreKit(),
            analytics: nil,
            trialProver: trial ? ShotProver() : nil
        ))
        if case .cloud = slide.kind {
            _cloud = State(initialValue: CloudSessionController(
                service: ShotCloudService(),
                identityStore: ShotIdentityStore(),
                tunnelStarter: ShotTunnelStarter(),
                connector: ShotConnector(),
                stateDirectory: FileManager.default.temporaryDirectory,
                deviceName: "iPhone"
            ))
        }
    }

    var body: some View {
        content
            .environment(model)
            .dynamicTypeSize(slide.dynamicType)
    }

    @ViewBuilder
    private var content: some View {
        switch slide.kind {
        case .settings:
            NavigationStack {
                Form {
                    MobileSettingsUpgradeSection()
                    Section {
                        LabeledContent("Signed in as", value: "you@example.com")
                        Text("Sign Out").foregroundStyle(.red)
                    } header: { Text("Account") }
                    MobileSettingsPlanSection()
                    Section {
                        Label("What's New", systemImage: "megaphone")
                        Label("Terminal Shortcuts", systemImage: "keyboard")
                    }
                }
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
            }
        case .cloud:
            if let cloud {
                NavigationStack {
                    CloudSectionView(controller: cloud)
                }
                .task { cloud.refreshMachines() }
            }
        case .paywall, .paywallAction, .ineligible:
            NavigationStack {
                MobilePaywallView(entryPoint: .settingsUpgradeCard)
            }
        case .lab:
            NavigationStack {
                MobilePaywallLabView()
            }
        }
    }
}

enum ShotFixtures {
    static func config(layout: BillingPaywallLayout) -> BillingPaywallConfig {
        switch layout {
        case .cards:
            return .control
        case .comparison:
            return BillingPaywallConfig(
                experiment: "ios-paywall-v1", variant: "comparison", layout: .comparison,
                headline: "Compare plans", subheadline: "Every plan includes the iPhone and Mac apps.",
                bullets: [], highlightedPlanID: .pro, defaultBillingPeriod: .yearly, ctaStyle: .price,
                showYearlySavings: true
            )!
        case .focus:
            return BillingPaywallConfig(
                experiment: "ios-paywall-v1", variant: "focus-pro", layout: .focus,
                headline: "Your agents, always on",
                subheadline: "Terminals on a Cloud VM keep running when you close your laptop.",
                bullets: [
                    "Up to 5 Cloud VMs sharing 20 vCPUs and 40 GB RAM",
                    "Agents open pull requests without touching your Mac",
                    "Persistent Linux machines keep files and tools",
                ],
                highlightedPlanID: .pro, defaultBillingPeriod: .yearly, ctaStyle: .action,
                showYearlySavings: true
            )!
        }
    }
}

struct ShotBillingAPI: BillingAPI {
    let config: BillingPaywallConfig
    let trial: Bool
    let eligible: Bool
    let staff: Bool

    func accountToken() async throws -> BillingAccount {
        BillingAccount(
            appAccountToken: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!,
            eligible: eligible,
            reason: eligible ? nil : .stripeSubscriptionActive,
            currentPlan: BillingCurrentPlan(planID: .free, source: .none),
            products: eligible ? ShotStoreKit.references : [],
            paywall: config,
            trial: trial ? BillingTrialOffer(
                offered: true, planID: .pro, billingPeriod: .monthly,
                productID: "com.cmux.app.pro.trial.monthly", attestRequired: true,
                limits: BillingTrialLimits(machines: 1, vcpus: 2, memoryGb: 4, vmHours: 20)
            ) : nil,
            staff: staff
        )
    }

    func submitTransaction(signedTransactionInfo: String) async throws -> BillingTransactionReceipt {
        throw URLError(.notConnectedToInternet)
    }

    func trialChallenge() async throws -> String { "challenge" }

    func verifyTrial(_ request: BillingTrialVerifyRequest) async throws -> BillingTrialVerification {
        BillingTrialVerification(eligible: true, introductoryOfferJWS: "jws", legacyTrialAllowed: true, reason: nil)
    }

    func paywallVariants() async throws -> [BillingPaywallVariant] {
        [
            BillingPaywallVariant(status: "live", config: .control),
            BillingPaywallVariant(status: "live", config: ShotFixtures.config(layout: .comparison)),
            BillingPaywallVariant(status: "live", config: ShotFixtures.config(layout: .focus)),
            BillingPaywallVariant(status: "retired", config: BillingPaywallConfig(
                experiment: "ios-paywall-v0", variant: "plain", layout: .cards, headline: "Plans",
                subheadline: "", bullets: [], highlightedPlanID: nil, defaultBillingPeriod: .monthly,
                ctaStyle: .price, showYearlySavings: false
            )!),
        ]
    }
}

struct ShotProver: BillingTrialDeviceProving {
    var isSupported: Bool { true }
    func proof(clientData: Data) async throws -> BillingTrialDeviceProof {
        BillingTrialDeviceProof(keyID: "k", attestation: "a", assertion: nil, deviceCheckToken: "t")
    }
    func resetKey() async {}
}

/// USD prices of the App Store products, as the USA storefront shows them.
struct ShotStoreKit: StoreKitClient {
    static let references: [BillingProductReference] = [
        BillingProductReference(productID: "com.cmux.app.go.monthly", planID: .go),
        BillingProductReference(productID: "com.cmux.app.pro.monthly", planID: .pro),
        BillingProductReference(productID: "com.cmux.app.pro.yearly", planID: .pro),
        BillingProductReference(productID: "com.cmux.app.max.monthly", planID: .max),
        BillingProductReference(productID: "com.cmux.app.max.yearly", planID: .max),
    ]

    private static let prices: [String: (Decimal, Bool)] = [
        "com.cmux.app.go.monthly": (14.99, false),
        "com.cmux.app.pro.monthly": (74.99, false),
        "com.cmux.app.pro.yearly": (699.99, true),
        "com.cmux.app.max.monthly": (299.99, false),
        "com.cmux.app.max.yearly": (2799.99, true),
        "com.cmux.app.pro.trial.monthly": (74.99, false),
    ]

    func products(for ids: [String]) async throws -> [StoreProduct] {
        let style = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
        return ids.compactMap { id in
            guard let (price, yearly) = Self.prices[id] else { return nil }
            return StoreProduct(
                id: id,
                displayName: id,
                productDescription: "",
                displayPrice: price.formatted(style),
                periodUnitName: yearly ? "year" : "month",
                price: price,
                currencyCode: "USD",
                monthlyEquivalentDisplayPrice: yearly ? (price / 12).formatted(style) : nil,
                introductoryOffer: id.contains(".trial.")
                    ? StoreIntroductoryOffer(periodValue: 7, periodUnit: .day, periodCount: 1, isFreeTrial: true, isEligibleOnDevice: true)
                    : nil
            )
        }
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> StorePurchaseResult { .userCancelled }
    func transactionUpdates() -> AsyncStream<StoreTransactionVerification> { AsyncStream { _ in } }
    func unfinishedTransactions() async -> [StoreTransactionVerification] { [] }
    func currentEntitlements() async -> [StoreTransactionVerification] { [] }
    func syncWithAppStore() async throws {}
    func storefrontCountryCode() async -> String? { "USA" }
    func finish(transactionID: UInt64) async {}
}

struct ShotFailure: Error {}

struct ShotCloudService: CloudVMServing {
    func listMachines() async throws -> [CloudMachine] { [] }
    func listMachineCatalog() async throws -> CloudMachineCatalog {
        CloudMachineCatalog(
            machines: [],
            availableKinds: nil,
            limits: CloudMachineLimits(maxActiveMachines: 0, activeMachineCount: 0, planID: "free", memoryOptionsMb: [8192])
        )
    }
    func createMachine(options: CloudMachineCreateOptions, idempotencyKey: String) async throws -> CloudMachine { throw ShotFailure() }
    func enrollTunnel(clientPublicKey: String, deviceFingerprint: String, tunnelPurpose: CloudTunnelPurpose, deviceName: String?) async throws
        -> CloudTunnelEnrollment { throw ShotFailure() }
    func enrollTunnel(
        clientPublicKey: String,
        deviceFingerprint: String,
        tunnelPurpose: CloudTunnelPurpose,
        deviceName: String?,
        credentials: CloudAPITokenSource.TokenContext?
    ) async throws -> CloudTunnelEnrollment { throw ShotFailure() }
    func revokeTunnel(deviceFingerprint: String, tunnelPurpose: CloudTunnelPurpose) async throws {}
    func revokeTunnel(deviceFingerprint: String, tunnelPurpose: CloudTunnelPurpose, accessToken: String, refreshToken: String) async throws {}
    func revokeTunnel(
        deviceFingerprint: String,
        tunnelPurpose: CloudTunnelPurpose,
        accessToken: String,
        refreshToken: String,
        teamID: String?
    ) async throws {}
    func openAttach(machineID: String, deviceFingerprint: String) async throws -> CloudAttachEndpoint { throw ShotFailure() }
    func approveEnrollment(machineID: String, invitationId: String) async throws -> Bool { false }
    func pauseMachine(id: String) async throws {}
    func resumeMachine(id: String) async throws {}
    func restartMachine(id: String) async throws {}
    func deleteMachine(id: String) async throws {}
}

struct ShotIdentityStore: CloudDeviceIdentityStoring {
    func read() async -> CloudDeviceIdentityReadResult { .absent }
    func resolve() async throws -> CloudDeviceIdentity { throw ShotFailure() }
    func write(_ identity: CloudDeviceIdentity) async throws {}
}

struct ShotTunnelStarter: CloudTunnelStarting {
    func start(wgQuickConfig: String) async throws -> any CloudTunnel { throw ShotFailure() }
}

struct ShotConnector: CloudTerminalConnecting {
    func connect(
        route: String,
        stateDirectory: URL,
        deviceName: String,
        invitation: String?,
        trustedCarrier: Bool,
        tunnel: (any CloudTunnel)?
    ) async throws -> any CloudTerminalSession { throw ShotFailure() }
}
#endif
