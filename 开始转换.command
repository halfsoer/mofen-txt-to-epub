#!/bin/bash
# 墨分：双击后扫描本文件所在文件夹及子文件夹里的 txt，生成同名 epub，转换成功后会删除原 txt。
DIR="$(cd "$(dirname "$0")" && pwd)"
export MOFEN_ROOT="$DIR"
export LANG="${LANG:-en_US.UTF-8}"
echo "墨分"
echo "程序位置：$DIR"

# 用 find 预先扫描（对外置盘最稳）
TMPLIST="$(mktemp /tmp/mofen-txtlist.XXXXXX)"
find "$DIR" -type f -iname "*.txt" -not -path "*/.*" > "$TMPLIST" 2>/dev/null
COUNT=$(wc -l < "$TMPLIST" | tr -d ' ')
echo "预扫描找到 $COUNT 个 txt"
export MOFEN_TXTLIST="$TMPLIST"

/usr/bin/osascript -l JavaScript <<'___MOFEN_SCRIPT_END___'
/** TXT → EPUB：章节识别、纠错、打包。网页与 Mac 本地程序共用。 */
const CN_NUM = "[0-9０-９]{1,5}|[零〇○一二三四五六七八九十百千万亿兩两壹贰貳叁參肆伍陆陸柒捌玖拾佰仟萬億]{1,16}|[IVXLCDMivxlcdm]{1,9}";
const CN_CHAPTER = "(?:正文|番外篇|番外|外传|外傳|外篇|间章|間章|插章|特别篇|特別篇|完结篇|完結篇)?" +
    "[\\s\\u3000]*第[\\s\\u3000]*(?<num>" +
    CN_NUM +
    ")[\\s\\u3000]*(?<unit>[章节回卷部篇集话話幕折场場节節记記则則课課讲講])" +
    "(?:[\\s\\u3000]*之[\\s\\u3000]*(?:[0-9０-９]{1,3}|[一二三四五六七八九十]{1,4}))?" +
    "(?:[\\s\\u3000]*[（\\(][^）\\)\\r\\n]{1,12}[）\\)])?";
const VOL_BARE = "(?:第[\\s\\u3000]*)?(?:上|中|下)[\\s\\u3000]*[卷部篇集编編]" +
    "|上篇|中篇|下篇|上部|中部|下部|上卷|中卷|下卷|序篇|终篇|終篇" +
    "|[卷部篇集编編][\\s\\u3000]*(?:[0-9０-９]{1,4}|[一二三四五六七八九十百千两兩]{1,8})";
const SPECIAL_WORDS = "完结感言|完結感言|作者的话|作者的話|特别篇|特別篇|序章|楔子|引子|序幕|序言|序文|前言|引言|绪论|緒論|概论|簡介|简介|尾声|尾聲|终章|終章|终曲|終曲|大结局|大結局|结局|結局|后记|後記|附录|附錄|番外篇|番外|外传|外傳|外篇|间章|間章|插章|结语|結語|致谢|致謝|后序|後序|跋文|跋|序|prologue|epilogue|interlude|preface|foreword|afterword|introduction";
const SPECIALS = "(?:" +
    SPECIAL_WORDS +
    ")(?=[\\s\\u3000:：、.．\\-—–~～【\\[（(「『★☆]|$)";
const EN_WORD = "eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|ten|one|two|three|four|five|six|seven|eight|nine";
const EN_NUMBERED = "(?:chapter|volume|section|episode|scene|chap|book|part|vol|act|sec|ep|ch)\\.?" +
    "[\\s\\u3000]*[:：.\\-–—]?[\\s\\u3000]*(?<ennum>[0-9]{1,5}|[IVXLCDMivxlcdm]{1,9}|(?:" +
    EN_WORD +
    ")(?:[\\s-](?:one|two|three|four|five|six|seven|eight|nine))?)";
const BRACKET = "[【\\[［][\\s\\u3000]*(?<brnum>[0-9０-９]{1,5})[\\s\\u3000]*[】\\]］]";
const PAREN = "[（\\(][\\s\\u3000]*(?<paren>[0-9０-９]{1,4}|[一二三四五六七八九十百千]{1,8})[\\s\\u3000]*[）\\)]";
const WEAK_DOT = "(?<weak>[0-9０-９]{1,4})[\\s\\u3000]*[.．、]";
const WEAK_SPACE = "(?<spnum>[0-9０-９]{2,4})[\\s\\u3000]+";
const PREFIX = "[\\s\\u3000\\uFEFF]*(?:[#＃]{1,6}[\\s\\u3000]*)?(?:[=＝\\-—―~～*_＊※★☆◆◇◎●○■□▲△▼▽§·•・|｜/／\\\\《〈「『“\"‘'【\\[［\\(（<＜〖][\\s\\u3000]*){0,16}";
/** 一行一条。覆盖中文章回体、卷篇、特典，以及 Chapter / 弱编号。纠错在识别之后。 */
const CHAPTER_REGEX_SOURCE = "^" +
    PREFIX +
    "(?<label>" +
    [CN_CHAPTER, VOL_BARE, SPECIALS, EN_NUMBERED, BRACKET, PAREN, WEAK_DOT, WEAK_SPACE].join("|") +
    ")(?<rest>[^\\r\\n]{0,200})$";
