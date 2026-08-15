#!/usr/bin/env python3
"""Final targeted cleanup for kaoyan_v3.json.

This pass deliberately avoids rebuilding the dictionary.  It applies only
source-checked or otherwise unambiguous fixes, scans all 5,847 meanings for
hard textbook-pollution markers, suspicious exact duplicates, neighbour
shifts and conservative part-of-speech conflicts, then validates a
deterministic random sample of 100 unchanged words.
"""

from __future__ import annotations

import argparse
import copy
import json
import random
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "蒸馏" / "output" / "kaoyan_v3.json"
DEFAULT_PDF = ROOT / "蒸馏" / "2027红宝书.pdf"
DEFAULT_OUTPUT = ROOT / "蒸馏" / "output"

HARD_POLLUTION_RE = re.compile(
    r"【(?:\d{4})?年?考研(?:英译汉|完形|阅读)|【考研英译汉】|"
    r"【句意】|【解析】|【试题分析】|本题|请.?登[陆录]|红宝书网站|增值服务|检索表"
)
POS_RE = re.compile(
    r"^(?:n|v|vt|vi|adj|adv|prep|conj|pron|modal|aux|det|art|num|int)\.", re.I
)


@dataclass(frozen=True)
class Fix:
    meaning: str
    reason: str
    category: str
    source_basis: str
    pos_correction: bool = False


def f(
    meaning: str,
    reason: str,
    category: str,
    source_basis: str = "回查《2027红宝书》对应词条及相邻版面",
    pos_correction: bool = False,
) -> Fix:
    return Fix(meaning, reason, category, source_basis, pos_correction)


