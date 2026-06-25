import Testing
@testable import WatermarkStudioMac

@Test func cleanupPresetRecommendedRoiPaddingMatchesDefaults() {
    #expect(CleanupPreset.fast.recommendedRoiPadding == 128)
    #expect(CleanupPreset.balanced.recommendedRoiPadding == 256)
    #expect(CleanupPreset.quality.recommendedRoiPadding == 0)
}

@Test func cleanupPresetProcessScaleMatchesSpeedIntent() {
    #expect(CleanupPreset.fast.processScale == 0.5)
    #expect(CleanupPreset.balanced.processScale == 1.0)
    #expect(CleanupPreset.quality.processScale == 1.0)
}
