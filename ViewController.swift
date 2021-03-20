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
import Vision
import Photos
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // Higher for accuracy, lower for speed
    let ccPassLoops = 3
    let expPassLoops = 3
    
    
    // Prefix : Card Length
    let cardTypes = [
        
        // Visa - Including related/partner brands: Dankort, Electron, etc. Note: majority of Visa cards are 16 digits, few old Visa cards may have 13 digits, and Visa is introducing 19 digits cards
        "4" : "16-19",
        
        // Mastercard
        "51-55" : "16",
        "2221-2720" : "16",
        
        // American Express
        "34" : "15",
        "37" : "15",
        
        // Discover
        "6011" : "16-19",
        "622126-622925" : "16-19",
        "624000-626999" : "16-19",
        "628200-628899" : "16-19",
        "64" : "16-19",
        "65" : "16-19"
        
    ]
    
    // MARK: - Standard Variables
    
    let year = Calendar.current.component(.year, from: Date())
    var recognizedText = ""
    var finalText = ""
    var image: UIImage?
    var processing = false
    var findExp = false
    var allCardTypes = [[String:String]]()
    var cardNumberDict = [String:Int]()
    var cardExpDict = [String:Int]()
    var cardExpPass = 0
    
    // MARK: - Vision
    
    lazy var textDetectionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        request.recognitionLevel = .accurate
        request.minimumTextHeight = 0.02
        request.usesLanguageCorrection = false
        return request
    }()
    
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
        preview.videoGravity = .resizeAspect
        return preview
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        for card in cardTypes {
            let cardNums = self.getCardDict(stringRange: card.key)
            let cardLengths = self.getCardDict(stringRange: card.value)
            
            for num in cardNums {
                for len in cardLengths {
                    self.allCardTypes.append([num : len])
                }
            }
        }
        
        self.addCameraInput()
        self.addVideoOutput()
    }
    
    private func addCameraInput() {
        let device = AVCaptureDevice.default(for: .video)!
        let cameraInput = try! AVCaptureDeviceInput(device: device)
        self.captureSession.addInput(cameraInput)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.bounds
    }
    
    private func addVideoOutput() {
        self.videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]
        self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "my.image.handling.queue"))
        self.captureSession.addOutput(self.videoOutput)
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
            processImage()
        }
    }
    
    func convert(cmage:CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cmage, from: cmage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
    func processImage()
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
    
    func closeCapture()
    {
        self.processing = false
        self.findExp = false
        self.cardExpPass = 0
        self.cardNumberDict = [String:Int]()
        self.cardExpDict = [String:Int]()
        self.textDetectionRequest.minimumTextHeight = 0.02
        self.captureSession.stopRunning()
        DispatchQueue.main.async {
            self.previewLayer.removeFromSuperlayer()
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
            
            let cleanedText = self.cleanText(originalText: self.recognizedText)
            
            if self.findExp && self.cardExpPass < 7 {
                findExpDate(fullText: self.recognizedText)
            }
            else if self.findExp {
                print("NO EXP DATE FOUND")
                self.closeCapture()
            }
            else
            {
                for card in self.allCardTypes {
                    
                    let start = Int(Array(card.keys)[0])!
                    let length = Int(Array(card.values)[0])!
                    
                    if self.findCC(fullText: cleanedText, startingNum: start, lengthOfCard: length) {
                        break
                    }
                }
            }
        }
        
        self.processing = false
    }
    
    func getCardDict(stringRange: String) -> [String] {
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
    
    func cleanText(originalText: String) -> String {
        var replaced = originalText.replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        replaced = String(replaced.filter { !"\n\t\r".contains($0) })
        return replaced.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Exp Date
    
    func findExpDate(fullText: String)
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
                print("EXP DATE: ", finalDate)
                self.closeCapture()
            }
        }
        
        self.cardExpPass += 1
    }
    
    // MARK: - Credit Card Number
    
    func findCC(fullText: String, startingNum: Int, lengthOfCard: Int) -> Bool
    {
        let result = fullText.filter("0123456789".contains)
        if let numIndex = result.indexInt(of: Character(UnicodeScalar(startingNum)!)) {
            let cardCheck = result[numIndex...]
            if cardCheck.count > lengthOfCard - 1 {
                return self.processCC(cardNumber: cardCheck)
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    func processCC(cardNumber: String) -> Bool
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
                print("PASSED: ", cardCheck)
                
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
    
    // MARK: - Buttons
    
    @IBAction func takePhoto(_ sender: Any) {
        self.view.layer.addSublayer(self.previewLayer)
        self.captureSession.startRunning()
    }
    
    @IBAction func choosePhoto(_ sender: Any) {
        presentPhotoPicker(type: .photoLibrary)
    }
    
    fileprivate func presentPhotoPicker(type: UIImagePickerController.SourceType) {
        let controller = UIImagePickerController()
        controller.sourceType = type
        controller.delegate = self
        present(controller, animated: true, completion: nil)
    }
}

// MARK: - Extensions

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        dismiss(animated: true, completion: nil)
        image = info[.originalImage] as? UIImage
        processImage()
    }
}

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
