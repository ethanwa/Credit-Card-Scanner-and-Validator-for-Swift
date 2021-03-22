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
    
    @IBOutlet var lblCardNumber: UILabel!
    @IBOutlet var lblCardExp: UILabel!
    @IBOutlet var lblCardType: UILabel!
    
    // Initialize the CC scanner
    let ccScanner = CCScanner()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the CC scanner delegate to your view controller
        self.ccScanner.delegate = self
    }
    
    @IBAction func startButton() {
        
        // OPTIONAL: You can add custom cards for your company. Here is an example for Target
        let targetCardRangeOne = self.ccScanner.createCardType.new(binRange: "639463",
                                                           lengthRange: "16")
        
        let targetCardRangeTwo = self.ccScanner.createCardType.new(binRange: "0023-0024",
                                                           lengthRange: "12-13")
        
        self.ccScanner.addCustomCards(cards: [targetCardRangeOne, targetCardRangeTwo])
        
        // OPTIONAL: The more you narrow down your search, the faster you'll get results. Default is .all
        self.ccScanner.cards = [.visa,
                                .mastercard,
                                .americanExpress,
                                .custom]
        
        // OPTIONAL: Choose between accuracy and speed
        self.ccScanner.recognitionLevel = .normal
        
        // Start the CC scanner
        self.ccScanner.startScanner(viewController: self)
    }
    
    // This delegate callback function is called upon a completed successful scan
    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String) {
        
        // Do what you wish with the data. UI changes need to be on the main thread
        DispatchQueue.main.async {
            self.lblCardNumber.text = cardNumber
            self.lblCardExp.text = expDate
            self.lblCardType.text = cardType
        }
    }
}