const CHAPTER_FORMATS = [
    "第X章 / 节 / 回 / 卷 / 部 / 篇 / 集 / 话 / 幕 / 折 / 场 / 记 / 则 / 课 / 讲",
    "阿拉伯、全角、中文、大写中文、罗马数字，含「第一百二十三章」「第两千三百章」「第１２章」",
    "第X章之一、第X章（上）（下）、正文第X章、第一卷第三章",
    "卷一、上篇、中卷、下部",
    "序 / 序章 / 楔子 / 引子 / 前言 / 引言 / 尾声 / 终章 / 后记 / 跋 / 附录 / 番外 / 外传 / 间章",
    "完结感言、作者的话",
    "Chapter、Chap.、Ch.、Part、Volume、Book、Episode、Section、Act、Scene",
    "英文数词与罗马数字：Chapter One、CHAPTER IV",
    "Prologue、Epilogue、Interlude、Preface、Foreword、Afterword",
    "【001】、[12]、（一）、（1）",
    "001 标题、001. 标题、1、标题（有「第×章」时自动剔除）",
    "行首装饰：【】「」★☆#  Markdown 标题、等号破折号",
];
const CN_DIGIT = {
    "零": 0,
    "〇": 0,
    "○": 0,
    "一": 1,
    "二": 2,
    "两": 2,
    "兩": 2,
    "三": 3,
    "四": 4,
    "五": 5,
    "六": 6,
    "七": 7,
    "八": 8,
    "九": 9,
    "壹": 1,
    "贰": 2,
    "貳": 2,
    "叁": 3,
    "參": 3,
    "肆": 4,
    "伍": 5,
    "陆": 6,
    "陸": 6,
    "柒": 7,
    "捌": 8,
    "玖": 9,
};
const CN_UNIT = { "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000 };
const CN_BIG = { "万": 10000, "萬": 10000, "亿": 100000000, "億": 100000000 };
const EN_WORDS = {
    one: 1,
    two: 2,
    three: 3,
    four: 4,
    five: 5,
    six: 6,
    seven: 7,
    eight: 8,
    nine: 9,
    ten: 10,
    eleven: 11,
    twelve: 12,
    thirteen: 13,
    fourteen: 14,
    fifteen: 15,
    sixteen: 16,
    seventeen: 17,
    eighteen: 18,
    nineteen: 19,
    twenty: 20,
    thirty: 30,
    forty: 40,
    fifty: 50,
};
function parseRoman(s) {
    const map = { I: 1, V: 5, X: 10, L: 50, C: 100, D: 500, M: 1000 };
    const u = s.toUpperCase();
    let total = 0;
    let prev = 0;
    for (let i = u.length - 1; i >= 0; i--) {
        const v = map[u.charAt(i)];
        if (!v)
            return null;
        if (v < prev)
            total -= v;
        else {
            total += v;
            prev = v;
        }
    }
    return total || null;
}
function parseChineseNumber(s) {
    let total = 0;
    let section = 0;
    let number = 0;
    let seen = false;
    for (let i = 0; i < s.length; i++) {
        const ch = s.charAt(i);
        if (ch in CN_DIGIT) {
            number = CN_DIGIT[ch];
            seen = true;
        }
        else if (ch in CN_UNIT) {
            seen = true;
            if (number === 0)
                number = 1;
            section += number * CN_UNIT[ch];
            number = 0;
        }
        else if (ch in CN_BIG) {
            seen = true;
            section += number;
            if (section === 0)
                section = 1;
            total += section * CN_BIG[ch];
            section = 0;
            number = 0;
        }
        else
            return null;
    }
    if (!seen)
        return null;
    return total + section + number;
}
function parseHeadingNumber(raw) {
    if (!raw)
        return null;
    const s = raw.replace(/[\s\u3000]/g, "");
    if (!s)
        return null;
    if (/^[0-9０-９]+$/.test(s)) {
        const n = s.replace(/[０-９]/g, (ch) => String.fromCharCode(ch.charCodeAt(0) - 0xff10 + 48));
        const v = Number.parseInt(n, 10);
        return Number.isFinite(v) ? v : null;
    }
    if (/^[ivxlcdm]+$/i.test(s))
        return parseRoman(s);
    const lower = s.toLowerCase();
    const parts = lower.split(/[\s-]+/);
    if (parts.length && parts.every((p) => p in EN_WORDS)) {
        if (parts.length === 1)
            return EN_WORDS[parts[0]];
        if (parts.length === 2 && EN_WORDS[parts[0]] >= 20 && EN_WORDS[parts[1]] < 10) {
            return EN_WORDS[parts[0]] + EN_WORDS[parts[1]];
        }
    }
    return parseChineseNumber(s);
}
function cleanTitle(label, rest) {
    const lab = label.replace(/^[\s\u3000]+|[\s\u3000]+$/g, "").replace(/[、.．]$/g, "");
    let r = rest.replace(/^[\s\u3000]+/, "");
    r = r.replace(/^[\]】」』》〉)）☆★◆◇=~～＝*＊\-—―_|｜/／\\:：、.．,，]+/, "");
    r = r.replace(/[\s\u3000*＊★☆◆◇=~～＝\-—―_|｜/／\\]+$/g, "");
    r = r.replace(/^[\s\u3000]+|[\s\u3000]+$/g, "");
    if (!r || r === lab)
        return lab;
    return (lab + " " + r).replace(/\s+/g, " ").trim();
}
function inferUnit(label, hint) {
    const m = label.match(/[章节回卷部篇集话話幕折场場节節记記则則课課讲講]/);
    if (m && hint !== "weak" && hint !== "en")
        return m[0];
    if (hint === "en")
        return /^(volume|vol\.?|book|part)\b/i.test(label) ? "vol" : "ch";
    if (hint === "br" || hint === "weak")
        return "w";
    return m ? m[0] : "s";
}
function classify(label, hint) {
    if (hint === "weak")
        return "weak";
    const compact = label.replace(/[\s\u3000]/g, "");
    const special = new RegExp("^(" + SPECIAL_WORDS + ")$", "i");
    if (special.test(compact))
        return "special";
    if (hint === "en" && /^(volume|vol\.?|book|part)\b/i.test(label))
        return "volume";
    if (/[卷部篇集编編]/.test(compact) && !/[章节回话話节節场場幕折课課讲講记記则則]/.test(compact)) {
        return "volume";
    }
    return "chapter";
}
function matchWith(re, line) {
    var _a;
    re.lastIndex = 0;
    const m = re.exec(line.replace(/\r$/, ""));
    if (!((_a = m === null || m === void 0 ? void 0 : m.groups) === null || _a === void 0 ? void 0 : _a.label))
        return null;
    const g = m.groups;
    const hint = g.weak || g.spnum || g.paren || g.brnum ? "weak" : g.ennum ? "en" : "cn";
    const label = g.label.replace(/^[\s\u3000]+|[\s\u3000]+$/g, "");
    const num = parseHeadingNumber(g.num || g.ennum || g.brnum || g.weak || g.spnum || g.paren || "");
    return {
        title: cleanTitle(label, g.rest || ""),
        num,
        kind: classify(label, hint),
        unit: g.unit || inferUnit(label, hint),
        label,
    };
}
function matchHeadingLine(line, source = CHAPTER_REGEX_SOURCE) {
    let re;
    try {
        re = new RegExp(source, "iu");
    }
    catch (_a) {
        return null;
    }
    return matchWith(re, line);
}
function shapeReject(line, kind) {
    const trimmed = line.replace(/^[\s\u3000]+|[\s\u3000]+$/g, "");
    if (!trimmed)
        return "空行";
    if (trimmed.length > 120)
        return "太长，更像正文";
    if ((trimmed.match(/。/g) || []).length > 0)
        return "含有句号，更像正文";
    if ((trimmed.match(/[！？!?]/g) || []).length > 1)
        return "语气符号太多，更像正文";
    const commas = (trimmed.match(/[，,]/g) || []).length;
    if (commas > 2)
        return "逗号太多，更像正文";
    if (trimmed.length > 60 && commas > 0)
        return "又长又有逗号，更像正文";
    if (/说道|问道|笑道|喊道|吼道|哼道|冷道|答道/.test(trimmed))
        return "像对白，不像标题";
    if (/^[“"「『].+[”"」』]$/.test(trimmed))
        return "整行在引号里，多半是对白";
    if (kind === "weak" && trimmed.length > 40)
        return "纯数字条目过长，不像章节";
    if (kind === "special" && trimmed.length > 36)
        return "特殊标题后的文字过长";
    return null;
}
function splitLines(text) {
    const src = text.replace(/^\uFEFF/, "").replace(/\u0000/g, "");
    const lines = [];
    let i = 0;
    while (i < src.length) {
        let j = i;
        while (j < src.length && src.charCodeAt(j) !== 10 && src.charCodeAt(j) !== 13)
            j++;
        lines.push(src.slice(i, j));
        if (src.charCodeAt(j) === 13 && src.charCodeAt(j + 1) === 10)
            j += 2;
        else if (j < src.length)
            j += 1;
        if (j === i)
            break;
        i = j;
    }
    return lines;
}
function bodyChars(lines, indexA, indexB) {
    let n = 0;
    for (let i = indexA + 1; i < indexB; i++)
        n += lines[i].replace(/[\s\u3000]/g, "").length;
    return n;
}
function median(nums) {
    if (!nums.length)
        return 0;
    const s = nums.slice().sort((a, b) => a - b);
    const mid = Math.floor(s.length / 2);
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
function normKey(s) {
    return s.replace(/[\s\u3000:：、\-—–~～.．【】[\]（）()「」『』★☆]/g, "").toLowerCase();
}
function toPublic(c, reason) {
    return {
        line: c.index + 1,
        title: c.title,
        kind: c.kind,
        num: c.num,
        unit: c.unit,
        raw: c.raw,
        reason: reason || "",
    };
}
function weakSequenceOk(weaks, lines) {
    if (weaks.length < 3)
        return false;
    let steps = 0;
    let good = 0;
    let prev = null;
    const gaps = [];
    for (let i = 0; i < weaks.length; i++) {
        if (i + 1 < weaks.length)
            gaps.push(bodyChars(lines, weaks[i].index, weaks[i + 1].index));
        const n = weaks[i].num;
        if (n === null || prev === null) {
            prev = n;
            continue;
        }
        steps++;
        if (n === prev + 1 || n === prev)
            good++;
        prev = n;
    }
    if (!steps)
        return false;
    return good / steps >= 0.7 && median(gaps) >= 80;
}
function prefixCatalog(kept, lines) {
    const drop = new Set();
    if (kept.length < 4)
        return drop;
    const tocLike = kept.map((c, i) => {
        if (i === kept.length - 1)
            return false;
        return bodyChars(lines, c.index, kept[i + 1].index) <= 20;
    });
    let j = 0;
    while (j < kept.length && tocLike[j])
        j++;
    if (j < 3 || j >= kept.length)
        return drop;
    const restGaps = [];
    for (let i = j; i < kept.length - 1; i++)
        restGaps.push(bodyChars(lines, kept[i].index, kept[i + 1].index));
    const prefixTitles = new Set(kept.slice(0, j).map((c) => normKey(c.title)));
    const dup = kept.slice(j).some((c) => prefixTitles.has(normKey(c.title)));
    if (!(dup || median(restGaps) >= 80))
        return drop;
    for (let i = 0; i < j; i++)
        drop.add(i);
    return drop;
}
function dedupeConsecutive(kept, dropped) {
    const out = [];
    for (const c of kept) {
        const prev = out[out.length - 1];
        if (prev && normKey(prev.title) === normKey(c.title)) {
            dropped.push(Object.assign(Object.assign({}, c), { reason: "与上一条标题重复，视为页眉" }));
            continue;
        }
        out.push(c);
    }
    return out;
}
function dedupeNumbers(kept, dropped) {
    const seen = new Set();
    const out = [];
    let segment = 0;
    let prevNum = null;
    for (const c of kept) {
        if (c.kind === "volume") {
            segment++;
            prevNum = null;
            out.push(c);
            continue;
        }
        if (c.num !== null && c.num <= 2 && prevNum !== null && prevNum >= 5)
            segment++;
        if (c.num !== null && c.kind !== "special") {
            const key = segment + ":" + c.unit + ":" + c.num;
            if (seen.has(key)) {
                dropped.push(Object.assign(Object.assign({}, c), { reason: "同一章号在本卷里重复，保留先出现的一条" }));
                continue;
            }
            seen.add(key);
            prevNum = c.num;
        }
        out.push(c);
    }
    return out;
}
function dropRegressions(kept, lines, dropped) {
    const gaps = [];
    for (let i = 0; i + 1 < kept.length; i++)
        gaps.push(bodyChars(lines, kept[i].index, kept[i + 1].index));
    const med = median(gaps);
    const out = [];
    let prev = null;
    for (let i = 0; i < kept.length; i++) {
        const c = kept[i];
        if (c.kind === "volume") {
            prev = null;
            out.push(c);
            continue;
        }
        if (c.num === null || c.kind === "special") {
            out.push(c);
            continue;
        }
        const restart = prev !== null && c.num <= 2 && prev >= 5;
        if (prev !== null && c.num < prev && !restart) {
            const before = i > 0 ? bodyChars(lines, kept[i - 1].index, c.index) : med;
            const after = i + 1 < kept.length ? bodyChars(lines, c.index, kept[i + 1].index) : med;
            if (Math.min(before, after) <= Math.max(40, med * 0.15)) {
                dropped.push(Object.assign(Object.assign({}, c), { reason: "编号回跳，而且紧贴前后标题，多半是夹注" }));
                continue;
            }
            out.push(c);
            continue;
        }
        prev = c.num;
        out.push(c);
    }
    return out;
}
function dropTiny(kept, lines, dropped) {
    const out = [];
    for (let i = 0; i < kept.length; i++) {
        const c = kept[i];
        const last = i === kept.length - 1;
        if (!last && (c.kind === "chapter" || c.kind === "weak")) {
            const n = bodyChars(lines, c.index, kept[i + 1].index);
            if (n < 12) {
                dropped.push(Object.assign(Object.assign({}, c), { reason: "标题后面几乎没有正文" }));
                continue;
            }
        }
        out.push(c);
    }
    return out;
}
function cjkCount(text) {
    let n = 0;
    const step = Math.max(1, Math.floor(text.length / 8000));
    for (let i = 0; i < text.length; i += step) {
        const c = text.charCodeAt(i);
        if (c >= 0x4e00 && c <= 0x9fff)
            n++;
    }
    return n;
}
function detectLanguage(text) {
    const step = Math.max(1, Math.floor(text.length / 5000));
    let n = 0;
    let cjk = 0;
    for (let i = 0; i < text.length; i += step) {
        n++;
        const c = text.charCodeAt(i);
        if (c >= 0x4e00 && c <= 0x9fff)
            cjk++;
    }
    return n && cjk / n > 0.05 ? "zh-CN" : "en";
}
function escapeXml(s) {
    let out = "";
    for (let i = 0; i < s.length; i++) {
        const c = s.charCodeAt(i);
        if (c === 38)
            out += "&" + "amp;";
        else if (c === 60)
            out += "&" + "lt;";
        else if (c === 62)
            out += "&" + "gt;";
        else if (c === 34)
            out += "&" + "quot;";
        else if (c < 32 && c !== 9 && c !== 10 && c !== 13)
            continue;
        else
            out += s.charAt(i);
    }
    return out;
}
function isTocWord(line) {
    const t = line.replace(/[\s\u3000:：]/g, "");
    return /^(目录|目次|目錄|contents|toc)$/i.test(t);
}
function linesToHtml(lines, skip, skipTocWord) {
    const parts = [];
    for (let i = 0; i < lines.length; i++) {
        if (skip === null || skip === void 0 ? void 0 : skip.has(i))
            continue;
        const t = lines[i].replace(/^[\s\u3000]+|[\s\u3000]+$/g, "");
        if (!t)
            continue;
        if (skipTocWord && isTocWord(t))
            continue;
        parts.push("<p>" + escapeXml(t) + "</p>");
    }
    return parts.join("\n");
}
function compactLen(s) {
    return s.replace(/[\s\u3000]/g, "").length;
}
function buildSections(lines, kept, catalogIdx, language) {
    const sections = [];
    const push = (title, kind, html) => {
        const id = "c" + String(sections.length + 1).padStart(3, "0");
        sections.push({ id, title, kind, html: html || "<p>&#160;</p>" });
    };
    if (!kept.length) {
        push(language === "zh-CN" ? "正文" : "Text", "chapter", linesToHtml(lines));
        return sections;
    }
    const first = kept[0].index;
    const preHtml = linesToHtml(lines.slice(0, first), catalogIdx, true);
    if (compactLen(preHtml.replace(/<[^>]+>/g, "")) >= 30) {
        push(language === "zh-CN" ? "卷首" : "Front", "front", preHtml);
    }
    for (let k = 0; k < kept.length; k++) {
        const start = kept[k].index + 1;
        const end = k + 1 < kept.length ? kept[k + 1].index : lines.length;
        push(kept[k].title, kept[k].kind, linesToHtml(lines.slice(start, end)));
    }
    return sections;
}
function emptyAnalysis(text, regexError) {
    return {
        kept: [],
        dropped: [],
        sections: [],
        language: detectLanguage(text),
        lineCount: 0,
        regexError,
    };
}
function analyzeText(text, opts = {}) {
    const source = (opts.regex || "").trim() || CHAPTER_REGEX_SOURCE;
    let re;
    try {
        re = new RegExp(source, "iu");
    }
    catch (err) {
        return emptyAnalysis(text, err instanceof Error ? err.message : "正则无效");
    }
    const lines = splitLines(text);
    const language = detectLanguage(text);
    const raw = [];
    const dropped = [];
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.length > 400)
            continue;
        re.lastIndex = 0;
        const hit = matchWith(re, line);
        if (!hit || !hit.title)
            continue;
        const cand = {
            index: i,
            raw: line,
            title: hit.title,
            kind: hit.kind,
            num: hit.num,
            unit: hit.unit,
        };
        const reason = shapeReject(line, hit.kind);
        if (reason)
            dropped.push(Object.assign(Object.assign({}, cand), { reason }));
        else
            raw.push(cand);
    }
    let kept = raw.slice();
    const strong = kept.filter((c) => c.kind === "chapter" || c.kind === "volume");
    const weaks = kept.filter((c) => c.kind === "weak");
    if (strong.length >= 1 && weaks.length) {
        for (const c of weaks)
            dropped.push(Object.assign(Object.assign({}, c), { reason: "已有「第×章」一类标题，纯数字编号视为列表" }));
        kept = kept.filter((c) => c.kind !== "weak");
    }
    else if (weaks.length && !weakSequenceOk(weaks, lines)) {
        for (const c of weaks)
            dropped.push(Object.assign(Object.assign({}, c), { reason: "纯数字编号不成稳定章节序列，已剔除" }));
        kept = kept.filter((c) => c.kind !== "weak");
    }
    const cat = prefixCatalog(kept, lines);
    if (cat.size) {
        kept = kept.filter((c, i) => {
            if (!cat.has(i))
                return true;
            dropped.push(Object.assign(Object.assign({}, c), { reason: "位于文首目录区，正文里会再次出现" }));
            return false;
        });
    }
    kept = dedupeConsecutive(kept, dropped);
    kept = dedupeNumbers(kept, dropped);
    kept = dropRegressions(kept, lines, dropped);
    kept = dropTiny(kept, lines, dropped);
    const forced = new Set(opts.forceLines || []);
    const banned = new Set(opts.banLines || []);
    if (forced.size) {
        const stay = [];
        for (const d of dropped) {
            if (forced.has(d.index + 1))
                kept.push(d);
            else
                stay.push(d);
        }
        dropped.length = 0;
        for (const d of stay)
            dropped.push(d);
        kept.sort((a, b) => a.index - b.index);
    }
    if (banned.size) {
        const next = [];
        for (const c of kept) {
            if (banned.has(c.index + 1))
                dropped.push(Object.assign(Object.assign({}, c), { reason: "手动剔除" }));
            else
                next.push(c);
        }
        kept = next;
    }
    const catalogIdx = new Set(dropped.filter((d) => d.reason.indexOf("目录区") >= 0).map((d) => d.index));
    const sections = buildSections(lines, kept, catalogIdx, language);
    dropped.sort((a, b) => a.index - b.index);
    return {
        kept: kept.map((c) => {
            const h = toPublic(c);
            return { line: h.line, title: h.title, kind: h.kind, num: h.num, unit: h.unit, raw: h.raw };
        }),
        dropped: dropped.map((d) => toPublic(d, d.reason)),
        sections,
        language,
        lineCount: lines.length,
    };
}
function decodeBuffer(buf) {
    if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe)
        return new TextDecoder("utf-16le").decode(buf);
    if (buf.length >= 2 && buf[0] === 0xfe && buf[1] === 0xff)
        return new TextDecoder("utf-16be").decode(buf);
    const skip = buf.length >= 3 && buf[0] === 0xef && buf[1] === 0xbb && buf[2] === 0xbf ? 3 : 0;
    const view = skip ? buf.subarray(skip) : buf;
    try {
        return new TextDecoder("utf-8", { fatal: true }).decode(view);
    }
    catch (_a) {
        try {
            return new TextDecoder("gb18030").decode(buf);
        }
        catch (_b) {
            return new TextDecoder("utf-8").decode(buf);
        }
    }
}
const NOT_AUTHOR = /精校|完结|完結|全本|校对|txt|www|\.com|小说|下載|下载|正文/;
function parseBookMeta(filename) {
    let base = filename.replace(/^.*[\\/]/, "").replace(/\.txt$/i, "");
    base = base.replace(/^\[[^\]]*?(?:\.com|\.cn|\.net|\.org|\.cc|www)[^\]]*\]/gi, "");
    base = base.replace(/【[^】]*?(?:\.com|\.cn|\.net|www)[^】]*】/gi, "");
    base = base.replace(/[(（][^)）]{0,16}?(?:精校|完结|完結|全本|正文|校对|精排|无错|无弹窗)[^)）]*[)）]/g, "");
    base = base.replace(/_+/g, " ").trim();
    let author = "";
    let title = base;
    let m;
    if ((m = /^【([^】]{1,20})】\s*(.+)$/.exec(title)) && !NOT_AUTHOR.test(m[1])) {
        author = m[1];
        title = m[2];
    }
    else if ((m = /^\[([^\]\]]{1,20})\]\s*(.+)$/.exec(title)) && !NOT_AUTHOR.test(m[1])) {
        author = m[1];
        title = m[2];
    }
    else if ((m = /^《([^》]+)》\s*(.*)$/.exec(title))) {
        title = m[1];
        author = (m[2] || "").replace(/^作者[:：\s]*/, "");
    }
    else if ((m = /^(.+?)\s*作者[:：]\s*(.+)$/.exec(title))) {
        title = m[1];
        author = m[2];
    }
    else if ((m = /^(.+?)\s+by\s+(.+)$/i.exec(title))) {
        title = m[1];
        author = m[2];
    }
    else if ((m = /^(.+?)[（(]([^)）]{1,12})[)）]\s*$/.exec(title)) && !NOT_AUTHOR.test(m[2])) {
        title = m[1];
        author = m[2];
    }
    else if ((m = /^(.+?)\s*[-–—]\s*([\u4e00-\u9fff·]{2,8})$/.exec(title))) {
        title = m[1];
        author = m[2];
    }
    title = title.replace(/^《|》$/g, "").trim() || "未名";
    author = author.replace(/[《》]/g, "").trim();
    return { title, author };
}
function wrapTitle(title) {
    const cjk = cjkCount(title) > 0;
    const size = cjk ? 8 : 18;
    const lines = [];
    let s = title.trim() || "未名";
    while (s.length && lines.length < 6) {
        lines.push(s.slice(0, size));
        s = s.slice(size);
    }
    if (s.length && lines.length) {
        const last = lines[lines.length - 1];
        lines[lines.length - 1] = last.slice(0, Math.max(1, size - 1)) + "…";
    }
    return lines;
}
function svgCover(title, author) {
    const lines = wrapTitle(title);
    const cjk = cjkCount(title) > 0;
    const size = cjk ? 64 : 48;
    const block = lines.length * (size + 18);
    const y0 = Math.max(220, 620 - block / 2);
    const tspans = lines
        .map((line, i) => `<tspan x="450" y="${y0 + i * (size + 18)}">${escapeXml(line)}</tspan>`)
        .join("");
    const who = author.trim();
    return (`<?xml version="1.0" encoding="UTF-8"?>` +
        `<svg xmlns="http://www.w3.org/2000/svg" width="900" height="1350" viewBox="0 0 900 1350">` +
        `<rect width="900" height="1350" fill="#241c16"/>` +
        `<rect x="56" y="56" width="788" height="1238" fill="none" stroke="#8f2d2a" stroke-width="3"/>` +
        `<rect x="72" y="72" width="756" height="1206" fill="none" stroke="#8f2d2a" stroke-width="1"/>` +
        `<text fill="#f3eadf" font-family="Songti SC, Noto Serif SC, serif" font-size="${size}" text-anchor="middle">${tspans}</text>` +
        (who
            ? `<text x="450" y="1120" fill="#c4a3a1" font-family="Songti SC, Noto Serif SC, serif" font-size="28" text-anchor="middle">${escapeXml(who)}</text>`
            : "") +
        `<rect x="706" y="1168" width="86" height="86" fill="#8f2d2a"/>` +
        `<text x="749" y="1226" fill="#f8efe8" font-family="Songti SC, Noto Serif SC, serif" font-size="42" text-anchor="middle">墨</text>` +
        `</svg>`);
}
function cleanUtf16(str) {
  if (!str) return "";
  // 去掉非法代理对，避免 encodeURIComponent / TextEncoder 炸
  return str.replace(/[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/g, "");
}

function utf8Encode(str) {
  str = cleanUtf16(str || "");
  if (typeof TextEncoder !== "undefined") {
    try { return new TextEncoder().encode(str); } catch (e) {}
  }
  try {
    const s = encodeURIComponent(str).replace(/%([0-9A-F]{2})/g, (_, hex) => String.fromCharCode(Number.parseInt(hex, 16)));
    const out = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
    return out;
  } catch (e) {
    // 最后兜底：直接按 charCode 截断到字节
    const out = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) out[i] = str.charCodeAt(i) & 0xff;
    return out;
  }
}
function svgCoverBytes(title, author) {
    return utf8Encode(svgCover(title, author));
}
function uint8ToBase64(u8) {
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let result = "";
    let i = 0;
    const len = u8.length;
    while (i < len) {
        const a = u8[i++] || 0;
        const b = i < len ? u8[i++] : 0;
        const c = i < len ? u8[i++] : 0;
        const triple = (a << 16) | (b << 8) | c;
        result += chars[(triple >> 18) & 63];
        result += chars[(triple >> 12) & 63];
        result += i - 2 < len ? chars[(triple >> 6) & 63] : "=";
        result += i - 1 < len ? chars[triple & 63] : "=";
    }
    return result;
}
const CRC_TABLE = (() => {
    const t = new Uint32Array(256);
    for (let i = 0; i < 256; i++) {
        let c = i;
        for (let k = 0; k < 8; k++)
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        t[i] = c >>> 0;
    }
    return t;
})();
function crc32(data) {
    let c = 0xffffffff;
    for (let i = 0; i < data.length; i++)
        c = CRC_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
}
function concatBytes(parts) {
    let n = 0;
    for (const p of parts)
        n += p.length;
    const out = new Uint8Array(n);
    let o = 0;
    for (const p of parts) {
        out.set(p, o);
        o += p.length;
    }
    return out;
}
function buildZip(files) {
    var _a;
    const dosDate = ((2026 - 1980) << 9) | (1 << 5) | 1;
    const locals = [];
    const centrals = [];
    let offset = 0;
    for (const f of files) {
        const nameBytes = utf8Encode(f.name);
        const crc = crc32(f.data);
        const local = new Uint8Array(30 + nameBytes.length);
        const dv = new DataView(local.buffer);
        dv.setUint32(0, 0x04034b50, true);
        dv.setUint16(4, 20, true);
        dv.setUint16(6, 0, true);
        dv.setUint16(8, 0, true);
        dv.setUint16(10, 0, true);
        dv.setUint16(12, dosDate, true);
        dv.setUint32(14, crc, true);
        dv.setUint32(18, f.data.length, true);
        dv.setUint32(22, f.data.length, true);
        dv.setUint16(26, nameBytes.length, true);
        dv.setUint16(28, 0, true);
        local.set(nameBytes, 30);
        locals.push(local, f.data);
        const central = new Uint8Array(46 + nameBytes.length);
        const cv = new DataView(central.buffer);
        cv.setUint16(4, 0x031e, true);
        cv.setUint32(0, 0x02014b50, true);
        cv.setUint16(6, 20, true);
        cv.setUint16(8, 0, true);
        cv.setUint16(10, 0, true);
        cv.setUint16(12, 0, true);
        cv.setUint16(14, dosDate, true);
        cv.setUint32(16, crc, true);
        cv.setUint32(20, f.data.length, true);
        cv.setUint32(24, f.data.length, true);
        cv.setUint16(28, nameBytes.length, true);
        cv.setUint16(30, 0, true);
        cv.setUint16(32, 0, true);
        cv.setUint16(34, 0, true);
        cv.setUint16(36, 0, true);
        cv.setUint32(38, (((_a = f.mode) !== null && _a !== void 0 ? _a : 0o644) << 16) >>> 0, true);
        cv.setUint32(42, offset, true);
        central.set(nameBytes, 46);
        centrals.push(central);
        offset += local.length + f.data.length;
    }
    let centralSize = 0;
    for (const c of centrals)
        centralSize += c.length;
    const eocd = new Uint8Array(22);
    const ev = new DataView(eocd.buffer);
    ev.setUint32(0, 0x06054b50, true);
    ev.setUint16(8, files.length, true);
    ev.setUint16(10, files.length, true);
    ev.setUint32(12, centralSize, true);
    ev.setUint32(16, offset, true);
    return concatBytes([...locals, ...centrals, eocd]);
}
function mediaType(name) {
    const n = name.toLowerCase();
    if (n.endsWith(".png"))
        return "image/png";
    if (n.endsWith(".jpg") || n.endsWith(".jpeg"))
        return "image/jpeg";
    if (n.endsWith(".svg"))
        return "image/svg+xml";
    if (n.endsWith(".gif"))
        return "image/gif";
    if (n.endsWith(".webp"))
        return "image/webp";
    return "application/octet-stream";
}
const EPUB_CSS = `body{font-family:"Songti SC","STSong","Noto Serif CJK SC","Source Han Serif SC",serif;line-height:1.75;margin:8%;}
h1{font-size:1.35em;font-weight:normal;text-align:center;margin:1.2em 0 1.5em;line-height:1.4;}
p{text-indent:2em;margin:0.35em 0;}
.coverpage{margin:0;padding:0;}
.coverwrap{margin:0;padding:0;text-align:center;}
.coverwrap img{width:100%;height:auto;}
`;
function navTree(sections) {
    const root = [];
    let vol = null;
    for (const s of sections) {
        const item = { title: s.title, href: s.id + ".xhtml", children: [] };
        if (s.kind === "volume") {
            root.push(item);
            vol = item;
        }
        else if (vol && s.kind !== "front")
            vol.children.push(item);
        else {
            root.push(item);
            if (s.kind === "front")
                vol = null;
        }
    }
    return root;
}
function navOl(items) {
    if (!items.length)
        return "";
    return ("<ol>" +
        items
            .map((it) => "<li><a href=\"" +
            escapeXml(it.href) +
            "\">" +
            escapeXml(it.title) +
            "</a>" +
            (it.children.length ? navOl(it.children) : "") +
            "</li>")
            .join("") +
        "</ol>");
}
function ncxPoints(items, state) {
    return items
        .map((it) => {
        const id = ++state.n;
        const kids = it.children.length ? ncxPoints(it.children, state) : "";
        return ('<navPoint id="np' +
            id +
            '" playOrder="' +
            id +
            '"><navLabel><text>' +
            escapeXml(it.title) +
            "</text></navLabel><content src=\"" +
            escapeXml(it.href) +
            "\"/>" +
            kids +
            "</navPoint>");
    })
        .join("");
}
function xhtml(title, lang, body, cover = false) {
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="' +
        lang +
        '" lang="' +
        lang +
        '"><head><meta charset="utf-8"/><title>' +
        escapeXml(title) +
        '</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body' +
        (cover ? ' class="coverpage"' : "") +
        ">" +
        body +
        "</body></html>");
}
function renderEpub(opts) {
    const lang = opts.language || "zh-CN";
    const title = opts.title.trim() || "未名";
    const author = opts.author.trim() || "佚名";
    const sections = opts.sections.length
        ? opts.sections
        : [{ id: "c001", title: lang === "zh-CN" ? "正文" : "Text", kind: "chapter", html: "<p>&#160;</p>" }];
    const uid = "urn:mofen:" + crc32(utf8Encode(title + "\n" + sections.length + "\n" + author)).toString(16);
    const modified = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const files = [];
    files.push({ name: "mimetype", data: utf8Encode("application/epub+zip") });
    files.push({
        name: "META-INF/container.xml",
        data: utf8Encode('<?xml version="1.0" encoding="UTF-8"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'),
    });
    const manifest = [
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>',
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '<item id="css" href="style.css" media-type="text/css"/>',
    ];
    const spine = [];
    const coverName = opts.cover && opts.cover.length ? opts.coverName || "cover.jpg" : "";
    if (coverName && opts.cover) {
        const base = coverName.replace(/^.*[\\/]/, "");
        files.push({ name: "OEBPS/" + base, data: opts.cover });
        manifest.push('<item id="cover-img" href="' +
            escapeXml(base) +
            '" media-type="' +
            mediaType(base) +
            '" properties="cover-image"/>');
        manifest.push('<item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>');
        spine.push('<itemref idref="cover"/>');
        files.push({
            name: "OEBPS/cover.xhtml",
            data: utf8Encode(xhtml("封面", lang, '<div class="coverwrap"><img src="' + escapeXml(base) + '" alt="' + escapeXml(title) + '"/></div>', true)),
        });
    }
    for (const s of sections) {
        manifest.push('<item id="' + s.id + '" href="' + s.id + '.xhtml" media-type="application/xhtml+xml"/>');
        spine.push('<itemref idref="' + s.id + '"/>');
        files.push({
            name: "OEBPS/" + s.id + ".xhtml",
            data: utf8Encode(xhtml(s.title, lang, "<h1>" + escapeXml(s.title) + "</h1>\n" + s.html)),
        });
    }
    const tree = navTree(sections);
    files.push({
        name: "OEBPS/nav.xhtml",
        data: utf8Encode('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="' +
            lang +
            '" lang="' +
            lang +
            '"><head><meta charset="utf-8"/><title>目录</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body><nav epub:type="toc" id="toc"><h1>目录</h1>' +
            navOl(tree) +
            "</nav></body></html>"),
    });
    files.push({
        name: "OEBPS/toc.ncx",
        data: utf8Encode('<?xml version="1.0" encoding="UTF-8"?>\n<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head><meta name="dtb:uid" content="' +
            escapeXml(uid) +
            '"/><meta name="dtb:depth" content="2"/><meta name="dtb:totalPageCount" content="0"/><meta name="dtb:maxPageNumber" content="0"/></head><docTitle><text>' +
            escapeXml(title) +
            "</text></docTitle><navMap>" +
            ncxPoints(tree, { n: 0 }) +
            "</navMap></ncx>"),
    });
    files.push({ name: "OEBPS/style.css", data: utf8Encode(EPUB_CSS) });
    const coverMeta = coverName ? '<meta name="cover" content="cover-img"/>' : "";
    const guide = coverName ? '<guide><reference type="cover" title="封面" href="cover.xhtml"/></guide>' : "";
    files.push({
        name: "OEBPS/content.opf",
        data: utf8Encode('<?xml version="1.0" encoding="UTF-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid" version="3.0" xml:lang="' +
            lang +
            '"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">' +
            escapeXml(uid) +
            "</dc:identifier><dc:title>" +
            escapeXml(title) +
            "</dc:title><dc:creator>" +
            escapeXml(author) +
            "</dc:creator><dc:language>" +
            lang +
            '</dc:language><dc:publisher>墨分</dc:publisher><meta property="dcterms:modified">' +
            modified +
            "</meta>" +
            coverMeta +
            "</metadata><manifest>" +
            manifest.join("") +
            '</manifest><spine toc="ncx">' +
            spine.join("") +
            "</spine>" +
            guide +
            "</package>"),
    });
    return buildZip(files);
}
function epubDownloadName(filename) {
    const base = filename.replace(/^.*[\\/]/, "").replace(/\.txt$/i, "") || "未名";
    return base + ".epub";
}

