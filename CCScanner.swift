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

import Foundation
import UIKit
import Vision
import Photos
import AVFoundation

/** Defines an interface for delegates of CCScannerDelegate to receive a valid credit card number, expiration date, and card type from a visible scan using the devices camera. */
protocol CCScannerDelegate: UIViewController {
    
    /** Called whenever a CCScannerDelegate instance validates a credit card number from a visual scan. */
    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String)
}

class CCScanner: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var delegate: CCScannerDelegate?
    var createCardType = Card()
    
    /** A list of the card types to check a visual scan of a card against. Default is all. */
    var cards = [CardType.all]
    
    /** The recognition level selects which techniques will be used during the text recognition. There are trade-offs between performance and accuracy. Default is normal.*/
    var recognitionLevel: RecognitionLevel?
    
    private let cardTypes = [
        
        CardType.visa:
            ["4" : "16-19"],
        
        CardType.mastercard:
            ["51-55" : "16",
             "2221-2720" : "16"],
        
        CardType.americanExpress:
            ["34" : "15",
             "37" : "15"],
        
        CardType.discover:
            ["6011" : "16-19",
             "622126-622925" : "16-19",
             "644-649" : "16-19",
             "65" : "16-19"],
        
        CardType.chinaTUnion:
            ["31" : "19"],
        
        CardType.chinaUnionPay:
            ["62" : "16-19"],
        
        CardType.dinersClubInternational:
            ["36" : "14-19"],
        
        // TODO: Missing UkrCard
        // 60400100 - 60420099 range is too large. 604 conflicts with RuPay.
        // Maybe enforce some search ordering.

        CardType.ruPay: ["60" : "15",
                         "6521-6522" : "16"],
        
        CardType.interPayment: ["636" : "16-19"],
        
        CardType.jcb: ["3528-3589" : "16-19"],
        
        CardType.maestroUK: ["6759" : "16-19",
                               "676770" : "12-19",
                               "676774" : "12-19"],
        
        CardType.maestro: ["5018" : "12-19",
                             "5020" : "12-19",
                             "5038" : "12-19",
                             "5893" : "12-19",
                             "6304" : "12-19",
                             "6759" : "12-19",
                             "6761" : "12-19",
                             "6762" : "12-19",
                             "6763" : "12-19"],
        
        CardType.dankort: ["5019" : "16"],
        
        CardType.mir: ["2200-2204" : "16"],
        
        CardType.npsPridnestrovie: ["6054740-6054744" : "16"],
        
        // TODO: Troy
        // CardType.troy: ["6-9" : "16],
        // Range is WAY too big to be included in .all
        
        CardType.utap: ["1" : "15"]
        
        // UNKNOWN VALIDATION
        // Verve, LankaPay
    ]
    
    enum CardType: String {
        case all
        case noneExceptCustom
        
        case visa = "Visa"
        case mastercard = "Mastercard"
        case americanExpress = "American Express"
        case discover = "Discover"
        case chinaTUnion = "China T-Union"
        case chinaUnionPay = "China Union Pay"
        case dinersClubInternational = "Diners Club International"
        //case ukrCard = "UkrCard"
        case ruPay = "RuPay"
        case interPayment = "Interpayment"
        case jcb = "JCB"
        case maestroUK = "Maestro UK"
        case maestro = "Maestro"
        case dankort = "Dankort"
        case mir = "MIR"
        case npsPridnestrovie = "NPS Pridnestrovie"
        //case troy = "Troy"
        case utap = "UTAP"
        case custom = "Custom Card"
    }
    
    enum RecognitionLevel {
        case fastest
        case fast
        case normal
        case accurate
        case veryaccurate
    }
    
    struct Card {
        var binRange = ""
        var lengthRange = ""
        
        /** Returns a custom Card by setting a custom BIN range and card number length. */
        mutating func new(binRange: String, lengthRange: String) -> Card {
            self.binRange = binRange
            self.lengthRange = lengthRange
            
            return self
        }
    }
    
    // MARK: - Standard Variables
    
    private let year = Calendar.current.component(.year, from: Date())
    private var usedCards = [CardType: [String: String]]()
    private var recognizedText = ""
    private var finalText = ""
    private var image: UIImage?
    private var processing = false
    private var findExp = false
    private var cardNumberDict = [String:Int]()
    private var cardExpDict = [String:Int]()
    private var cardExpPass = 0
    private var nagivationCont = UINavigationController()
    private var foundType: CardType?
    private var finalCardNumber = ""
    private var finalExpDate = ""
    private var finalName = ""
    private var ccPassLoops = 3
    private var expPassLoops = 3
    private var customCards = [String: String]()
    
    // MARK: - Card() Setup
    
    /** Add custom Cards to run a visual check against in a scan. */
    func addCustomCards(cards: Array<Card>) {
        for card in cards {
            self.customCards[card.binRange] = card.lengthRange
        }
    }
    
    func setupCardOptions() {
        self.ccPassLoops = 3
        self.expPassLoops = 4
        
        switch recognitionLevel {
        case .veryaccurate:
            self.ccPassLoops += 2
            self.expPassLoops += 2
            break
        case .accurate:
            self.ccPassLoops += 1
            self.expPassLoops += 1
            break
        case .normal:
            break
        case .fast:
            self.ccPassLoops -= 1
            self.expPassLoops -= 1
            break
        case .fastest:
            self.ccPassLoops -= 2
            self.expPassLoops -= 2
            break

        default:
            break
        }
        
        done: for card in cards {
            if card == .all {
                self.usedCards = self.cardTypes
                self.usedCards[CardType.custom] = self.customCards
                break done
            } else if card == .noneExceptCustom {
                self.usedCards.removeAll()
                self.usedCards[CardType.custom] = self.customCards
                break done
            } else if card == .custom {
                self.usedCards[CardType.custom] = self.customCards
            } else {
                self.usedCards[card] = self.cardTypes[card]
            }
        }
        
        
    }
    
    // MARK: - Vision
        
    private lazy var textDetectionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.020
        request.usesLanguageCorrection = false
        return request
    }()
    
    private let disQueue = DispatchQueue(label: "my.image.handling.queue")
    private var captureSession: AVCaptureSession?
    private lazy var previewLayer = AVCaptureVideoPreviewLayer()
    
    func startScanner(viewController: UIViewController)
    {
        self.setupCardOptions()
        
        self.captureSession = AVCaptureSession()
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession!)
        preview.videoGravity = .resizeAspect
        self.previewLayer = preview
        
        let screenSize = UIScreen.main.bounds
        let cardLayer = CAShapeLayer()
        cardLayer.frame = screenSize
        self.previewLayer.insertSublayer(cardLayer, above: self.previewLayer)
        
        let cardWidth = 350.0 as CGFloat
        let cardHeight = 225.0 as CGFloat
        let cardXlocation = (screenSize.width - cardWidth) / 2
        let cardYlocation = (screenSize.height / 2) - (cardHeight / 2) - (screenSize.height * 0.05)
        let path = UIBezierPath(roundedRect: CGRect(
                                    x: cardXlocation, y: cardYlocation, width: cardWidth, height: cardHeight),
                                cornerRadius: 10.0)
        cardLayer.path = path.cgPath
        cardLayer.strokeColor = UIColor.white.cgColor
        cardLayer.lineWidth = 8.0
        cardLayer.backgroundColor = UIColor.black.withAlphaComponent(0.7).cgColor
        
        let mask = CALayer()
        mask.frame = cardLayer.bounds
        cardLayer.mask = mask
        
        let r = UIGraphicsImageRenderer(size: mask.bounds.size)
        let im = r.image { ctx in
            UIColor.black.setFill()
            ctx.fill(mask.bounds)
            path.addClip()
            ctx.cgContext.clear(mask.bounds)
        }
        mask.contents = im.cgImage

        self.previewLayer.frame = screenSize

        self.addCameraInput()
        self.addVideoOutput()

        let viewCont = UIViewController()
        viewCont.view.backgroundColor = .black
        viewCont.view.frame = screenSize
        viewCont.title = "Card Scanner"
        viewCont.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.doneButton(_:)))
        self.nagivationCont = UINavigationController(rootViewController: viewCont)
        self.nagivationCont.modalPresentationStyle = .fullScreen
        viewController.present(self.nagivationCont, animated: true, completion: nil)
    
        viewCont.view.layer.addSublayer(self.previewLayer)

        self.disQueue.async {
            self.captureSession!.startRunning()
        }
    }

    private func addCameraInput() {
        let device = AVCaptureDevice.default(for: .video)!
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession!.addInput(cameraInput)
    }
    
    private func addVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        videoOutput.setSampleBufferDelegate(self, queue: self.disQueue)
        self.captureSession!.addOutput(videoOutput)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        if !processing
        {
            guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                debugPrint("unable to get image from sample buffer")
                return
            }
            
            self.processing = true
            
            let ciimage : CIImage = CIImage(cvPixelBuffer: frame)
            let theimage : UIImage = self.convert(cmage: ciimage)
            
            self.image = theimage
            self.processImage()
        }
    }
    
    private func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
    private func processImage()
    {
        guard let image = image, let cgImage = image.cgImage else { return }
        
        let requests = [textDetectionRequest]
        let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .right, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try imageRequestHandler.perform(requests)
            } catch let error {
                print("Error: \(error)")
            }
        }
    }
    
    private func callDelegate() {
        self.delegate?.ccScannerCompleted(cardNumber: self.finalCardNumber,
                                          expDate: self.finalExpDate,
                                          cardType: self.foundType?.rawValue ?? "error")
        self.closeCapture()
    }
    
    @objc func doneButton(_ sender: UIBarButtonItem) {
        self.closeCapture()
    }
    
    private func closeCapture()
    {
        self.finalCardNumber = ""
        self.finalExpDate = ""
        self.finalName = ""
        self.processing = false
        self.findExp = false
        self.cardExpPass = 0
        self.cardNumberDict = [String:Int]()
        self.cardExpDict = [String:Int]()
        self.textDetectionRequest.minimumTextHeight = 0.020
        self.disQueue.async {
            self.captureSession!.stopRunning()
            if let inputs = self.captureSession!.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    self.captureSession!.removeInput(input)
                }
            }
        }
        DispatchQueue.main.async {
            self.previewLayer.removeFromSuperlayer()
            self.nagivationCont.dismiss(animated: true, completion: nil)
        }
    }
    
    // MARK: - Handle the read text
    
    fileprivate func handleDetectedText(request: VNRequest?, error: Error?)
    {
        self.finalText = ""
        
        if let error = error {
            print(error.localizedDescription)
            self.processing = false
            return
        }
        guard let results = request?.results, results.count > 0 else {
            self.processing = false
            return
        }
        
        if let requestResults = request?.results as? [VNRecognizedTextObservation] {
            self.recognizedText = ""
            for observation in requestResults {
                guard let candidiate = observation.topCandidates(1).first else { return }
                self.recognizedText += candidiate.string
                self.recognizedText += " "
            }
            
            var cleanedText = self.cleanText(originalText: self.recognizedText)
            
            if self.findExp && self.cardExpPass < 7 {
                findExpDate(fullText: self.recognizedText)
            }
            else if self.findExp {
                print("NO EXP DATE FOUND")
                self.callDelegate()
            }
            else
            {
                cleanedText = cleanedText.filter("0123456789".contains)
                
                verify: for (type, details) in self.usedCards {
                    for cardRange in details {
                        let cardNums = self.getCardDict(stringRange: cardRange.key)
                        let cardLengths = self.getCardDict(stringRange: cardRange.value)
                        
                        for num in cardNums {
                            for len in cardLengths {
                                if self.findCC(fullText: cleanedText, startingNum: Int(num)!, lengthOfCard: Int(len)!) {
                                    self.foundType = type
                                    break verify
                                }
                            }
                        }
                    }
                }
            }
        }
        
        self.processing = false
    }
    
    private func getCardDict(stringRange: String) -> [String] {
        let cardNums = stringRange.components(separatedBy: "-")
        var finalCardNums = [String]()
        if cardNums.count > 1 {
            var cardCount = Int(cardNums[0])!
            finalCardNums.append(String(cardCount))
            repeat {
                cardCount += 1
                finalCardNums.append(String(cardCount))
            } while cardCount < Int(cardNums[1])!
        }
        else {
            finalCardNums.append(cardNums[0])
        }
        
        return finalCardNums
    }
    
    private func cleanText(originalText: String) -> String {
        var replaced = originalText.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        replaced = String(replaced.filter { !"\n\t\r".contains($0) })
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Exp Date
    
    private func findExpDate(fullText: String)
    {
        // looks for valid date for the next 20 years
        let expDate = fullText.regex(pattern: #"[0-1][0-9][\/][2-4][0-9]"#)
        
        if expDate.count > 0 {
            var finalDate = expDate[0]
            if expDate.count > 1 {
                var dates = [[String:Int]]()
                for ed in expDate {
                    let year = Int(ed.suffix(2))!
                    let month = Int(ed.prefix(2))!
                    dates.append(["month" : month, "year" : year])
                }
                let sortedDates = dates.sorted { $0["year"]! > $1["year"]! }
                
                finalDate = String(format:"%02d/%d", sortedDates[0]["month"]!, sortedDates[0]["year"]!)
            }
            
            if let expCount = self.cardExpDict[finalDate] {
                self.cardExpDict[finalDate]! = expCount + 1
            } else {
                self.cardExpDict[finalDate] = 0
            }
            
            if self.cardExpDict[finalDate]! > 3
            {
                //print("EXP DATE: ", finalDate)
                self.finalExpDate = finalDate
                self.callDelegate()
            }
        }
        
        self.cardExpPass += 1
    }
    
    // MARK: - Credit Card Number
    
    private func findCC(fullText: String, startingNum: Int, lengthOfCard: Int) -> Bool
    {
        if let numIndex = fullText.index(of: String(startingNum)) {
            let cardCheck = fullText[numIndex...]
            if cardCheck.count > lengthOfCard - 1 {
                return self.processCC(cardNumber: String(cardCheck))
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    private func processCC(cardNumber: String) -> Bool
    {
        let cardCheck = cardNumber[0..<16]
        let cardCheckRev = cardCheck.reversed().dropFirst()
        
        var testNum = 0
        
        // Luhn algorithm
        for (index, char) in cardCheckRev.enumerated() {
            if index % 2 == 0 {
                var num = Int(String(char))! * 2
                if num > 9 { num -= 9 }
                testNum += num
            } else {
                let num = Int(String(char))!
                testNum += num
            }
        }
        testNum += Int(String(cardCheck.last!))!
        if testNum % 10 == 0 {
            
            if let cardCount = self.cardNumberDict[cardCheck] {
                self.cardNumberDict[cardCheck]! = cardCount + 1
            } else {
                self.cardNumberDict[cardCheck] = 0
            }
            
            if self.cardNumberDict[cardCheck]! > self.ccPassLoops
            {
                //print("PASSED: ", cardCheck)
                self.finalCardNumber = cardCheck
                
                self.textDetectionRequest.minimumTextHeight = 0.01
                self.findExp = true
            }
            
            return true
        }
        else
        {
            return false
        }
    }
}

// MARK: - Extensions

extension String {
    
    func regex (pattern: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: NSRegularExpression.Options(rawValue: 0))
            let nsstr = self as NSString
            let all = NSRange(location: 0, length: nsstr.length)
            var matches : [String] = [String]()
            regex.enumerateMatches(in: self, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: all) {
                (result : NSTextCheckingResult?, _, _) in
                if let r = result {
                    let result = nsstr.substring(with: r.range) as String
                    matches.append(result)
                }
            }
            return matches
        } catch {
            return [String]()
        }
    }
    
    func indexInt(of char: Character) -> Int? {
        return firstIndex(of: char)?.utf16Offset(in: self)
    }
    
    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }
    
    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        return String(self[start...])
    }
}

extension StringProtocol {
    func index<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.lowerBound
    }
    func endIndex<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> Index? {
        range(of: string, options: options)?.upperBound
    }
    func indices<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Index] {
        ranges(of: string, options: options).map(\.lowerBound)
    }
    func ranges<S: StringProtocol>(of string: S, options: String.CompareOptions = []) -> [Range<Index>] {
        var result: [Range<Index>] = []
        var startIndex = self.startIndex
        while startIndex < endIndex,
            let range = self[startIndex...]
                .range(of: string, options: options) {
                result.append(range)
                startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                    index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}
