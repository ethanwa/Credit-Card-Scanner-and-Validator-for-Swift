# Credit and Debit Card Scanner and Validator
Requires iOS 13 or above.

Uses the iOS Vision text recognizer framework to visually read credit and debit card numbers and expiration dates. During the recognition process, it uses the Luhn algorithm to make sure the CC number is valid. It also checks agains a list of prefix numbers to determine card type (Mastercard, Visa, Discover, Amex, etc).

This is a very early 0.1 development version.

## How to Use

It's very simple to use this ViewController.swift file to demo how the code works. You can then modify it as needed. Simply connect a button to `@IBAction func takePhoto` (to use the live camera), run the app and touch the button, and hold up the credit card side showing the numbers to the camera view. In the Xcode console you will see a valid credit card number and expiration date (if it can find one). You can then modify the code to do what you wish with that information.

## Options

* If you want to increase the speed of detection, or decrease the speed but improve accuracy, you can adjust how many positive detections of the same number are needed before being given a positive passing result. Do this by adjusting the `ccPassLoops` and `expPassLoops` variables at the beginning of the file.

* If you'd like to add more credit card types from around the world, you can do so by modifying the `cardTypes` variable. You can put ranges of numbers to check against. These numbers must follow the Luhn algorithm for verifying check digits. Over time I will be adding all of the major worldwide card issuers.

## Current Known Limitations, Issues, and Extra Details

* As stated in the Options section, not all worldwide credit/debit card issuers are included yet.

* During my testing I was able to get about 99% accuracy, but every now and then there could be a false positive based on the number arrangement, the numbers in the CCV, and other small text on the back of the card, which could by just pure luck of the number ordering could pass the validation check. This is because the code scans the entire image and doesn't break the text down into text blocks using Vision. There is room for improvement here, but overall the accuracy is quite good as it is.

* With experations dates, some cards list multiple dates throughout the text for various reasons. The code does its best to scan above a certain fractional height of the total image to pull out the correct date using `.minimumTextHeight`, but sometimes that doesn't work all of the time. I added a few extra checks against past (meaning you can't get the Exp Date of an old card) and future dates (it won't get a date more than 20 years in the current future), and then sort remaining dates by most in the future first, and then use that date. It's a bit of guess work to narrow down the best possible choice.

* This code will not work with cards that have a full 4-digit year as an Exp Date (i.e. it won't find 04/2027). This is something that can be added fairly easily. I am sure there are some cards out there that have the full year (some Amex cards if I remember correctly).

* There are some no-no's I do in the code that I hacked in just to get things up and running as quick as possible, the major one being I force cast a lot. This is just clean-up that needs to be done. The code should run fine without crashing though... I hope.
