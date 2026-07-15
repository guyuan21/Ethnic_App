package com.example.app_flutter

/**
 * Conservative title matcher for the 56 officially recognized ethnic groups.
 *
 * OCR is only an auxiliary signal. An unrelated line containing `族` must not
 * stop the search or influence the image classifier, so results are accepted
 * only when they match this allow-list. A one-character OCR correction is
 * allowed only for names with at least three Chinese characters and a final
 * `族`, which avoids turning short background words into a label.
 */
object EthnicTitleMatcher {
    data class Match(
        val canonicalName: String,
        val lineIndex: Int,
        val exact: Boolean,
    )

    val canonicalNames: List<String> = listOf(
        "汉族", "蒙古族", "回族", "藏族", "维吾尔族", "苗族", "彝族", "壮族",
        "布依族", "朝鲜族", "满族", "侗族", "瑶族", "白族", "土家族", "哈尼族",
        "哈萨克族", "傣族", "黎族", "傈僳族", "佤族", "畲族", "高山族", "拉祜族",
        "水族", "东乡族", "纳西族", "景颇族", "柯尔克孜族", "土族", "达斡尔族",
        "仫佬族", "羌族", "布朗族", "撒拉族", "毛南族", "仡佬族", "锡伯族",
        "阿昌族", "普米族", "塔吉克族", "怒族", "乌孜别克族", "俄罗斯族",
        "鄂温克族", "德昂族", "保安族", "裕固族", "京族", "塔塔尔族", "独龙族",
        "鄂伦春族", "赫哲族", "门巴族", "珞巴族", "基诺族",
    ).sortedByDescending { it.length }

    fun find(lines: List<String>): Match? {
        val normalized = lines.map(::normalize)

        normalized.forEachIndexed { index, line ->
            canonicalNames.firstOrNull { line.contains(it) }?.let { name ->
                return Match(name, index, exact = true)
            }
        }

        normalized.forEachIndexed { index, line ->
            if (line.length !in 3..7 || !line.endsWith('族')) return@forEachIndexed
            val candidates = canonicalNames.filter { name ->
                name.length >= 3 &&
                    name.length == line.length &&
                    editDistance(name, line) == 1
            }
            // An ambiguous correction is less useful than no OCR hint.
            if (candidates.size == 1) {
                return Match(candidates.single(), index, exact = false)
            }
        }
        return null
    }

    private fun normalize(value: String): String = buildString(value.length) {
        value.forEach { character ->
            if (character.isLetterOrDigit() || character == '族') append(character)
        }
    }

    private fun editDistance(left: String, right: String): Int {
        if (left == right) return 0
        if (left.isEmpty()) return right.length
        if (right.isEmpty()) return left.length
        var previous = IntArray(right.length + 1) { it }
        var current = IntArray(right.length + 1)
        left.forEachIndexed { leftIndex, leftCharacter ->
            current[0] = leftIndex + 1
            right.forEachIndexed { rightIndex, rightCharacter ->
                val substitution = previous[rightIndex] +
                    if (leftCharacter == rightCharacter) 0 else 1
                current[rightIndex + 1] = minOf(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    substitution,
                )
            }
            val swap = previous
            previous = current
            current = swap
        }
        return previous[right.length]
    }
}