function isNullish(v) {
  if (v === null || v === undefined) return true;
  try {
    if (v.isKindOfClass && v.isKindOfClass($.NSNull)) return true;
  } catch (e) {}
  return false;
}

function jsString(value) {
  if (isNullish(value)) return "";
  try {
    var unwrapped = ObjC.unwrap(value);
    if (isNullish(unwrapped)) return "";
    return String(unwrapped);
  } catch (e) {
    return "";
  }
}

function asList(ns) {
  if (isNullish(ns)) return [];
  try {
    var arr = ObjC.unwrap(ns);
    if (arr && typeof arr.length === "number") return arr;
    if (isNullish(ns.count)) return [];
    var n = ns.count;
    if (typeof n !== "number" || n < 0) return [];
    var out = [];
    for (var i = 0; i < n; i++) out.push(jsString(ns.objectAtIndex(i)));
    return out;
  } catch (e) {
    return [];
  }
}

function runTask(bin, args) {
  var task = $.NSTask.alloc.init;
  try {
    task.executableURL = $.NSURL.fileURLWithPath(bin);
    task.arguments = $(args);
    task.launchAndReturnError(null);
    task.waitUntilExit();
    return task.terminationStatus === 0;
  } catch (err) {
    try {
      task.setLaunchPath(bin);
      task.setArguments($(args));
      task.launch();
      task.waitUntilExit();
      return task.terminationStatus === 0;
    } catch (err2) {
      return false;
    }
  }
}

