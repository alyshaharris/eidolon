import UIKit
import RxSwift
import SVProgressHUD
import Action

extension UIViewController {
    func promptForBidderDetailsRetrieval() -> Observable<Void> {
        return deferred { () -> Observable<Void> in
            let alertController = self.emailPromptAlertController()

            self.presentViewController(alertController, animated: true) { }
            
            return empty()
        }
    }
    
    func retrieveBidderDetails(email: String) -> Observable<Void> {
        return just(email)
            .take(1)
            .doOnNext { _ in
                SVProgressHUD.show()
            }
            .flatMap { email -> Observable<Void> in
                let endpoint = ArtsyAPI.BidderDetailsNotification(auctionID: appDelegate().appViewController.sale.value.id, identifier: email)

                return XAppRequest(endpoint, provider: Provider.sharedProvider).filterSuccessfulStatusCodes().map(void)
            }
            .throttle(1, MainScheduler.sharedInstance)
            .doOnNext { _ in
                SVProgressHUD.dismiss()
                self.presentViewController(UIAlertController.successfulBidderDetailsAlertController(), animated: true, completion: nil)
            }
            .doOnError { _ in
                SVProgressHUD.dismiss()
                self.presentViewController(UIAlertController.failedBidderDetailsAlertController(), animated: true, completion: nil)
            }
    }

    func emailPromptAlertController() -> UIAlertController {
        let alertController = UIAlertController(title: "Send Bidder Details", message: "Enter your email address or phone number registered with Artsy and we will send your bidder number and PIN.", preferredStyle: .Alert)

        let ok = UIAlertAction.Action("OK", style: .Default)
        let action = CocoaAction { _ -> Observable<Void> in
            let text = (alertController.textFields?.first)?.text ?? ""

            return self.retrieveBidderDetails(text)
        }
        ok.rx_action = action
        let cancel = UIAlertAction.Action("Cancel", style: .Cancel)

        alertController.addTextFieldWithConfigurationHandler(nil)
        alertController.addAction(ok)
        alertController.addAction(cancel)

        return alertController
    }
}

extension UIAlertController {
    class func successfulBidderDetailsAlertController() -> UIAlertController {
        let alertController = self.init(title: "Your details have been sent", message: nil, preferredStyle: .Alert)
        alertController.addAction(UIAlertAction.Action("OK", style: .Default))
        
        return alertController
    }
    
    class func failedBidderDetailsAlertController() -> UIAlertController {
        let alertController = self.init(title: "Incorrect Email", message: "Email was not recognized. You may not be registered to bid yet.", preferredStyle: .Alert)
        alertController.addAction(UIAlertAction.Action("Cancel", style: .Cancel))
        
        let retryAction = UIAlertAction.Action("Retry", style: .Default)
        retryAction.rx_action = appDelegate().requestBidderDetailsCommand()
        
        alertController.addAction(retryAction)
        
        return alertController
    }
}