# Only unambiguous, source-checked corrections belong here.  Entries that are
# merely verbose or stylistically uneven are intentionally absent.
FIXES: dict[str, Fix] = {
    # User-confirmed final-pass targets.
    "massive": f("adj. 大而重的；厚实的；粗大的；大规模的；大量的", "释义串入 size/large 等辨析正文", "neighbor_shift"),
    "vague": f("adj. 含糊的；不明确的；模糊的", "释义串入 take 的多组词义", "neighbor_shift"),
    "public": f("adj. 公开的；公共的；平民的；大众的；n. 平民；百姓；公众", "整条被真题英译汉正文覆盖", "textbook_pollution"),
    "being": f("n. 生物；人；存在；生命", "整条被丝绸之路真题例句覆盖", "textbook_pollution"),
    "pleasure": f("n. 愉快；快乐；乐事；乐趣", "整条被考研完形正文覆盖", "textbook_pollution"),
    "threshold": f("n. 门槛；入门；开端", "整条被考研完形正文覆盖", "textbook_pollution"),
    "lie": f("n. 谎话；谎言；vi. 说谎；躺；位于", "整条被考古真题正文覆盖", "textbook_pollution"),
    "entry": f("n. 进入；入口；通道；记载；条目", "整条被高等教育真题正文覆盖", "textbook_pollution"),
    "resemble": f("vt. 像；类似", "整条被考研完形正文覆盖", "textbook_pollution"),
    "return": f("v. 返回；归还；恢复；n. 返回；归还；回报；收益", "整条被论文引用真题正文覆盖", "textbook_pollution"),
    "shore": f("n. 岸；海岸；滨", "整条被移民真题正文覆盖", "textbook_pollution"),
    "copious": f("adj. 大量的；丰富的；充裕的", "整条被档案馆真题正文覆盖", "textbook_pollution"),
    "beautiful": f("adj. 美丽的；漂亮的；美好的", "释义串到 walk/step", "neighbor_shift"),
    "few": f("adj./pron. 很少的；不多的；少数", "释义混入 approach/tackle", "neighbor_shift"),
    "forest": f("n. 森林；林区", "释义混入 reflection/reflect", "neighbor_shift"),
    "handsome": f("adj. 英俊的；漂亮的；可观的；大方的", "释义混入 complement", "neighbor_shift"),
    "team": f("n. 队；组；团队；v. 合作", "释义串到 part", "neighbor_shift"),
    "cruise": f("n. 海上航游；乘船游览；vi. 巡游；以中等速度行进", "释义串到 first/first-class", "neighbor_shift"),
    "backdrop": f("n. 背景；背景幕布", "整条被《博兹札记》阅读正文覆盖", "textbook_pollution"),
    "inherited": f("adj. 继承的；遗传的", "整条被继承财富阅读正文覆盖", "textbook_pollution"),
    "create": f("vt. 创造；创作；引起；造成；封（爵）", "释义完全复制自 fabricate", "neighbor_shift"),
    "plentiful": f("adj. 丰富的；充足的；大量的", "与 wealthy 完全重复且遗漏充足、大量义", "duplicate_semantic"),
    "inaugurate": f("v. 为……举行就职典礼；为……举行落成仪式；引进；开创；开始", "动词误标为 n.", "pos_conflict", pos_correction=True),

    # Additional high-confidence residuals found by the full 5,847-word scan.
    "highly": f("adv. 高度地；很；非常；赞许地", "释义混入 unrelated adjective 内容", "neighbor_shift"),
    "climb": f("n./v. 攀登；爬", "释义末尾串入 also", "neighbor_shift"),
    "remarkable": f("adj. 非凡的；显著的；引人注目的", "释义串入 contribution/donation", "neighbor_shift"),
    "article": f("n. 文章；论文；物品；商品；项目；条款；冠词", "释义串到 protocol", "neighbor_shift"),
    "by": f("prep. 在……旁；被；由；经；通过；adv. 经过；在旁边", "基础词释义串入 majority/legal age", "neighbor_shift"),
    "afternoon": f("n. 下午", "释义末尾串入 otherwise", "neighbor_shift"),
    "almost": f("adv. 几乎；差不多", "释义末尾串入 wonder", "neighbor_shift"),
    "another": f("det./pron. 另一个；再一个", "释义串入 custom", "neighbor_shift"),
    "irrigation": f("n. 灌溉", "释义串到 article", "neighbor_shift"),
    "combine": f("v. 结合；联合；化合", "释义混入 approvingly", "neighbor_shift"),
    "determine": f("v. 决定；决心；确定；限定", "当前内容是辨析判断而非词条释义", "textbook_residue"),
    "plot": f("n. 小块土地；情节；阴谋；v. 密谋；绘制", "释义串到 manipulate", "neighbor_shift"),
    "remember": f("v. 记得；回想起；不忘记；代……问候", "释义仅剩引文且尾部残缺", "incomplete_example"),
    "psychology": f("n. 心理学；心理；心理特征", "释义串到 habitat", "neighbor_shift"),
    "spread": f("v. 伸展；展开；散布；传播；蔓延；n. 传播；范围", "释义串到 background", "neighbor_shift"),
    "staff": f("n. 全体职员；行政人员；杖；棒；v. 配备人员", "释义混入 anxiety/worry", "neighbor_shift"),
    "project": f("v. 放映；投射；规划；预计；n. 工程；项目；计划", "释义混入无关格言且主释义残缺", "neighbor_shift"),
    "program": f("n. 程序；节目；计划；方案；v. 编程；安排", "meaning 仅剩完整教材例句", "incomplete_example"),
    "promote": f("vt. 促进；增进；提升；提拔；宣传", "释义末尾串入 legal", "neighbor_shift"),
    "nearby": f("adj. 附近的；adv. 在附近；prep. 在……附近", "释义串到 current/trend", "neighbor_shift"),
    "childhood": f("n. 幼年；童年", "释义串到 transition/process", "neighbor_shift"),
    "sake": f("n. 缘故；理由", "释义末尾串入 assure/ensure", "neighbor_shift"),
    "to": f("prep. 到；向；对；对于；用于动词不定式", "基础词释义串入 favour", "neighbor_shift"),
    "launch": f("v. 发射；发动；使船下水；n. 发射；下水", "释义末尾串入 serious", "neighbor_shift"),
    "hard": f("adj. 硬的；坚固的；困难的；努力的；adv. 努力地；猛烈地", "释义串到 achieve", "neighbor_shift"),
    "if": f("conj. 如果；假使；是否", "基础连词释义残缺并混入乱码", "textbook_residue"),
    "school": f("n. 学校；上学；学院；学派；v. 教育", "释义混入无关引文", "neighbor_shift"),
    "trade": f("n. 贸易；商业；职业；v. 从事贸易；交换", "释义末尾串入 distraction", "neighbor_shift"),
    "arrange": f("v. 整理；排列；布置；安排；筹备", "当前内容是提取后的辨析判断", "textbook_residue"),
    "within": f("prep. 在……里面；在……以内；adv. 在内部", "释义末尾串入 opportunity", "neighbor_shift"),
    "blow": f("v. 吹；吹响；爆炸；n. 打击；吹", "释义串到 mission/delegation", "neighbor_shift"),
    "error": f("n. 错误；过失", "释义被认识论正文覆盖", "textbook_residue"),
    "and": f("conj. 和；与；同；又；然后", "基础连词仅剩例句", "incomplete_example"),
    "copper": f("n. 铜；铜制品；铜币", "释义末尾串入 battle", "neighbor_shift"),
    "mistake": f("n. 错误；过失；误解；v. 弄错；误认为", "释义末尾串入 cost estimate", "neighbor_shift"),
    "curb": f("n. 抑制；控制；马勒；v. 控制；约束", "释义串到 diminish", "neighbor_shift"),
    "trunk": f("n. 大衣箱；树干；躯干；汽车行李箱；象鼻", "释义串到 shadow", "neighbor_shift"),
    "customer": f("n. 顾客；客户", "释义串到 serve", "neighbor_shift"),
    "danger": f("n. 危险；危险的人或物", "meaning 仅剩完整例句", "incomplete_example"),
    "during": f("prep. 在……期间", "释义串到 fail", "neighbor_shift"),
    "front": f("n. 前面；正面；前线；adj. 前面的；v. 面向", "释义串到 conductor", "neighbor_shift"),
    "keep": f("v. 保持；保存；遵守；阻止；n. 生计", "meaning 仅剩完整例句", "incomplete_example"),
    "page": f("n. 页；页码；v. 翻页；呼叫", "释义串到 refer/inquiry", "neighbor_shift"),
    "speech": f("n. 演说；讲话；言语；说话能力", "释义串到 capital", "neighbor_shift"),
    "visit": f("n./v. 访问；参观；拜访", "释义末尾串入 nearby", "neighbor_shift"),
    "whether": f("conj. 是否；不管；无论", "meaning 仅剩完整例句", "incomplete_example"),
    "famous": f("adj. 著名的；出名的", "形容词被错误标为 art. 且释义属于 display", "pos_conflict", pos_correction=True),

    # Correct example-only entries that remain unusable as definitions.
    "imagination": f("n. 想象；想象力", "meaning 仅剩完整例句", "incomplete_example"),
    "policy": f("n. 政策；方针；原则", "meaning 仅剩完整例句", "incomplete_example"),
    "living": f("n. 生计；生活；adj. 活着的；现存的", "meaning 仅剩完整例句", "incomplete_example"),
    "priority": f("n. 优先；优先权；优先事项", "meaning 仅剩完整例句", "incomplete_example"),
    "property": f("n. 财产；所有物；性质；特性", "meaning 仅剩完整例句", "incomplete_example"),
    "raw": f("adj. 生的；未加工的；原始的；n. 原料", "meaning 仅剩完整例句", "incomplete_example"),
    "prefer": f("v. 更喜欢；宁愿", "meaning 仅剩完整例句", "incomplete_example"),

    # Defects found during the first 100-word unchanged-word spot check.
    "comprehend": f("v. 理解；领会", "动词误标为 adj.", "pos_conflict", pos_correction=True),
    "supplement": f("n. 增补；补充；增刊；副刊；v. 增补；补充", "名词和动词释义拼接但词性标记缺失", "textbook_residue"),
    "strong": f("adj. 强壮的；强大的；强烈的；坚固的", "释义串到 glare", "neighbor_shift"),
    "congratulate": f("v. 祝贺；向……道喜", "动词误标为 n.", "pos_conflict", pos_correction=True),
    "porcelain": f("n. 瓷；瓷器；adj. 瓷制的", "名词义被错误标为 adj.", "pos_conflict", pos_correction=True),
    "strange": f("adj. 奇怪的；陌生的", "meaning 仅剩完整例句", "incomplete_example"),
    "Buddhist": f("n. 佛教徒；adj. 佛教的", "meaning 仅剩完整例句", "incomplete_example"),
    "spider": f("n. 蜘蛛", "释义末尾串入 spokesman", "neighbor_shift"),
    "calcium": f("n. 钙", "OCR 导致释义残缺为“化钙”", "ocr_residue"),

    # Defects found during the second 100-word unchanged-word spot check.
    "grave": f("n. 坟墓；adj. 严肃的；庄重的；重大的", "名词和形容词释义被错误合并到 adj. 下", "pos_conflict", pos_correction=True),
    "pat": f("v. 轻拍；n. 轻拍；adj. 恰好的；合适的", "动词释义被错误标为 adj.", "pos_conflict", pos_correction=True),
    "racket": f("n. 喧闹；球拍；非法勾当", "释义混入无关的“考验”", "neighbor_shift"),
    "above": f("prep. 在……上方；高于；adv. 在上面；adj. 上述的", "当前释义“其他人或物”明显错配", "neighbor_shift"),
    "earth": f("n. 地球；世界；泥土；土壤；陆地", "释义混入语法说明残留", "textbook_residue"),
    "sneeze": f("n./v. 打喷嚏；喷嚏", "释义混入 sneer 的“轻视”", "neighbor_shift"),
    "antique": f("adj. 古老而珍贵的；古式的；n. 古物；古董", "形容词和名词释义被错误合并到 n. 下", "pos_conflict", pos_correction=True),

    # Defects found during the third 100-word unchanged-word spot check.
    "gravity": f("n. 重力；引力；严重性；庄重", "meaning 仅剩严重性的完整例句", "incomplete_example"),
    "vocal": f("adj. 声音的；有声的；口头的；歌唱的；n. 元音；声乐作品", "形容词误标为 v.", "pos_conflict", pos_correction=True),
    "hardly": f("adv. 几乎不；几乎没有", "释义串到 thickly/heavily", "neighbor_shift"),
    "poster": f("n. 海报；招贴", "释义串到 paste", "neighbor_shift"),
    "consent": f("n./v. 同意；赞成", "meaning 仅剩残缺例句", "incomplete_example"),
    "cat": f("n. 猫", "释义混入 means/approach", "neighbor_shift"),
    "more": f("adj./pron. 更多；更多的人或物；adv. 更；更加", "基础词释义残缺并混入数字", "textbook_residue"),
    "husbandry": f("n. 农牧业；耕作；饲养；经营管理", "释义末尾串到 publicity/hype", "neighbor_shift"),
    "chronicle": f("n. 编年史；v. 按时间顺序记述", "释义发生 OCR 拼接污染", "ocr_residue"),

    # Defects found during the fourth 100-word unchanged-word spot check.
    "voice": f("n. 声音；嗓音；语态；v. 说出；表达", "名词和动词释义被错误合并到 v. 下", "pos_conflict", pos_correction=True),
    "faculty": f("n. 才能；能力；全体教员；学院；系", "释义串到 dean", "neighbor_shift"),
    "alcohol": f("n. 酒精；含酒精饮料；酒", "meaning 仅剩完整例句", "incomplete_example"),
    "mushroom": f("n. 蘑菇；v. 迅速增长", "释义被蘑菇例句和 edible 辨析覆盖", "neighbor_shift"),
    "speed": f("n. 速度；迅速；v. 加速；快速行进", "meaning 仅剩谚语", "incomplete_example"),
    "fixation": f("n. 固定；固着；异常依恋；迷恋", "释义末尾串入 hiss/failure", "neighbor_shift"),
    "impossibility": f("n. 不可能；不可能做到的事情；无法实现或存在的情况", "释义末尾串入 poverty", "neighbor_shift"),

    # Defects found during the fifth 100-word unchanged-word spot check.
    "gather": f("v. 聚集；集合；收集；逐渐增加；推断", "当前释义属于 force/compel", "neighbor_shift"),
    "wound": f("n. 伤口；创伤；v. 使受伤；伤害", "整条被狄更斯阅读正文覆盖", "textbook_pollution"),
    "stereotype": f("n. 模式化形象；老一套；成见；v. 对……形成刻板印象", "释义串入 steward", "neighbor_shift"),
    "futurologist": f("n. 未来学家", "释义串入 gape", "neighbor_shift"),
    "multinational": f("adj. 多国的；跨国的；n. 跨国公司", "形容词和名词义被错误合并到 n. 下", "pos_conflict", pos_correction=True),

    # Defects found during the sixth 100-word unchanged-word spot check.
    "conceal": f("v. 隐藏；隐瞒；隐蔽", "动词误标为 n.", "pos_conflict", pos_correction=True),
    "cross": f("n. 十字形；十字架；v. 穿过；交叉；adj. 生气的；交叉的", "释义仅剩“圣乔治十字架”例词", "incomplete_example"),
    "filing": f("n. 存档；归档；档案；锉屑", "释义末尾混入 file 的“锉刀”", "neighbor_shift"),
    "forthright": f("adj. 直率的；直接的；坦诚的", "释义末尾串入 maker/creator", "neighbor_shift"),
    "nautical": f("adj. 航海的；船舶的；船员的", "形容词误标为 n.", "pos_conflict", pos_correction=True),
    "sustainable": f("adj. 可持续的；能长期维持的", "释义末尾串入 exchange", "neighbor_shift"),

    # Defects found during the seventh 100-word unchanged-word spot check.
    "concede": f("v. 承认；让出；承认失败", "动词误标为 n.", "pos_conflict", pos_correction=True),
    "lorry": f("n. 卡车；货运汽车", "释义串到 collision/clash", "neighbor_shift"),
    "nobody": f("pron. 没有人；n. 无足轻重的人", "释义串到 slide", "neighbor_shift"),
    "flexibility": f("n. 适应性；灵活性；弹性", "释义末尾串入 flip", "neighbor_shift"),
    "overly": f("adv. 过度地；太", "释义末尾串入 overpay", "neighbor_shift"),

    # Defects found during the eighth 100-word unchanged-word spot check.
    "nor": f("conj. 也不；又不", "连词误标为 n.", "pos_conflict", pos_correction=True),
    "nonverbal": f("adj. 非言语的；不用语言表达的", "形容词误标为 v.", "pos_conflict", pos_correction=True),
    "pervasive": f("adj. 弥漫的；渗透的；普遍的", "释义末尾串入 pesticide", "neighbor_shift"),

    # Defects found during the ninth 100-word unchanged-word spot check.
    "noteworthy": f("adj. 显著的；值得注意的", "形容词误标为 n.", "pos_conflict", pos_correction=True),
    "pharmaceutical": f("adj. 制药的；n. 药物；药品；药剂", "形容词和名词义未正确分隔", "pos_conflict", pos_correction=True),

    # OCR residue found during the tenth 100-word unchanged-word spot check.
    "overview": f("n. 概述；概观；总的看法", "释义尾部混入“计概述”OCR 残字", "ocr_residue"),
}


