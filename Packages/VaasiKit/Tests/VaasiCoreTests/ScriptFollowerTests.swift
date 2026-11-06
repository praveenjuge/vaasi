import Foundation
import Testing
@testable import VaasiCore

@Suite("Script follower")
struct ScriptFollowerTests {
    let text = """
    Thank you for downloading this app. This tool exists because of many things \
    created before it, ideas, technologies, and people whose work we all build on. \
    You don't have to invent everything from scratch. You just need a place to think.
    """

    private func words(_ s: String) -> [String] { ScriptTokenizer.words(in: s) }

    @Test func followsWordByWord() {
        var follower = ScriptFollower(text: text)
        var spoken: [String] = []
        for word in words(text) {
            spoken.append(word)
            follower.update(transcriptWords: spoken)
        }
        #expect(follower.lastMatchedIndex == follower.tokens.count - 1)
    }

    @Test func toleratesMisheardAndExtraWords() {
        var follower = ScriptFollower(text: text)
        follower.update(transcriptWords: words("thank you for downloading the app this tool exist because"))
        let token = follower.tokens[follower.lastMatchedIndex]
        #expect(token.word == "because")
        follower.update(transcriptWords: words("thank you for downloading the app this tool exist because um of many thing created"))
        #expect(follower.tokens[follower.lastMatchedIndex].word == "created")
    }

    @Test func ignoresUnrelatedSpeech() {
        var follower = ScriptFollower(text: text)
        follower.update(transcriptWords: words("thank you for downloading"))
        let before = follower.lastMatchedIndex
        follower.update(transcriptWords: words("thank you for downloading sorry can everyone hear me okay"))
        #expect(follower.lastMatchedIndex == before)
    }

    @Test func recoversAfterSkippingAhead() {
        var follower = ScriptFollower(text: text)
        follower.update(transcriptWords: words("thank you for downloading"))
        follower.update(transcriptWords: words("thank you for downloading you just need a place to think"))
        #expect(follower.tokens[follower.lastMatchedIndex].word == "think")
    }

    @Test func resetAnchorsToOffset() {
        var follower = ScriptFollower(text: text)
        let offset = (text as NSString).range(of: "You just").location
        follower.reset(toUTF16Offset: offset)
        follower.update(transcriptWords: words("you just need"))
        #expect(follower.tokens[follower.lastMatchedIndex].word == "need")
    }

    @Test func fuzzyMatching() {
        #expect(ScriptFollower.similar("technologies", "technology"))
        #expect(ScriptFollower.similar("exists", "exist"))
        #expect(!ScriptFollower.similar("the", "this"))
        #expect(ScriptFollower.editDistance("kitten", "sitting", limit: 5) == 3)
    }

    @Test func transcriptBufferReplacesVolatile() {
        var buffer = TranscriptBuffer()
        buffer.apply(text: "This tool", isFinal: false)
        buffer.apply(text: "This tool exists", isFinal: false)
        #expect(buffer.words == ["this", "tool", "exists"])
        buffer.apply(text: "This tool exists.", isFinal: true)
        buffer.apply(text: "Because", isFinal: false)
        #expect(buffer.words == ["this", "tool", "exists", "because"])
    }
}
