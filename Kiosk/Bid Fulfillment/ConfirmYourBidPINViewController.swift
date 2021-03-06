import UIKit
import Moya
import RxSwift
import Action

class ConfirmYourBidPINViewController: UIViewController {

    private var _pin = Variable("")

    @IBOutlet var keypadContainer: KeypadContainerView!
    @IBOutlet var pinTextField: TextField!
    @IBOutlet var confirmButton: Button!
    @IBOutlet var bidDetailsPreviewView: BidDetailsPreviewView!

    lazy var pin: Observable<String> = { self.keypadContainer.stringValue }()
    
    lazy var provider: RxMoyaProvider<ArtsyAPI> = Provider.sharedProvider

    class func instantiateFromStoryboard(storyboard: UIStoryboard) -> ConfirmYourBidPINViewController {
        return storyboard.viewControllerWithID(.ConfirmYourBidPIN) as! ConfirmYourBidPINViewController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pin
            .bindTo(_pin)
            .addDisposableTo(rx_disposeBag)

        pin
            .bindTo(pinTextField.rx_text)
            .addDisposableTo(rx_disposeBag)

        pin
            .mapToOptional()
            .bindTo(fulfillmentNav().bidDetails.bidderPIN)
            .addDisposableTo(rx_disposeBag)
        
        let pinExists = pin.map { $0.isNotEmpty }

        bidDetailsPreviewView.bidDetails = fulfillmentNav().bidDetails

        /// verify if we can connect with number & pin

        confirmButton.rx_action = CocoaAction(enabledIf: pinExists) { [weak self] _ in
            guard let me = self else { return empty() }

            let phone = me.fulfillmentNav().bidDetails.newUser.phoneNumber.value ?? ""

            let loggedInProvider = me.providerForPIN(me._pin.value, number: phone)

            return loggedInProvider
                .request(ArtsyAPI.Me)
                .filterSuccessfulStatusCodes()
                .map(void)
                .doOnNext { _ in
                    // If the request to ArtsyAPI.Me succeeds, we have logged in and can use this provider.
                    self?.fulfillmentNav().loggedInProvider = loggedInProvider
                }.then {
                    // We want to put the data we've collected up to the server.
                    self?.fulfillmentNav().updateUserCredentials()
                }.then {
                    // This looks for credit cards on the users account, and sends them on the observable
                    return self?
                        .checkForCreditCard()
                        .doOnNext { (cards) in

                            // If the cards list doesn't exist, or its empty, then perform the segue to collect one.
                            // Otherwise, proceed directly to the loading view controller to place the bid.
                            if cards.isEmpty {
                                self?.performSegue(.ArtsyUserviaPINHasNotRegisteredCard)
                            } else {
                                self?.performSegue(.PINConfirmedhasCard)
                            }
                        }
                        .map(void)
                }
                .doOnError { [weak self] error in
                    if let response = (error as NSError).userInfo["data"] as? MoyaResponse {
                        let responseBody = NSString(data: response.data, encoding: NSUTF8StringEncoding)
                        print("Error authenticating(\(response.statusCode)): \(responseBody)")
                    }

                    self?.showAuthenticationError()
                }
        }
    }

    @IBAction func forgotPINTapped(sender: AnyObject) {
        let auctionID = fulfillmentNav().auctionID
        let number = fulfillmentNav().bidDetails.newUser.phoneNumber.value ?? ""
        let endpoint: ArtsyAPI = ArtsyAPI.BidderDetailsNotification(auctionID: auctionID, identifier: number)

        let alertController = UIAlertController(title: "Forgot PIN", message: "We have sent your bidder details to your device.", preferredStyle: .Alert)

        let cancelAction = UIAlertAction(title: "Back", style: .Cancel) { (_) in }
        alertController.addAction(cancelAction)

        self.presentViewController(alertController, animated: true) {}

        XAppRequest(endpoint, provider: Provider.sharedProvider)
            .filterSuccessfulStatusCodes()
            .subscribeNext { _ in

                // Necessary to subscribe to the actual observable. This should be in a CocoaAction of the button, instead.
                logger.log("Sent forgot PIN request")
            }
            .addDisposableTo(rx_disposeBag)
    }

    func providerForPIN(pin: String, number: String) -> RxMoyaProvider<ArtsyAPI> {
        let newEndpointsClosure = { (target: ArtsyAPI) -> Endpoint<ArtsyAPI> in
            // Grab existing endpoint to piggy-back off of any existing configurations being used by the sharedprovider.
            let endpoint = Provider.sharedProvider.endpointClosure(target)

            let auctionID = self.fulfillmentNav().auctionID
            return endpoint.endpointByAddingParameters(["auction_pin": pin, "number": number, "sale_id": auctionID])
        }

        return RxMoyaProvider(endpointClosure: newEndpointsClosure, requestClosure: endpointResolver(), stubClosure: Provider.APIKeysBasedStubBehaviour, plugins: Provider.plugins)

    }

    func showAuthenticationError() {
        confirmButton.flashError("Wrong PIN")
        pinTextField.flashForError()
        keypadContainer.resetAction.execute()
    }

    func checkForCreditCard() -> Observable<[Card]> {
        let endpoint: ArtsyAPI = ArtsyAPI.MyCreditCards
        let authProvider = self.fulfillmentNav().loggedInProvider!
        return authProvider.request(endpoint).filterSuccessfulStatusCodes().mapJSON().mapToObjectArray(Card.self)
    }
}

private extension ConfirmYourBidPINViewController {
    @IBAction func dev_loggedInTapped(sender: AnyObject) {
        self.performSegue(.PINConfirmedhasCard)
    }
}