LEGITIMATE_DUPLICATE_GROUPS = {
    frozenset({"capable", "competent"}),
    frozenset({"gigantic", "enormous", "huge"}),
    frozenset({"energetic", "vigorous"}),
    frozenset({"toss", "throw"}),
    frozenset({"fortunate", "lucky"}),
    frozenset({"compose", "constitute"}),
    frozenset({"petrol", "gasoline/gasolene"}),
    frozenset({"skilled", "skillful"}),
    frozenset({"warehouse", "storehouse"}),
    frozenset({"pamphlet", "brochure"}),
    frozenset({"dove", "pigeon"}),
}

POS_SUFFIX_EXCEPTIONS = {
    "unlikely", "sly", "friendly", "lovely", "lonely", "likely", "lively", "daily", "early", "only",
    "silly", "ugly", "costly", "elderly", "orderly", "holy", "jolly", "family", "comply", "imply",
    "rely", "apply", "supply", "reply", "multiply", "fly", "rally", "belly", "bully", "ally",
    "assembly", "monopoly", "butterfly", "trolley/trolly", "bodily", "priestly", "timely", "weekly",
    "yearly", "deadly",
}
NOUN_SUFFIX_EXCEPTIONS = {
    "mention", "implement", "enhance", "commence", "freelance", "hence", "low-density", "dance", "envision",
}
ADJECTIVE_SUFFIX_EXCEPTIONS = {"bless", "handful", "bible", "doubtless", "nevertheless", "regardless"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUTPUT)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError(f"UTF-8 BOM is not allowed: {path}")
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("words"), list):
        raise ValueError("expected an object containing a words list")
    return data


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def normalized_meaning(text: str) -> str:
    return re.sub(r"[\s，。；：、,.!?！？（）()【】\[\]…·~～]+", "", text.lower())


