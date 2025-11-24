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

// MARK: - Constants

private enum Constants {
    static let minTextHeight: CGFloat = 0.020
    static let minTextHeightDetail: CGFloat = 0.01
    static let cardOverlayWidth: CGFloat = 350.0
    static let cardOverlayHeight: CGFloat = 225.0
    static let cardCornerRadius: CGFloat = 10.0
    static let cardBorderWidth: CGFloat = 8.0
    static let overlayAlpha: CGFloat = 0.7
    static let verticalOffsetMultiplier: CGFloat = 0.05
    static let defaultCCPassLoops = 3
    static let defaultExpPassLoops = 4
    static let maxExpDateSearchAttempts = 7
    static let expDateConfirmationThreshold = 3
}

// MARK: - Delegate Protocol

/// Defines an interface for delegates of CCScannerDelegate to receive a valid credit card number, expiration date, and card type from a visible scan using the device's camera.
protocol CCScannerDelegate: UIViewController {
    /// Called whenever a CCScannerDelegate instance validates a credit card number from a visual scan.
    func ccScannerCompleted(cardNumber: String, expDate: String, cardType: String)

    /// Called when an error occurs during scanning. Optional - provides a default empty implementation.
    func ccScannerError(_ error: CCScannerError)

    /// Called when the user cancels the scanner. Optional - provides a default empty implementation.
    func ccScannerCancelled()
}

// Default implementations for optional delegate methods
extension CCScannerDelegate {
    func ccScannerError(_ error: CCScannerError) {}
    func ccScannerCancelled() {}
}

// MARK: - Error Types

enum CCScannerError: Error, LocalizedError {
    case cameraUnavailable
    case cameraPermissionDenied
    case cameraPermissionRestricted
    case cameraInputFailed(Error)
    case imageConversionFailed
    case unknownError(Error)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "Camera device is not available on this device"
        case .cameraPermissionDenied:
            return "Camera permission was denied. Please enable camera access in Settings."
        case .cameraPermissionRestricted:
            return "Camera access is restricted on this device"
        case .cameraInputFailed(let error):
            return "Failed to configure camera input: \(error.localizedDescription)"
        case .imageConversionFailed:
            return "Failed to convert camera image"
        case .unknownError(let error):
            return "An unknown error occurred: \(error.localizedDescription)"
        }
    }
}

// MARK: - Card Types

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
    case ruPay = "RuPay"
    case interPayment = "Interpayment"
    case jcb = "JCB"
    case maestroUK = "Maestro UK"
    case maestro = "Maestro"
    case dankort = "Dankort"
    case mir = "MIR"
    case npsPridnestrovie = "NPS Pridnestrovie"
    case utap = "UTAP"
    case custom = "Custom Card"
}

// MARK: - Recognition Level

enum RecognitionLevel {
    case fastest
    case fast
    case normal
    case accurate
    case veryAccurate
}

// MARK: - Card Structure

struct Card {
    var binRange = ""
    var lengthRange = ""

    /// Returns a custom Card by setting a custom BIN range and card number length.
    mutating func new(binRange: String, lengthRange: String) -> Card {
        self.binRange = binRange
        self.lengthRange = lengthRange
        return self
    }
}

// MARK: - CCScanner

