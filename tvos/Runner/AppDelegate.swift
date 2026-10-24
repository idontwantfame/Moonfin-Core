import Flutter
import GameController
import UIKit

/// Hosts the Flutter view so a game controller can be kept away from the UI.
///
/// The one switch tvOS offers is this view controller's
/// `controllerUserInteractionEnabled`, honored for whatever sits in its
/// responder chain, so it has to be an ancestor of the Flutter view rather
/// than a sibling. Off routes controller input to the GameController profiles
/// instead of the responder chain, and that covers more devices than a
/// gamepad: the Siri Remote is a microGamepad, a paired keyboard is a
/// GCKeyboard, and a third party remote reaches tvOS as one or the other. It
/// therefore starts on, matching the Apple TV preference default, until Dart
/// sends the stored value.
final class GamepadNavigationHostViewController: GCEventViewController {
    let flutterViewController: FlutterViewController

    init(flutterViewController: FlutterViewController) {
        self.flutterViewController = flutterViewController
        super.init(nibName: nil, bundle: nil)
        controllerUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(flutterViewController)
        flutterViewController.view.frame = view.bounds
        flutterViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(flutterViewController.view)
        flutterViewController.didMove(toParent: self)
    }
}

@main
class AppDelegate: FlutterAppDelegate {
    // Keep the single Flutter host alive across scene disconnections. The scene
    // owns its window; plugins and channels are still ready before app launch ends.
    private(set) var gamepadHost: GamepadNavigationHostViewController?
    private var hasConnectedScene = false
    private var nativeApplePlayerChannel: NativeApplePlayerChannel?
    private var topShelfChannel: TopShelfChannel?
    private var previewChannel: AppleTvPreviewChannel?
    private var systemChannel: AppleTvSystemChannel?
    private var audioChannel: AppleTvAudioChannel?
    private var themeMusicChannel: AppleTvThemeMusicChannel?
    private var sfSymbolChannel: AppleTvSfSymbolChannel?
    private var gameChannel: AppleTvGameChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let gamepadHost = GamepadNavigationHostViewController(
            flutterViewController: flutterViewController)
        self.gamepadHost = gamepadHost

        // The scene's root is a gamepad host, so register plugins against the
        // Flutter controller directly rather than looking it up via the window.
        GeneratedPluginRegistrant.register(with: flutterViewController)

        nativeApplePlayerChannel = NativeApplePlayerChannel(
            messenger: flutterViewController.binaryMessenger,
            rootProvider: { [weak flutterViewController] in flutterViewController })
        topShelfChannel = TopShelfChannel(
            messenger: flutterViewController.binaryMessenger)
        previewChannel = AppleTvPreviewChannel(
            messenger: flutterViewController.binaryMessenger,
            textures: flutterViewController)
        systemChannel = AppleTvSystemChannel(
            messenger: flutterViewController.binaryMessenger,
            gamepadHost: gamepadHost)
        audioChannel = AppleTvAudioChannel(
            messenger: flutterViewController.binaryMessenger)
        themeMusicChannel = AppleTvThemeMusicChannel(
            messenger: flutterViewController.binaryMessenger)
        sfSymbolChannel = AppleTvSfSymbolChannel(
            messenger: flutterViewController.binaryMessenger)
        gameChannel = AppleTvGameChannel(
            messenger: flutterViewController.binaryMessenger,
            textures: flutterViewController,
            rootViewController: flutterViewController)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func deliverDeepLink(_ url: URL, isLaunch: Bool) {
        topShelfChannel?.deliverDeepLink(url, isLaunch: isLaunch)
    }

    func deliverSceneConnectionURLs(_ contexts: Set<UIOpenURLContext>) {
        for context in contexts {
            // A reconnected scene reuses the running engine, whose Dart side has
            // already consumed the initial link. Send those links as events.
            deliverDeepLink(context.url, isLaunch: !hasConnectedScene)
        }
        hasConnectedScene = true
    }
}

// Kept in the existing source file so adopting scenes needs no Xcode project
// changes (including developers' local signing settings).
class SceneDelegate: FlutterSceneDelegate {
    private var registeredEngine: FlutterEngine?

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
            let appDelegate = UIApplication.shared.delegate as? AppDelegate,
            let gamepadHost = appDelegate.gamepadHost
        else {
            super.scene(scene, willConnectTo: session, options: connectionOptions)
            return
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = gamepadHost
        self.window = window

        // The Flutter controller is nested inside the gamepad host, so associate
        // its engine explicitly before Flutter forwards scene events to plugins.
        let engine = gamepadHost.flutterViewController.engine
        registerSceneLifeCycle(with: engine)
        registeredEngine = engine

        appDelegate.deliverSceneConnectionURLs(connectionOptions.urlContexts)

        window.makeKeyAndVisible()
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            (UIApplication.shared.delegate as? AppDelegate)?.deliverDeepLink(
                context.url, isLaunch: false)
        }
    }

    override func sceneDidDisconnect(_ scene: UIScene) {
        super.sceneDidDisconnect(scene)
        if let engine = registeredEngine {
            unregisterSceneLifeCycle(with: engine)
            registeredEngine = nil
        }
        window?.rootViewController = nil
        window = nil
    }
}

@MainActor
final class AppleTvSfSymbolChannel: NSObject {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "moonfin/sf_symbols", binaryMessenger: messenger)
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "render",
            let args = call.arguments as? [String: Any],
            let name = args["name"] as? String
        else {
            result(FlutterMethodNotImplemented)
            return
        }
        let size = CGFloat(args["size"] as? Double ?? 18)
        let scale = CGFloat(args["scale"] as? Double ?? 2)
        let color = UIColor(
            red: CGFloat(args["r"] as? Double ?? 1),
            green: CGFloat(args["g"] as? Double ?? 1),
            blue: CGFloat(args["b"] as? Double ?? 1),
            alpha: CGFloat(args["a"] as? Double ?? 1))
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config) else {
            result(nil)
            return
        }
        let tinted = symbol.withTintColor(color, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: tinted.size, format: format)
        let data = renderer.pngData { _ in tinted.draw(at: .zero) }
        result(FlutterStandardTypedData(bytes: data))
    }
}
