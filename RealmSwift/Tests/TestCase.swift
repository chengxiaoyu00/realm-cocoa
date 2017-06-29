////////////////////////////////////////////////////////////////////////////
//
// Copyright 2014 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

import Foundation
import Realm
import Realm.Private
import Realm.Dynamic
import RealmSwift
import XCTest

func inMemoryRealm(_ inMememoryIdentifier: String) -> Realm {
    return try! Realm(configuration: Realm.Configuration(inMemoryIdentifier: inMememoryIdentifier))
}

class TestCase: XCTestCase {
    var exceptionThrown = false
    var testDir: String! = nil

    let queue = DispatchQueue(label: "background")

    @discardableResult
    func realmWithTestPath(configuration: Realm.Configuration = Realm.Configuration()) -> Realm {
        var configuration = configuration
        configuration.fileURL = testRealmURL()
        return try! Realm(configuration: configuration)
    }

    override class func setUp() {
        super.setUp()
#if DEBUG || arch(i386) || arch(x86_64)
        // Disable actually syncing anything to the disk to greatly speed up the
        // tests, but only when not running on device because it can't be
        // re-enabled and we need it enabled for performance tests
        RLMDisableSyncToDisk()
#endif
        do {
            // Clean up any potentially lingering Realm files from previous runs
            try FileManager.default.removeItem(atPath: RLMRealmPathForFile(""))
        } catch {
            // The directory might not actually already exist, so not an error
        }
    }

    override class func tearDown() {
        RLMRealm.resetRealmState()
        super.tearDown()
    }

    override func invokeTest() {
        testDir = RLMRealmPathForFile(realmFilePrefix())

        do {
            try FileManager.default.removeItem(atPath: testDir)
        } catch {
            // The directory shouldn't actually already exist, so not an error
        }
        try! FileManager.default.createDirectory(at: URL(fileURLWithPath: testDir, isDirectory: true),
                                                     withIntermediateDirectories: true, attributes: nil)

        let config = Realm.Configuration(fileURL: defaultRealmURL())
        Realm.Configuration.defaultConfiguration = config

        exceptionThrown = false
        autoreleasepool { super.invokeTest() }

        if !exceptionThrown {
            XCTAssertFalse(RLMHasCachedRealmForPath(defaultRealmURL().path))
            XCTAssertFalse(RLMHasCachedRealmForPath(testRealmURL().path))
        }

        resetRealmState()

        do {
            try FileManager.default.removeItem(atPath: testDir)
        } catch {
            XCTFail("Unable to delete realm files")
        }

        // Verify that there are no remaining realm files after the test
        let parentDir = (testDir as NSString).deletingLastPathComponent
        for url in FileManager.default.enumerator(atPath: parentDir)! {
            let url = url as! NSString
            XCTAssertNotEqual(url.pathExtension, "realm", "Lingering realm file at \(parentDir)/\(url)")
            assert(url.pathExtension != "realm")
        }
    }

    func resetRealmState() {
        RLMRealm.resetRealmState()
    }

    func dispatchSyncNewThread(block: @escaping () -> Void) {
        queue.async {
            autoreleasepool {
                block()
            }
        }
        queue.sync { }
    }

    /// Check whether two test objects are equal (refer to the same row in the same Realm), even if their models
    /// don't define a primary key.
    func assertEqual(_ o1: Object?, _ o2: Object?, fileName: String = #file, lineNumber: UInt = #line) {
        if o1?.isEqual(to: o2) ?? false {
            return
        }
        recordFailure(withDescription: "Objects expected to be equal, but weren't. First: \(o1?.description ?? "nil"), "
            + "second: \(o2?.description ?? "nil")",
            inFile: fileName, atLine: lineNumber, expected: false)
    }

    /// Check whether two collections containing Realm objects are equal.
    func assertEqualObjectCollections<T: Collection, U: Collection>(_ c1: T, _ c2: U, fileName: String = #file, lineNumber: UInt = #line)
        where T.Iterator.Element : Object,
        U.Iterator.Element : Object,
        T.IndexDistance : Equatable,
        T.IndexDistance == U.IndexDistance {
        XCTAssertEqual(c1.count, c2.count, "Collection counts were incorrect")
        for (o1, o2) in zip(c1, c2) {
            assertEqual(o1, o2, fileName: fileName, lineNumber: lineNumber)
        }
    }

    func assertThrows<T>(_ block: @autoclosure @escaping() -> T, named: String? = RLMExceptionName,
                         _ message: String? = nil, fileName: String = #file, lineNumber: UInt = #line) {
        exceptionThrown = true
        RLMAssertThrowsWithName(self, { _ = block() }, named, message, fileName, lineNumber)
    }

    func assertThrows<T>(_ block: @autoclosure @escaping () -> T, reason regexString: String,
                         _ message: String? = nil, fileName: String = #file, lineNumber: UInt = #line) {
        exceptionThrown = true
        RLMAssertThrowsWithReasonMatching(self, { _ = block() }, regexString, message, fileName, lineNumber)
    }

    func assertSucceeds(message: String? = nil, fileName: StaticString = #file,
                        lineNumber: UInt = #line, block: () throws -> Void) {
        do {
            try block()
        } catch {
            XCTFail("Expected no error, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Realm.Error.Code, _ message: String? = nil,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: () throws -> T) {
        do {
            _ = try block()
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch let e as Realm.Error where e.code == expectedError {
            // Success!
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertFails<T>(_ expectedError: Error, _ message: String? = nil,
                        fileName: StaticString = #file, lineNumber: UInt = #line,
                        block: () throws -> T) {
        do {
            _ = try block()
            XCTFail("Expected to catch <\(expectedError)>, but no error was thrown.",
                file: fileName, line: lineNumber)
        } catch let e where e._code == expectedError._code {
            // Success!
        } catch {
            XCTFail("Expected to catch <\(expectedError)>, but instead caught <\(error)>.",
                file: fileName, line: lineNumber)
        }
    }

    func assertNil<T>(block: @autoclosure() -> T?, _ message: String? = nil,
                      fileName: StaticString = #file, lineNumber: UInt = #line) {
        XCTAssert(block() == nil, message ?? "", file: fileName, line: lineNumber)
    }

    func assertMatches(_ block: @autoclosure () -> String, _ regexString: String, _ message: String? = nil,
                       fileName: String = #file, lineNumber: UInt = #line) {
        RLMAssertMatches(self, block, regexString, message, fileName, lineNumber)
    }

    private func realmFilePrefix() -> String {
        return name!.trimmingCharacters(in: CharacterSet(charactersIn: "-[]"))
    }

    internal func testRealmURL() -> URL {
        return realmURLForFile("test.realm")
    }

    internal func defaultRealmURL() -> URL {
        return realmURLForFile("default.realm")
    }

    private func realmURLForFile(_ fileName: String) -> URL {
        let directory = URL(fileURLWithPath: testDir, isDirectory: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
