import Foundation
import Testing
@testable import Horizon

struct LocalizationCoverageTests {
    @Test func compatibilitySamplesHaveEnglishTitlesAndFindings() {
        for sample in CompatibilitySamples.all {
            #expect(sample.englishTitle != "Compatibility example", "Missing title: \(sample.id)")
            let report = ConfigurationCompatibility.inspect(Data(sample.yaml.utf8))
            for finding in report.findings {
                #expect(ConfigurationDiagnosticText.location(finding.location) != nil, "Missing location: \(sample.id) / \(finding.location)")
                let english = DiagnosticText.importEnglish(finding.detail)
                #expect(!english.contains("unavailable in English"), "Missing finding: \(sample.id) / \(finding.detail)")
                #expect(english.range(of: #"\p{script=Han}"#, options: .regularExpression) == nil, "Mixed language: \(sample.id) / \(english)")
            }
        }
    }

    @Test func usableSampleAdaptationsAreTranslated() throws {
        for sample in CompatibilitySamples.all where sample.usable {
            // Fictional fixtures only: no downloads, credentials or tunnel startup.
            let prepared = try PrototypeConfiguration.prepare(Data(sample.yaml.utf8))
            #expect(DiagnosticText.importEnglish(prepared.summary).contains("nodes"))
            for adaptation in prepared.adaptations {
                #expect(!DiagnosticText.importEnglish(adaptation).contains("unavailable in English"), "Missing adaptation: \(sample.id) / \(adaptation)")
            }
        }
    }

    @Test func updateSummariesAndValidationLocationsKeepUsefulDetails() {
        #expect(DiagnosticText.english("100 个节点、6 个策略组、867 条规则。") == "100 nodes · 6 groups · 867 rules")
        #expect(DiagnosticText.english("节点新增 2 · 删除 1 · 字段变化 3") == "Nodes added: 2 · Removed: 1 · Changed: 3")
        #expect(DiagnosticText.english("DNS：已改变") == "DNS: Changed")
        #expect(ConfigurationDiagnosticText.location("DNS · fallback-filter") == "DNS · fallback-filter")
        #expect(DiagnosticText.english("策略组 2：timeout 超出支持范围。 (2003)") == "Group 2: timeout is out of the supported range. (2003)")
    }

    @Test func downloadFailuresRemainSpecificAndUnknownInputStaysHidden() {
        #expect(DiagnosticText.english("100 ms · TCP") == "100 ms · TCP")
        for failure in SubscriptionDownloader.Failure.allCases {
            let result = DiagnosticText.english(failure.safeReason + "；现有版本保留。")
            #expect(result.contains(failure.englishReason))
            #expect(result.contains("retained"))
        }
        #expect(!DiagnosticText.importEnglish("未知错误：TEST-ONLY-SECRET").contains("TEST-ONLY-SECRET"))
        #expect(!DiagnosticText.importEnglish("节点 1：TEST-ONLY-SECRET 参数无效。 (2003)").contains("TEST-ONLY-SECRET"))
    }

    @Test func permissionResourcesExistInBothLanguages() throws {
        let englishURL = try #require(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: "en.lproj"))
        let chineseURL = try #require(Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: "zh-Hans.lproj"))
        let english = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: englishURL), format: nil) as? [String: String])
        let chinese = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: chineseURL), format: nil) as? [String: String])
        for key in ["NSCameraUsageDescription", "NSMotionUsageDescription"] {
            let en = try #require(english[key]), zh = try #require(chinese[key])
            #expect(en.range(of: #"\p{script=Han}"#, options: .regularExpression) == nil)
            #expect(zh.range(of: #"\p{script=Han}"#, options: .regularExpression) != nil)
        }
    }
}
