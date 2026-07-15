package com.example.app_flutter

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EthnicTitleMatcherTest {
    @Test
    fun containsAll56CanonicalNames() {
        assertEquals(56, EthnicTitleMatcher.canonicalNames.distinct().size)
        assertTrue(EthnicTitleMatcher.canonicalNames.contains("门巴族"))
        assertTrue(EthnicTitleMatcher.canonicalNames.contains("白族"))
    }

    @Test
    fun acceptsCanonicalTitleInsideAnOcrLine() {
        val match = EthnicTitleMatcher.find(listOf("民族服饰：门巴族", "Moinba"))

        assertEquals("门巴族", match?.canonicalName)
        assertEquals(0, match?.lineIndex)
        assertTrue(match?.exact == true)
    }

    @Test
    fun conservativelyRepairsOneCharacterForLongNames() {
        val match = EthnicTitleMatcher.find(listOf("门巳族"))

        assertEquals("门巴族", match?.canonicalName)
        assertFalse(match?.exact ?: true)
    }

    @Test
    fun doesNotAcceptGenericOrShortFuzzyBackgroundText() {
        assertNull(EthnicTitleMatcher.find(listOf("少数民族服饰", "家族文化")))
        assertNull(EthnicTitleMatcher.find(listOf("白旅")))
        assertNull(EthnicTitleMatcher.find(listOf("某某族")))
        assertNull(EthnicTitleMatcher.find(listOf("阿巴族")))
    }
}