function curlText(url) {
  var pipe = $.NSPipe.pipe();
  var task = $.NSTask.alloc.init;
  try {
    task.executableURL = $.NSURL.fileURLWithPath("/usr/bin/curl");
    task.arguments = $(["-fsSL", "--max-time", "12", "-A", "Mofen/1.0", url]);
    task.standardOutput = pipe;
    task.launchAndReturnError(null);
    task.waitUntilExit();
  } catch (err) {
    return "";
  }
  if (task.terminationStatus !== 0) return "";
  var data = pipe.fileHandleForReading.readDataToEndOfFile();
  if (!data) return "";
  var text = $.NSString.alloc.initWithDataEncoding(data, 4);
  return jsString(text);
}

function normName(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/[\s\u3000《》【】\[\]（）()：:，,。.!！？?·\-—_]/g, "");
}

function closeEnough(query, title) {
  var a = normName(query);
  var b = normName(title);
  if (!a || !b) return false;
  if (a.length <= 1) return a === b;
  return a === b || b.indexOf(a) >= 0 || a.indexOf(b) >= 0;
}

function upgradeUrl(url) {
  if (!url) return "";
  var u = String(url);
  if (u.indexOf("//") === 0) u = "https:" + u;
  if (u.indexOf("http://") === 0) u = "https://" + u.slice(7);
  return u.replace("zoom=1", "zoom=2").replace("&edge=curl", "");
}

