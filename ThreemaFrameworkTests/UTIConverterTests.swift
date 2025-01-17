//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2020-2021 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import XCTest
@testable import ThreemaFramework

class UTIConverterTests: XCTestCase {
    
    private let rawFilename = "Bild-7"
    
    let testBundle: Bundle = Bundle(for: UTIConverterTests.self)
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    /// This tests the mime type generation from the uti for a selection of raw formats generated with imagemagick.
    /// The list was taken from https://stackoverflow.com/a/47612661/2310837.
    /// All items not recognized by macOSs Finder were removed.
    /// - Throws:
    func testGetRawImageMimeType() throws {
        let matrix : [(String, Bool)] = [
            ("srf", false),
            ("sr2", true),
            ("raf", false),
            ("pef", false),
            ("orf", false),
            ("nef", false),
            ("mrw", false),
            ("erf", true),
            ("dng", true),
            ("dcr", false),
            ("crw", true),
            ("cr2", false),
            ("arw", false),
            ("raw", false),
        ]
        for item in matrix {
            let testImageUrl = testBundle.url(forResource:rawFilename, withExtension: item.0)
            let uti = UTIConverter.uti(forFileURL: testImageUrl)
            let mimeType = UTIConverter.mimeType(fromUTI: uti)

            XCTAssert(UTIConverter.type(uti, conformsTo: kUTTypeImage as String), "\(item.0) with uti \(String(describing: uti)) should conform to image but does not")
            XCTAssert(UTIConverter.isImageMimeType(mimeType) == item.1, "\(item.0) with mime type \(String(describing: mimeType)) should conform to image \(item.1)")
        }
    }
    
    
}
