import UIKit
import SwiftUI
import Reachability
import AppTrackingTransparency
import UIKit
import Dxozue

class PPRootViewController: UIViewController {

    private let hostingController: UIHostingController<AnyView>
    init() {

        self.hostingController = UIHostingController(rootView: AnyView(
            ContentView()))

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            ATTrackingManager.requestTrackingAuthorization {_ in }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        hostingController.view.backgroundColor = .black
        addChild(hostingController)

        view.addSubview(hostingController.view)
        
        let iuas = UIImageView()
        iuas.frame = UIScreen.main.bounds
        iuas.image = UIImage(named: "pingpongback")
        iuas.contentMode = .scaleAspectFill
        iuas.tag = 876
        view.addSubview(iuas)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
        
        let duye = try! Reachability()
        duye.whenReachable = { reachability in
            let iis = CycleCore()
            iis.conductAction(.experiment)
            duye.stopNotifier()
        }
        do {
            try duye.startNotifier()
        } catch {}
        
    }

}