function searchCoverUrl(title, author) {
  var found = [];
  function add(url, name, source) {
    url = upgradeUrl(url);
    if (!url || url.indexOf("https://") !== 0) return;
    if (!closeEnough(title, name)) return;
    found.push(url);
  }
  try {
    var g = JSON.parse(
      curlText(
        "https://www.googleapis.com/books/v1/volumes?q=" +
          encodeURIComponent("intitle:" + title) +
          "&maxResults=4&printType=books",
      ) || "null",
    );
    var items = (g && g.items) || [];
    for (var i = 0; i < items.length; i++) {
      var info = items[i].volumeInfo || {};
      var links = info.imageLinks || {};
      add(links.thumbnail || links.small || links.smallThumbnail, info.title, "Google Books");
    }
  } catch (err) {}
  if (found.length) return found[0];
  try {
    var it = JSON.parse(
      curlText(
        "https://itunes.apple.com/search?media=ebook&limit=5&term=" +
          encodeURIComponent(author ? title + " " + author : title),
      ) || "null",
    );
    var results = (it && it.results) || [];
    for (var j = 0; j < results.length; j++) {
      var art = results[j].artworkUrl100 || "";
      add(art.replace("100x100bb", "600x600bb"), results[j].trackName, "Apple Books");
    }
  } catch (err2) {}
  if (found.length) return found[0];
  try {
    var ol = JSON.parse(curlText("https://openlibrary.org/search.json?limit=5&title=" + encodeURIComponent(title)) || "null");
    var docs = (ol && ol.docs) || [];
    for (var k = 0; k < docs.length; k++) {
      if (!docs[k].cover_i) continue;
      add("https://covers.openlibrary.org/b/id/" + docs[k].cover_i + "-L.jpg", docs[k].title, "Open Library");
    }
  } catch (err3) {}
  return found.length ? found[0] : "";
}

