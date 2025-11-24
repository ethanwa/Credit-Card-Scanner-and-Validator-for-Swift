/*
 MIT License

 Copyright (c) 2021 Ethan C. Allen (ethanwa on GitHub)

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import UIKit

class ViewController: UIViewController, CCScannerDelegate {

    // Initialize the CC scanner
    let ccScanner = CCScanner()

    override func viewDidLoad() {
        super.viewDidLoad()

        // Set the CC scanner delegate to your view controller
        ccScanner.delegate = self
    }

    @IBAction func startButton() {

        // OPTIONAL: You can add custom cards for your company. Here is an example for Target
        /*
        let targetCard = ccScanner.createCardType.new(binRange: "639463",
                                                      lengthRange: "16")

        let amazonCard = ccScanner.createCardType.new(binRange: "604578",
                                                      lengthRange: "16")

        ccScanner.addCustomCards(cards: [targetCard, amazonCard])
        */

        // OPTIONAL: The more you narrow down your search, the faster you'll get results. Default is .all
        /*
        ccScanner.cards = [.visa,
                           .mastercard,
                           .americanExpress,
                           .custom]
        */

        // OPTIONAL: Choose between accuracy and speed
        // ccScanner.recognitionLevel = .fast

        // Start the CC scanner
        ccScanner.startScanner(viewController: self)
    }

    // MARK: - CCScannerDelegate

    // Called upon a completed successful scan
    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String) {
        // Do what you wish with the data
        print("Card Number: \(cardNumber)")
        print("Expiration Date: \(expDate)")
        print("Card Type: \(cardType)")
    }

    // Called when an error occurs during scanning (optional)
    func ccScannerError(_ error: CCScannerError) {
        // Handle the error appropriately
        let alert = UIAlertController(
            title: "Scanner Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // Called when the user cancels the scanner (optional)
    func ccScannerCancelled() {
        print("Scanner was cancelled by user")
    }
}