def exact_duplicate_groups(words: list[dict[str, Any]]) -> list[dict[str, Any]]:
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in words:
        groups[normalized_meaning(record["meaning"])].append(record)
    result: list[dict[str, Any]] = []
    for normalized, records in groups.items():
        if not normalized or len(records) < 2:
            continue
        word_set = frozenset(record["word"] for record in records)
        result.append(
            {
                "words": [record["word"] for record in records],
                "positions": [record["position"] for record in records],
                "meaning": records[0]["meaning"],
                "classification": "legitimate" if word_set in LEGITIMATE_DUPLICATE_GROUPS else "suspicious",
            }
        )
    return sorted(result, key=lambda item: item["positions"])


def conservative_pos_conflict(word: str, meaning: str) -> str:
    lower = word.lower()
    match = POS_RE.match(meaning.strip())
    if not match:
        return ""
    pos = match.group(0).lower()
    if lower.endswith("ly") and lower not in POS_SUFFIX_EXCEPTIONS and not pos.startswith("adv"):
        return "-ly 词形与当前词性冲突"
    if (
        re.search(r"(tion|sion|ment|ness|ity|ship|ance|ence|ism|hood)$", lower)
        and lower not in NOUN_SUFFIX_EXCEPTIONS
        and not pos.startswith("n")
    ):
        return "名词后缀与当前词性冲突"
    if (
        re.search(r"(ous|ful|less|ible)$", lower)
        and lower not in ADJECTIVE_SUFFIX_EXCEPTIONS
        and not pos.startswith("adj")
    ):
        return "形容词后缀与当前词性冲突"
    if re.search(r"(ize|ify|fy)$", lower) and lower not in {"outsize", "oversize", "prize"} and not pos.startswith(("v", "vt", "vi")):
        return "动词后缀与当前词性冲突"
    return ""


