import UIKit
import Artsy_UILabels
import ARAnalytics
import RxSwift

class LoadingViewController: UIViewController {

    @IBOutlet weak var titleLabel: ARSerifLabel!
    @IBOutlet var bidDetailsPreviewView: BidDetailsPreviewView!

    @IBOutlet weak var statusMessage: ARSerifLabel!
    @IBOutlet weak var spinner: Spinner!
    @IBOutlet weak var bidConfirmationImageView: UIImageView!

    var placingBid = true

    var animate = true

    @IBOutlet weak var backToAuctionButton: SecondaryActionButton!
    @IBOutlet weak var placeHigherBidButton: ActionButton!

    private let _viewWillDisappear = PublishSubject<Void>()
    var viewWillDisappear: Observable<Void> {
        return self._viewWillDisappear.asObserver()
    }
    
    lazy var viewModel: LoadingViewModelType = {
        return LoadingViewModel(
            bidNetworkModel: BidderNetworkModel(fulfillmentController: self.fulfillmentNav()),
            placingBid: self.placingBid,
            actionsComplete: self.viewWillDisappear
        )
    }()

    lazy var recognizer = UITapGestureRecognizer()
    lazy var closeSelf: () -> Void = { [weak self] in
        self?.fulfillmentContainer()?.closeFulfillmentModal()
        return
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if placingBid  {
            bidDetailsPreviewView.bidDetails = viewModel.bidDetails
        } else {
            bidDetailsPreviewView.hidden = true
        }

        statusMessage.hidden = true
        backToAuctionButton.hidden = true
        placeHigherBidButton.hidden = true

        spinner.animate(animate)

        titleLabel.text = placingBid ? "Placing bid..." : "Registering..."

        // Either finishUp() or bidderError() are responsible for providing a way back to the auction.
        fulfillmentContainer()?.cancelButton.hidden = true

        // The view model will perform actions like registering a user if necessary,
        // placing a bid if requested, and polling for results.
        viewModel.performActions().subscribe(onNext: nil,
            onError: { [weak self] error in
                logger.log("Bidder error \(error)")
                self?.bidderError(error as NSError)
            },
            onCompleted: { [weak self] in
                logger.log("Bid placement and polling completed")
                self?.finishUp()
            },
            onDisposed: { [weak self] in
                // Regardless of error or completion. hide the spinner.
                self?.spinner.hidden = true
            })
            .addDisposableTo(rx_disposeBag)
    }

    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
        _viewWillDisappear.onNext()
    }

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue == .PushtoRegisterConfirmed {
            let detailsVC = segue.destinationViewController as! YourBiddingDetailsViewController
            detailsVC.confirmationImage = bidConfirmationImageView.image
        }

        if segue == .PlaceaHigherBidAfterNotBeingHighestBidder {
            let placeBidVC = segue.destinationViewController as! PlaceBidViewController
            placeBidVC.hasAlreadyPlacedABid = true
        }
    }
}

extension LoadingViewController {

    func finishUp() {
        let reserveNotMet = viewModel.reserveNotMet.value
        let isHighestBidder = viewModel.isHighestBidder.value
        let bidIsResolved = viewModel.bidIsResolved.value
        let createdNewBidder = viewModel.createdNewBidder.value

        logger.log("Bidding process result: reserveNotMet \(reserveNotMet), isHighestBidder \(isHighestBidder), bidIsResolved \(bidIsResolved), createdNewbidder \(createdNewBidder)")

        if placingBid {
            ARAnalytics.event("Placed a bid", withProperties: ["top_bidder" : isHighestBidder, "sale_artwork": viewModel.bidDetails.saleArtwork?.artwork.id ?? ""])

            if bidIsResolved {

                if reserveNotMet {
                    handleReserveNotMet()
                } else if isHighestBidder {
                    handleHighestBidder()
                } else {
                    handleLowestBidder()
                }

            } else {
                handleUnknownBidder()
            }

        } else { // Not placing bid
            if createdNewBidder { // Creating new user
                handleRegistered()
            } else { // Updating existing user
                handleUpdate()
            }
        }

        let showPlaceHigherButton = placingBid && (!isHighestBidder || reserveNotMet)
        placeHigherBidButton.hidden = !showPlaceHigherButton

        let showAuctionButton = showPlaceHigherButton || isHighestBidder || (!placingBid && !createdNewBidder)
        backToAuctionButton.hidden = !showAuctionButton

        let title = reserveNotMet ? "NO, THANKS" : (createdNewBidder ? "CONTINUE" : "BACK TO AUCTION")
        backToAuctionButton.setTitle(title, forState: .Normal)
    }