function imageKind(path) {
  var data = $.NSData.dataWithContentsOfFile($(path));
  if (!data || data.length < 32) return "";
  var sub = data.subdataWithRange($.NSMakeRange(0, 12));
  var b64 = jsString(sub.base64EncodedStringWithOptions(0));
  if (b64.indexOf("/9j/") === 0) return "jpg";
  if (b64.indexOf("iVBOR") === 0) return "png";
  return "";
}

function bytesFromFile(path) {
  var data = $.NSData.dataWithContentsOfFile($(path));
  if (!data) return null;
  var b64 = jsString(data.base64EncodedStringWithOptions(0));
  if (!b64) return null;
  var bin = atob(b64);
  var u8 = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  return u8;
}

function drawCover(title, author, path) {
  try {
    ObjC.import("Cocoa");
    var W = 900;
    var H = 1350;
    var img = $.NSImage.alloc.initWithSize($.NSMakeSize(W, H));
    img.lockFocus();
    $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0.14, 0.11, 0.09, 1).setFill();
    $.NSRectFill($.NSMakeRect(0, 0, W, H));
    var accent = $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0.56, 0.18, 0.16, 1);
    accent.setStroke();
    var border = $.NSBezierPath.bezierPathWithRect($.NSMakeRect(48, 48, W - 96, H - 96));
    border.setLineWidth(3);
    border.stroke();
    var inner = $.NSBezierPath.bezierPathWithRect($.NSMakeRect(64, 64, W - 128, H - 128));
    inner.setLineWidth(1);
    inner.stroke();
    var para = $.NSMutableParagraphStyle.alloc.init;
    para.alignment = $.NSTextAlignmentCenter;
    var font = $.NSFont.fontWithNameSize("Songti SC", 64);
    if (!font) font = $.NSFont.fontWithNameSize("PingFangSC-Regular", 56);
    if (!font) font = $.NSFont.systemFontOfSize(56);
    var attrs = $.NSDictionary.dictionaryWithObjectsForKeys(
      [font, $.NSColor.colorWithCalibratedWhiteAlpha(0.95, 1), para],
      [$.NSFontAttributeName, $.NSForegroundColorAttributeName, $.NSParagraphStyleAttributeName],
    );
    var shown = title || "未名";
    if (shown.length > 48) shown = shown.slice(0, 47) + "…";
    var str = $.NSString.alloc.initWithString(shown);
    str.drawInRectWithAttributes($.NSMakeRect(90, 420, W - 180, 620), attrs);
    if (author) {
      var font2 = $.NSFont.fontWithNameSize("PingFangSC-Regular", 28) || $.NSFont.systemFontOfSize(28);
      var attrs2 = $.NSDictionary.dictionaryWithObjectsForKeys(
        [font2, accent, para],
        [$.NSFontAttributeName, $.NSForegroundColorAttributeName, $.NSParagraphStyleAttributeName],
      );
      var a = $.NSString.alloc.initWithString(author);
      a.drawInRectWithAttributes($.NSMakeRect(90, 240, W - 180, 80), attrs2);
    }
    img.unlockFocus();
    var tiff = img.TIFFRepresentation;
    var rep = $.NSBitmapImageRep.imageRepWithData(tiff);
    var png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $.NSDictionary.dictionary);
    return png.writeToFileAtomically($(path), true);
  } catch (err) {
    return false;
  }
}