def apply_fixes(data: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    revised = copy.deepcopy(data)
    changes: list[dict[str, Any]] = []
    seen: set[str] = set()
    for record in revised["words"]:
        fix = FIXES.get(record["word"])
        if fix is None:
            continue
        seen.add(record["word"])
        if record["meaning"] == fix.meaning:
            continue
        changes.append(
            {
                "position": record["position"],
                "word": record["word"],
                "before": record["meaning"],
                "after": fix.meaning,
                "reason": fix.reason,
                "category": fix.category,
                "sourceBasis": fix.source_basis,
                "posCorrection": fix.pos_correction,
            }
        )
        record["meaning"] = fix.meaning
    missing = sorted(set(FIXES) - seen)
    if missing:
        raise RuntimeError(f"fix words not found: {missing}")
    revised["book"]["id"] = "kaoyan_final"
    revised["book"]["version"] = 4
    return revised, changes


def build_reviews(revised: dict[str, Any]) -> list[dict[str, Any]]:
    reviews: list[dict[str, Any]] = []
    for record in revised["words"]:
        word = record["word"]
        meaning = record["meaning"]
        if HARD_POLLUTION_RE.search(meaning):
            reviews.append(
                {
                    "position": record["position"],
                    "word": word,
                    "currentMeaning": meaning,
                    "reason": "仍含高风险真题/教材正文标记",
                    "suggestedMeaning": "",
                    "confidence": "medium",
                }
            )
        conflict = conservative_pos_conflict(word, meaning)
        if conflict:
            reviews.append(
                {
                    "position": record["position"],
                    "word": word,
                    "currentMeaning": meaning,
                    "reason": conflict,
                    "suggestedMeaning": "",
                    "confidence": "medium",
                }
            )
    for group in exact_duplicate_groups(revised["words"]):
        if group["classification"] == "legitimate":
            continue
        for word, position in zip(group["words"], group["positions"]):
            reviews.append(
                {
                    "position": position,
                    "word": word,
                    "currentMeaning": group["meaning"],
                    "reason": f"与 {', '.join(w for w in group['words'] if w != word)} 的 meaning 完全相同且未归类为正常近义词",
                    "suggestedMeaning": "",
                    "confidence": "medium",
                }
            )
    unique: dict[tuple[int, str], dict[str, Any]] = {}
    for review in reviews:
        unique[(review["position"], review["reason"])] = review
    return sorted(unique.values(), key=lambda item: (item["position"], item["reason"]))


def validate_integrity(original: dict[str, Any], revised: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    old_words = original["words"]
    new_words = revised["words"]
    if len(old_words) != 5847 or len(new_words) != 5847:
        errors.append("单词总数不是 5847")
        return errors
    positions = [record["position"] for record in new_words]
    if positions != list(range(1, 5848)):
        errors.append("position 不连续或顺序变化")
    if len(set(positions)) != 5847:
        errors.append("position 不唯一")
    if len({record["id"] for record in new_words}) != 5847:
        errors.append("id 不唯一")
    for before, after in zip(old_words, new_words):
        if not isinstance(after.get("word"), str) or not after["word"].strip():
            errors.append(f"position {after.get('position')} word 为空")
        if not isinstance(after.get("meaning"), str) or not after["meaning"].strip():
            errors.append(f"position {after.get('position')} meaning 为空")
        for field in ("id", "position", "word", "phonetic", "example"):
            if before.get(field) != after.get(field):
                errors.append(f"position {before.get('position')} 的 {field} 被修改")
    for field in ("expectedWordCount", "source", "licenseNote"):
        if original["book"].get(field) != revised["book"].get(field):
            errors.append(f"book.{field} 被修改")
    if revised["book"].get("id") != "kaoyan_final" or revised["book"].get("version") != 4:
        errors.append("book.id/version 未更新为 kaoyan_final/4")
    return errors


def random_unchanged_sample(
    original: dict[str, Any], revised: dict[str, Any], changed_words: set[str]
) -> list[dict[str, Any]]:
    old_by_word = {record["word"]: record for record in original["words"]}
    candidates = [record for record in revised["words"] if record["word"] not in changed_words]
    selected = random.Random(2027).sample(candidates, 100)
    result: list[dict[str, Any]] = []
    for record in sorted(selected, key=lambda item: item["position"]):
        before = old_by_word[record["word"]]
        checks: list[str] = []
        if before != record:
            checks.append("未修改词的字段发生变化")
        if HARD_POLLUTION_RE.search(record["meaning"]):
            checks.append("含高风险教材正文标记")
        conflict = conservative_pos_conflict(record["word"], record["meaning"])
        if conflict:
            checks.append(conflict)
        result.append(
            {
                "position": record["position"],
                "word": record["word"],
                "meaning": record["meaning"],
                "result": "pass" if not checks else "review",
                "notes": "；".join(checks),
            }
        )
    return result


def escape_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def render_report(
    total: int,
    changes: list[dict[str, Any]],
    reviews: list[dict[str, Any]],
    original_duplicate_groups: list[dict[str, Any]],
    final_duplicate_groups: list[dict[str, Any]],
    sample: list[dict[str, Any]],
    pdf_path: Path,
) -> str:
    confirmed_exam_pollution = sum(c["category"] == "textbook_pollution" for c in changes)
    neighbor_shifts = sum(c["category"] == "neighbor_shift" for c in changes)
    pos_corrections = sum(bool(c["posCorrection"]) for c in changes)
    sample_failures = sum(item["result"] != "pass" for item in sample)
    lines = [
        "# 考研词库最终定点清理报告",
        "",
        f"总词数：{total}",
        f"本轮修改条数：{len(changes)}",
        f"仍需人工复核条数：{len(reviews)}",
        f"检测到的真题正文污染条数：{confirmed_exam_pollution}",
        f"检测到的明显串词条数：{neighbor_shifts}",
        f"词性修正条数：{pos_corrections}",
        f"修改前完全相同 meaning 分组：{len(original_duplicate_groups)}",
        f"修改后完全相同 meaning 分组：{len(final_duplicate_groups)}",
        f"随机抽查未修改词：{len(sample)}",
        f"随机抽查需复核：{sample_failures}",
        "",
        "## 原始来源与原则",
        "",
        f"- 原始 PDF：`{pdf_path}`",
        "- 仅修改原书回查或词义关系明确的高置信错误；长但正确的辨析内容保持原样。",
        "- `skilled/skillful` 等正常近义重复组保持不变。",
        "",
        "## 修改前后 diff",
        "",
        "| position | word | 修改前 | 修改后 | 修改原因 |",
        "|---:|---|---|---|---|",
    ]
    for change in changes:
        lines.append(
            f"| {change['position']} | {change['word']} | {escape_cell(change['before'])} | "
            f"{escape_cell(change['after'])} | {escape_cell(change['reason'])} |"
        )
    lines.extend(
        [
            "",
            "## 随机抽查 100 个未修改词",
            "",
            "随机种子固定为 `2027`，抽样对象仅为本轮未修改词。",
            "",
            "| position | word | meaning | 结果 |",
            "|---:|---|---|---|",
        ]
    )
    for item in sample:
        result = "通过" if item["result"] == "pass" else f"复核：{item['notes']}"
        lines.append(
            f"| {item['position']} | {item['word']} | {escape_cell(item['meaning'])} | {escape_cell(result)} |"
        )
    lines.extend(
        [
            "",
            "## 完整性校验",
            "",
            "- JSON 可正常解析。",
            "- 单词总数为 5847，position 为 1-5847 且唯一，id 唯一。",
            "- word 与 meaning 均非空。",
            "- 除高置信条目的 meaning 及顶层 id/version 外，word、phonetic、example、position、词条 id 均未修改。",
            "- `book.id` 已更新为 `kaoyan_final`，`book.version` 已更新为 `4`。",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    original = read_json(args.input)
    if not args.pdf.exists():
        raise FileNotFoundError(args.pdf)
    original_duplicate_groups = exact_duplicate_groups(original["words"])
    revised, changes = apply_fixes(original)
    final_duplicate_groups = exact_duplicate_groups(revised["words"])
    reviews = build_reviews(revised)
    integrity_errors = validate_integrity(original, revised)
    if integrity_errors:
        raise RuntimeError("integrity validation failed: " + "; ".join(integrity_errors[:20]))
    changed_words = {change["word"] for change in changes}
    sample = random_unchanged_sample(original, revised, changed_words)
    sample_failures = [item for item in sample if item["result"] != "pass"]
    if sample_failures:
        for item in sample_failures:
            reviews.append(
                {
                    "position": item["position"],
                    "word": item["word"],
                    "currentMeaning": item["meaning"],
                    "reason": "随机抽查命中：" + item["notes"],
                    "suggestedMeaning": "",
                    "confidence": "medium",
                }
            )
        reviews.sort(key=lambda item: (item["position"], item["reason"]))
    write_json(args.out_dir / "kaoyan_final.json", revised)
    write_json(args.out_dir / "meaning_review_needed_final.json", reviews)
    (args.out_dir / "meaning_fix_report_final.md").write_text(
        render_report(
            len(original["words"]),
            changes,
            reviews,
            original_duplicate_groups,
            final_duplicate_groups,
            sample,
            args.pdf,
        ),
        encoding="utf-8",
        newline="\n",
    )
    print(
        json.dumps(
            {
                "totalWords": len(original["words"]),
                "modified": len(changes),
                "manualReview": len(reviews),
                "examPollution": sum(c["category"] == "textbook_pollution" for c in changes),
                "neighborShift": sum(c["category"] == "neighbor_shift" for c in changes),
                "posCorrections": sum(bool(c["posCorrection"]) for c in changes),
                "randomSample": len(sample),
                "randomSampleFailures": len(sample_failures),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
