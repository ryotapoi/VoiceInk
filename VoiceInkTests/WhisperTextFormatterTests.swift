import Testing
@testable import VoiceInk

struct WhisperTextFormatterTests {

    @Test func japaneseSentencesJoinedWithoutSpace() {
        let input = "それってどうなの?教えて。"
        let result = WhisperTextFormatter.format(input)
        #expect(!result.contains("? 教"))
    }

    @Test func englishSentencesJoinedWithSpace() {
        let input = "Hello world. How are you?"
        let result = WhisperTextFormatter.format(input)
        #expect(result.contains(". How"))
    }

    @Test func chineseSentencesJoinedWithoutSpace() {
        let input = "你好世界。今天天气怎么样？"
        let result = WhisperTextFormatter.format(input)
        #expect(!result.contains("。 今"))
    }

    @Test func koreanSentencesJoinedWithSpace() {
        let input = "안녕하세요. 오늘 날씨가 좋습니다."
        let result = WhisperTextFormatter.format(input)
        #expect(result.contains(". 오"))
    }
}