function pickCover(title, author) {
  // 外置盘环境下网络搜索和部分 AppKit 调用容易返回 NSNull，直接走本地绘图/SVG
  try {
    var pngPath = jsString($.NSTemporaryDirectory()) + "mofen-draw-" + Date.now() + ".png";
    if (drawCover(title, author, pngPath)) {
      var drawn = bytesFromFile(pngPath);
      try { $.NSFileManager.defaultManager.removeItemAtPathError($(pngPath), null); } catch(e) {}
      if (drawn && drawn.length > 100) return { bytes: drawn, name: "cover.png", source: "墨印" };
    }
  } catch (e) {
    console.log("  本地绘图失败，改用 SVG：" + e);
  }
  try {
    return { bytes: svgCoverBytes(title, author || ""), name: "cover.svg", source: "墨印" };
  } catch (e2) {
    console.log("  SVG 也失败：" + e2);
    // 最小兜底
    return { bytes: new Uint8Array(0), name: "cover.svg", source: "无" };
  }
}

function readText(path) {
  // 先尝试 Foundation
  var encs = [4, 10];
  try {
    encs.push($.CFStringConvertEncodingToNSStringEncoding(0x0632));
    encs.push($.CFStringConvertEncodingToNSStringEncoding(0x0631));
  } catch (err) {}
  for (var i = 0; i < encs.length; i++) {
    try {
      var ns = $.NSString.stringWithContentsOfFileEncodingError($(path), encs[i], null);
      if (isNullish(ns)) continue;
      var s = jsString(ns);
      if (s && s.length > 0) return s;
    } catch (e) {}
  }
  // 后备：用 shell cat + iconv 尝试常见编码
  try {
    var task = $.NSTask.alloc.init;
    task.setLaunchPath("/bin/cat");
    task.setArguments($( [path] ));
    var pipe = $.NSPipe.pipe;
    task.setStandardOutput(pipe);
    task.setStandardError($.NSPipe.pipe);
    task.launch();
    task.waitUntilExit();
    var data = pipe.fileHandleForReading.readDataToEndOfFile;
    if (isNullish(data) || !data || data.length === 0) return "";
    var encodings = [$.NSUTF8StringEncoding, 10];
    try { encodings.push($.CFStringConvertEncodingToNSStringEncoding(0x0632)); } catch(e){}
    for (var j = 0; j < encodings.length; j++) {
      try {
        var str = $.NSString.alloc.initWithDataEncoding(data, encodings[j]);
        if (!isNullish(str)) {
          var t = jsString(str);
          if (t && t.length > 10) return t;
        }
      } catch (e) {}
    }
  } catch (e) {}
  return "";
}