class CCScanner: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Public Properties

    weak var delegate: CCScannerDelegate?
    var createCardType = Card()

    /// A list of the card types to check a visual scan of a card against. Default is all.
    var cards = [CardType.all]

    /// The recognition level selects which techniques will be used during the text recognition. There are trade-offs between performance and accuracy. Default is normal.
    var recognitionLevel: RecognitionLevel = .normal

    // MARK: - Card Type Definitions

    private let cardTypes: [CardType: [String: String]] = [
        .visa: ["4": "16-19"],
        .mastercard: ["51-55": "16", "2221-2720": "16"],
        .americanExpress: ["34": "15", "37": "15"],
        .discover: ["6011": "16-19", "622126-622925": "16-19", "644-649": "16-19", "65": "16-19"],
        .chinaTUnion: ["31": "19"],
        .chinaUnionPay: ["62": "16-19"],
        .dinersClubInternational: ["36": "14-19"],
        .ruPay: ["60": "15", "6521-6522": "16"],
        .interPayment: ["636": "16-19"],
        .jcb: ["3528-3589": "16-19"],
        .maestroUK: ["6759": "16-19", "676770": "12-19", "676774": "12-19"],
        .maestro: ["5018": "12-19", "5020": "12-19", "5038": "12-19", "5893": "12-19",
                   "6304": "12-19", "6759": "12-19", "6761": "12-19", "6762": "12-19", "6763": "12-19"],
        .dankort: ["5019": "16"],
        .mir: ["2200-2204": "16"],
        .npsPridnestrovie: ["6054740-6054744": "16"],
        .utap: ["1": "15"]
    ]

    // MARK: - Private Properties

    private let year = Calendar.current.component(.year, from: Date())
    private var usedCards = [CardType: [String: String]]()
    private var recognizedText = ""
    private var finalText = ""
    private var image: UIImage?
    private var findExp = false
    private var cardNumberDict = [String: Int]()
    private var cardExpDict = [String: Int]()
    private var cardExpPass = 0
    private var navigationController_: UINavigationController?
    private var foundType: CardType?
    private var finalCardNumber = ""
    private var finalExpDate = ""
    private var finalName = ""
    private var ccPassLoops = Constants.defaultCCPassLoops
    private var expPassLoops = Constants.defaultExpPassLoops
    private var customCards = [String: String]()
    private var currentCardLength = 16

    // Thread safety
    private let processingLock = NSLock()
    private var _processing = false
    private var processing: Bool {
        get {
            processingLock.lock()
            defer { processingLock.unlock() }
            return _processing
        }
        set {
            processingLock.lock()
            defer { processingLock.unlock() }
            _processing = newValue
        }
    }

    // Pre-compiled regex for expiration date matching (MM/YY format for next ~20 years)
    private lazy var expDateRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"(0[1-9]|1[0-2])[\/](2[4-9]|3[0-9]|4[0-9])"#, options: [])
    }()

    // MARK: - Vision Components

    private lazy var textDetectionRequest: VNRecognizeTextRequest = {
        let request = VNRecognizeTextRequest(completionHandler: self.handleDetectedText)
        request.recognitionLevel = .accurate
        request.minimumTextHeight = Constants.minTextHeight
        request.usesLanguageCorrection = false
        return request
    }()

    private let dispatchQueue = DispatchQueue(label: "com.ccscanner.image.handling.queue")
    private var captureSession: AVCaptureSession?
    private lazy var previewLayer = AVCaptureVideoPreviewLayer()

    // MARK: - Lifecycle

    deinit {
        clearSensitiveData()
    }

    private func clearSensitiveData() {
        cardNumberDict.removeAll()
        cardExpDict.removeAll()
        recognizedText = ""
        finalCardNumber = ""
        finalExpDate = ""
        finalName = ""
        finalText = ""
    }

    // MARK: - Custom Cards Setup

    /// Add custom Cards to run a visual check against in a scan.
    func addCustomCards(cards: Array<Card>) {
        for card in cards {
            guard !card.binRange.isEmpty, !card.lengthRange.isEmpty else { continue }
            self.customCards[card.binRange] = card.lengthRange
        }
    }

    private func setupCardOptions() {
        ccPassLoops = Constants.defaultCCPassLoops
        expPassLoops = Constants.defaultExpPassLoops

        switch recognitionLevel {
        case .veryAccurate:
            ccPassLoops += 2
            expPassLoops += 2
        case .accurate:
            ccPassLoops += 1
            expPassLoops += 1
        case .normal:
            break
        case .fast:
            ccPassLoops -= 1
            expPassLoops -= 1
        case .fastest:
            ccPassLoops -= 2
            expPassLoops -= 2
        }

        for card in cards {
            switch card {
            case .all:
                usedCards = cardTypes
                usedCards[.custom] = customCards
                return
            case .noneExceptCustom:
                usedCards.removeAll()
                usedCards[.custom] = customCards
                return
            case .custom:
                usedCards[.custom] = customCards
            default:
                usedCards[card] = cardTypes[card]
            }
        }
    }

    // MARK: - Scanner Control

    func startScanner(viewController: UIViewController) {
        checkCameraPermission { [weak self] granted in
            guard let self = self else { return }

            if granted {
                DispatchQueue.main.async {
                    self.initializeScanner(viewController: viewController)
                }
            } else {
                DispatchQueue.main.async {
                    self.delegate?.ccScannerError(.cameraPermissionDenied)
                }
            }
        }
    }

    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        case .denied:
            delegate?.ccScannerError(.cameraPermissionDenied)
            completion(false)
        case .restricted:
            delegate?.ccScannerError(.cameraPermissionRestricted)
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    private func initializeScanner(viewController: UIViewController) {
        setupCardOptions()

        captureSession = AVCaptureSession()

        guard let session = captureSession else { return }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        previewLayer = preview

        let screenSize = UIScreen.main.bounds
        setupCardOverlay(screenSize: screenSize)

        previewLayer.frame = screenSize

        guard addCameraInput() else { return }
        addVideoOutput()

        presentScannerUI(viewController: viewController, screenSize: screenSize)

        dispatchQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    private func setupCardOverlay(screenSize: CGRect) {
        let cardLayer = CAShapeLayer()
        cardLayer.frame = screenSize
        previewLayer.insertSublayer(cardLayer, above: previewLayer)

        let cardXLocation = (screenSize.width - Constants.cardOverlayWidth) / 2
        let cardYLocation = (screenSize.height / 2) - (Constants.cardOverlayHeight / 2) - (screenSize.height * Constants.verticalOffsetMultiplier)

        let path = UIBezierPath(
            roundedRect: CGRect(x: cardXLocation, y: cardYLocation,
                              width: Constants.cardOverlayWidth, height: Constants.cardOverlayHeight),
            cornerRadius: Constants.cardCornerRadius
        )

        cardLayer.path = path.cgPath
        cardLayer.strokeColor = UIColor.white.cgColor
        cardLayer.lineWidth = Constants.cardBorderWidth
        cardLayer.backgroundColor = UIColor.black.withAlphaComponent(Constants.overlayAlpha).cgColor

        let mask = CALayer()
        mask.frame = cardLayer.bounds
        cardLayer.mask = mask

        let renderer = UIGraphicsImageRenderer(size: mask.bounds.size)
        let maskImage = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(mask.bounds)
            path.addClip()
            ctx.cgContext.clear(mask.bounds)
        }
        mask.contents = maskImage.cgImage
    }

    private func presentScannerUI(viewController: UIViewController, screenSize: CGRect) {
        let scannerVC = UIViewController()
        scannerVC.view.backgroundColor = .black
        scannerVC.view.frame = screenSize
        scannerVC.title = "Card Scanner"
        scannerVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneButton(_:))
        )

        let navController = UINavigationController(rootViewController: scannerVC)
        navController.modalPresentationStyle = .fullScreen
        navigationController_ = navController

        viewController.present(navController, animated: true, completion: nil)
        scannerVC.view.layer.addSublayer(previewLayer)
    }

    @discardableResult
    private func addCameraInput() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.ccScannerError(.cameraUnavailable)
            return false
        }

        do {
            let cameraInput = try AVCaptureDeviceInput(device: device)
            captureSession?.addInput(cameraInput)
            return true
        } catch {
            delegate?.ccScannerError(.cameraInputFailed(error))
            return false
        }
    }

    private func addVideoOutput() {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as NSString): NSNumber(value: kCVPixelFormatType_32BGRA)
        ] as [String: Any]
        videoOutput.setSampleBufferDelegate(self, queue: dispatchQueue)
        captureSession?.addOutput(videoOutput)
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !processing else { return }

        guard let frame = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            debugPrint("Unable to get image from sample buffer")
            return
        }

        processing = true

        let ciImage = CIImage(cvPixelBuffer: frame)

        guard let convertedImage = convert(ciImage: ciImage) else {
            delegate?.ccScannerError(.imageConversionFailed)
            processing = false
            return
        }

        image = convertedImage
        processImage()
    }

    private func convert(ciImage: CIImage) -> UIImage? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func processImage() {
        guard let image = image, let cgImage = image.cgImage else {
            processing = false
            return
        }

        let requests = [textDetectionRequest]
        let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage, orientation: .right, options: [:])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try imageRequestHandler.perform(requests)
            } catch {
                print("Vision error: \(error)")
                self?.processing = false
            }
        }
    }

    // MARK: - Scanner Actions

    @objc private func doneButton(_ sender: UIBarButtonItem) {
        delegate?.ccScannerCancelled()
        closeCapture()
    }

    private func callDelegate() {
        delegate?.ccScannerCompleted(
            cardNumber: finalCardNumber,
            expDate: finalExpDate,
            cardType: foundType?.rawValue ?? "Unknown"
        )
        closeCapture()
    }

    private func closeCapture() {
        clearSensitiveData()
        processing = false
        findExp = false
        cardExpPass = 0
        textDetectionRequest.minimumTextHeight = Constants.minTextHeight

        dispatchQueue.async { [weak self] in
            guard let self = self, let session = self.captureSession else { return }

            session.stopRunning()

            if let inputs = session.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    session.removeInput(input)
                }
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.previewLayer.removeFromSuperlayer()
            self?.navigationController_?.dismiss(animated: true, completion: nil)
            self?.navigationController_ = nil
        }
    }

    // MARK: - Text Detection Handler

    private func handleDetectedText(request: VNRequest?, error: Error?) {
        finalText = ""

        if let error = error {
            print("Text detection error: \(error.localizedDescription)")
            processing = false
            return
        }

        guard let results = request?.results, !results.isEmpty else {
            processing = false
            return
        }

        guard let requestResults = results as? [VNRecognizedTextObservation] else {
            processing = false
            return
        }

        recognizedText = ""
        for observation in requestResults {
            guard let candidate = observation.topCandidates(1).first else { continue }
            recognizedText += candidate.string
            recognizedText += " "
        }

        var cleanedText = cleanText(originalText: recognizedText)

        if findExp && cardExpPass < Constants.maxExpDateSearchAttempts {
            findExpDate(fullText: recognizedText)
        } else if findExp {
            print("No expiration date found after \(Constants.maxExpDateSearchAttempts) attempts")
            callDelegate()
        } else {
            cleanedText = cleanedText.filter { "0123456789".contains($0) }

            for (type, details) in usedCards {
                var found = false
                for cardRange in details {
                    let cardNums = getCardRange(stringRange: cardRange.key)
                    let cardLengths = getCardRange(stringRange: cardRange.value)

                    for num in cardNums {
                        for len in cardLengths {
                            guard let numInt = Int(num), let lenInt = Int(len) else { continue }
                            if findCC(fullText: cleanedText, startingNum: numInt, lengthOfCard: lenInt) {
                                foundType = type
                                currentCardLength = lenInt
                                found = true
                                break
                            }
                        }
                        if found { break }
                    }
                    if found { break }
                }
                if found { break }
            }
        }

        processing = false
    }

    private func getCardRange(stringRange: String) -> [String] {
        let parts = stringRange.components(separatedBy: "-")
        var result = [String]()

        if parts.count > 1, let start = Int(parts[0]), let end = Int(parts[1]) {
            for value in start...end {
                result.append(String(value))
            }
        } else {
            result.append(parts[0])
        }

        return result
    }

    private func cleanText(originalText: String) -> String {
        let charactersToRemove = CharacterSet(charactersIn: "- .\n\t\r")
        return originalText.components(separatedBy: charactersToRemove).joined()
    }

    // MARK: - Expiration Date Detection

    private func findExpDate(fullText: String) {
        guard let regex = expDateRegex else {
            cardExpPass += 1
            return
        }

        let nsString = fullText as NSString
        let range = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: fullText, options: [], range: range)

        let expDates = matches.compactMap { result -> String? in
            guard result.range.location != NSNotFound else { return nil }
            return nsString.substring(with: result.range)
        }

        guard !expDates.isEmpty else {
            cardExpPass += 1
            return
        }

        var finalDate = expDates[0]

        if expDates.count > 1 {
            // Find the date furthest in the future
            let currentYear = Calendar.current.component(.year, from: Date()) % 100
            let currentMonth = Calendar.current.component(.month, from: Date())

            var validDates: [(date: String, month: Int, year: Int)] = []

            for dateStr in expDates {
                let components = dateStr.split(separator: "/")
                guard components.count == 2,
                      let month = Int(components[0]),
                      let year = Int(components[1]),
                      month >= 1, month <= 12 else { continue }

                // Check if the date is in the future
                if year > currentYear || (year == currentYear && month >= currentMonth) {
                    validDates.append((date: dateStr, month: month, year: year))
                }
            }

            // Sort by year descending, then month descending
            validDates.sort { ($0.year, $0.month) > ($1.year, $1.month) }

            if let firstValid = validDates.first {
                finalDate = firstValid.date
            }
        }

        // Validate the date is actually in the future
        let components = finalDate.split(separator: "/")
        if components.count == 2,
           let month = Int(components[0]),
           let year = Int(components[1]),
           month >= 1, month <= 12 {

            let currentYear = Calendar.current.component(.year, from: Date()) % 100
            let currentMonth = Calendar.current.component(.month, from: Date())

            let isValidFutureDate = year > currentYear || (year == currentYear && month >= currentMonth)

            if isValidFutureDate {
                if let expCount = cardExpDict[finalDate] {
                    cardExpDict[finalDate] = expCount + 1
                } else {
                    cardExpDict[finalDate] = 1
                }

                if let count = cardExpDict[finalDate], count > Constants.expDateConfirmationThreshold {
                    finalExpDate = finalDate
                    callDelegate()
                    return
                }
            }
        }

        cardExpPass += 1
    }

    // MARK: - Credit Card Number Detection

    private func findCC(fullText: String, startingNum: Int, lengthOfCard: Int) -> Bool {
        let startingNumStr = String(startingNum)

        guard let numIndex = fullText.index(of: startingNumStr) else {
            return false
        }

        let cardCheck = fullText[numIndex...]

        guard cardCheck.count >= lengthOfCard else {
            return false
        }

        return processCC(cardNumber: String(cardCheck), lengthOfCard: lengthOfCard)
    }

    private func processCC(cardNumber: String, lengthOfCard: Int) -> Bool {
        guard cardNumber.count >= lengthOfCard else { return false }

        let cardCheck = String(cardNumber.prefix(lengthOfCard))

        // Verify all characters are digits
        guard cardCheck.allSatisfy({ $0.isNumber }) else { return false }

        // Luhn algorithm validation
        guard validateLuhn(cardNumber: cardCheck) else { return false }

        if let cardCount = cardNumberDict[cardCheck] {
            cardNumberDict[cardCheck] = cardCount + 1
        } else {
            cardNumberDict[cardCheck] = 1
        }

        if let count = cardNumberDict[cardCheck], count > ccPassLoops {
            finalCardNumber = cardCheck
            textDetectionRequest.minimumTextHeight = Constants.minTextHeightDetail
            findExp = true
        }

        return true
    }

    private func validateLuhn(cardNumber: String) -> Bool {
        let digits = cardNumber.compactMap { $0.wholeNumberValue }
        guard digits.count == cardNumber.count else { return false }

        var sum = 0
        let reversedDigits = digits.reversed()

        for (index, digit) in reversedDigits.enumerated() {
            if index % 2 == 1 {
                var doubled = digit * 2
                if doubled > 9 {
                    doubled -= 9
                }
                sum += doubled
            } else {
                sum += digit
            }
        }

        return sum % 10 == 0
    }
}

// MARK: - String Extensions

extension String {
    func regex(pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = self as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var matches = [String]()

        regex.enumerateMatches(in: self, options: [], range: range) { result, _, _ in
            if let r = result {
                matches.append(nsString.substring(with: r.range))
            }
        }

        return matches
    }

    func indexInt(of char: Character) -> Int? {
        return firstIndex(of: char)?.utf16Offset(in: self)
    }

    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound, range.upperBound - range.lowerBound))
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
              let range = self[startIndex...].range(of: string, options: options) {
            result.append(range)
            startIndex = range.lowerBound < range.upperBound ? range.upperBound :
                index(range.lowerBound, offsetBy: 1, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}