    func handleRegistered() {
        titleLabel.text = "Registration Complete"
        bidConfirmationImageView.image = UIImage(named: "BidHighestBidder")
        fulfillmentContainer()?.cancelButton.setTitle("DONE", forState: .Normal)
        interval(1, MainScheduler.sharedInstance)
            .take(1)
            .subscribeCompleted { [weak self] in
                self?.performSegue(.PushtoRegisterConfirmed)
            }
            .addDisposableTo(rx_disposeBag)
    }

    func handleUpdate() {
        titleLabel.text = "Updated your Information"
        bidConfirmationImageView.image = UIImage(named: "BidHighestBidder")
        fulfillmentContainer()?.cancelButton.setTitle("DONE", forState: .Normal)
    }

    func handleUnknownBidder() {
        titleLabel.text = "Bid Submitted"
        bidConfirmationImageView.image = UIImage(named: "BidHighestBidder")
    }

    func handleReserveNotMet() {
        titleLabel.text = "Reserve Not Met"
        statusMessage.hidden = false
        statusMessage.text = "Your bid is still below this lot's reserve. Please place a higher bid."
        bidConfirmationImageView.image = UIImage(named: "BidNotHighestBidder")
    }

    func handleHighestBidder() {
        titleLabel.text = "High Bid!"
        statusMessage.hidden = false
        statusMessage.text = "You are the high bidder for this lot."
        bidConfirmationImageView.image = UIImage(named: "BidHighestBidder")

        recognizer.rx_event.subscribeNext { [weak self] _ in
            self?.closeSelf()
        }.addDisposableTo(rx_disposeBag)

        bidConfirmationImageView.userInteractionEnabled = true
        bidConfirmationImageView.addGestureRecognizer(recognizer)

        fulfillmentContainer()?.cancelButton.setTitle("DONE", forState: .Normal)
    }

    func handleLowestBidder() {
        titleLabel.text = "Higher bid needed"
        titleLabel.textColor = .artsyRed()
        statusMessage.hidden = false
        statusMessage.text = "Another bidder has placed a higher maximum bid. Place a higher bid to secure the lot."
        bidConfirmationImageView.image = UIImage(named: "BidNotHighestBidder")
        placeHigherBidButton.hidden = false
    }

    // MARK: - Error Handling

    func bidderError(error: NSError) {
        if placingBid {
            // If you are bidding, we show a bidding error regardless of whether or not you're also registering.
            if error.domain == OutbidDomain {
                handleLowestBidder()
            } else {
                bidPlacementFailed(error)
            }
        } else {
            // If you're not placing a bid, you're here because you're just registering.
            presentError("Registration Failed", message: "There was a problem registering for the auction. Please speak to an Artsy representative.")
        }
    }

    func bidPlacementFailed(error: NSError? = nil) {
        presentError("Bid Failed", message: "There was a problem placing your bid. Please speak to an Artsy representative.")

        if let error = error {
            statusMessage.presentOnLongPress("Error: \(error.localizedDescription). \n \(error.artsyServerError())", title: "Bidding error") { [weak self] (alertController) in
                self?.presentViewController(alertController, animated: true, completion: nil)
            }
        }
    }

    func presentError(title: String, message: String) {
        titleLabel.textColor = .artsyRed()
        titleLabel.text = title
        statusMessage.text = message
        statusMessage.hidden = false
        backToAuctionButton.hidden = false
    }

    @IBAction func placeHigherBidTapped(sender: AnyObject) {
        self.fulfillmentNav().bidDetails.bidAmountCents.value = 0
        self.performSegue(.PlaceaHigherBidAfterNotBeingHighestBidder)
    }

    @IBAction func backToAuctionTapped(sender: AnyObject) {
        if viewModel.createdNewBidder.value {
            self.performSegue(.PushtoRegisterConfirmed)
        } else {
            closeSelf()
        }
    }
}