function writeBytes(path, u8) {
  var b64 = uint8ToBase64(u8);
  var data = $.NSData.alloc.initWithBase64EncodedStringOptions($(b64), 0);
  if (!data) return false;
  return !!data.writeToFileAtomically($(path), true);
}

function removeGenerated(path) {
  if (!/\.epub$/i.test(path) && !/\.writing$/i.test(path)) return;
  $.NSFileManager.defaultManager.removeItemAtPathError($(path), null);
}

function findTxtFiles(root) {
  try {
    var listPath = jsString($.NSProcessInfo.processInfo.environment.objectForKey($("MOFEN_TXTLIST")));
    if (!listPath) {
      console.log("没有预扫描列表");
      return [];
    }
    var ns = $.NSString.stringWithContentsOfFileEncodingError($(listPath), $.NSUTF8StringEncoding, null);
    var text = jsString(ns);
    if (!text) return [];
    return text.split(/\r?\n/).filter(function(p) { return p && p.length > 4; });
  } catch (e) {
    console.log("读取列表失败：" + e);
    return [];
  }
}

function walk(dir, out) {
  var files = findTxtFiles(dir);
  for (var i = 0; i < files.length; i++) {
    out.push(files[i]);
  }
}

function convertOne(path) {
var text = "";
  try { text = readText(path); } catch (e) { console.log("  readText 异常：" + e); return false; }
  if (!text || !normName(text)) {
    console.log("  跳过：读不到文本，或文件是空的");
    return false;
  }
  text = cleanUtf16(text);
var base = path.split("/").pop();
  var meta = parseBookMeta(base);
var analysis;
  try { analysis = analyzeText(text); } catch (e) { console.log("  analyzeText 异常：" + e); return false; }
  if (analysis.regexError) {
    console.log("  跳过：" + analysis.regexError);
    return false;
  }
var cover;
  try { cover = pickCover(meta.title, meta.author); } catch (e) { console.log("  pickCover 异常：" + e); return false; }
  console.log("  目录 " + analysis.kept.length + " 条，剔除 " + analysis.dropped.length + " 条，封面 " + cover.source);
  var epub = renderEpub({
    title: meta.title,
    author: meta.author || "佚名",
    sections: analysis.sections,
    cover: cover.bytes,
    coverName: cover.name,
    language: analysis.language,
  });
  var finalPath = path.replace(/\.txt$/i, ".epub");
  if (finalPath === path || !/\.epub$/i.test(finalPath)) return false;
  var partial = finalPath + ".writing";
  if (!writeBytes(partial, epub)) {
    removeGenerated(partial);
    console.log("  写入失败");
    return false;
  }
  if ($.NSFileManager.defaultManager.fileExistsAtPath($(finalPath))) removeGenerated(finalPath);
  var moved = $.NSFileManager.defaultManager.moveItemAtPathToPathError($(partial), $(finalPath), null);
  if (!moved) {
    removeGenerated(partial);
    console.log("  无法放到 txt 旁边");
    return false;
  }
  // 转换成功，删除原 txt
  try {
    $.NSFileManager.defaultManager.removeItemAtPathError($(path), null);
    console.log("  已删除原文件");
  } catch (e) {
    console.log("  epub 已生成，但删除原文件失败：" + e);
  }
  return true;
}

function main() {
  ObjC.import("Foundation");
  ObjC.import("CoreFoundation");
  var root = jsString($.NSProcessInfo.processInfo.environment.objectForKey($("MOFEN_ROOT")));
  if (!root) {
    console.log("没有找到程序所在的文件夹。");
    return;
  }
  console.log("墨分正在扫描：" + root);
  var files = [];
  walk(root, files);
  files.sort();
  if (!files.length) {
    console.log("这个文件夹里没有 txt。请把「开始转换.command」放进小说所在文件夹，或它的上层，再双击。");
    return;
  }
  var ok = 0;
  var bad = 0;
  for (var i = 0; i < files.length; i++) {
    console.log("[" + (i + 1) + "/" + files.length + "] " + files[i]);
    try {
      if (convertOne(files[i])) ok++;
      else bad++;
    } catch (err) {
      bad++;
      console.log("  失败：" + err);
    }
  }
  console.log("");
  console.log("完成。成功 " + ok + " 本，失败 " + bad + " 本。");
  console.log("epub 已放在各自的 txt 旁边，原 txt 已删除。");
}

main();

___MOFEN_SCRIPT_END___
rm -f "$TMPLIST" 2>/dev/null
echo
read -r -p "按回车键关闭窗口…" _
