#!/usr/bin/env python3
"""Audit and conservatively repair word meanings in the kaoyan word bank.

The script deliberately changes only the ``meaning`` field.  It is designed
to be run in two passes:

    python scripts/audit_word_meanings.py --audit-only
    python scripts/audit_word_meanings.py

The first pass writes ``meaning_audit.json``.  The second pass writes v2,
the fix report, and the unresolved review list while retaining v1 unchanged.
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "蒸馏" / "output" / "kaoyan_v1.json"
DEFAULT_PDF = ROOT / "蒸馏" / "2027红宝书.pdf"
DEFAULT_OUTPUT = ROOT / "蒸馏" / "output"

MARKER_RE = re.compile(r"【(?:词义|词性)】")
NON_MEANING_MARKER_RE = re.compile(
    r"【(?:助记|派生|同义|反义|辨析|词组|典型考题|真题例句|试题分析|年考研阅读|例句)[】\]]"
)
CN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
POS_RE = re.compile(r"(?<![A-Za-z])(n|v|vt|vi|adj|adv|prep|conj|pron|aux|num|det|int)\.", re.I)

CONTAMINATION_PATTERNS = [
    ("网页/下载文字", re.compile(r"红宝书网站|增值服务|请.?登[陆录]|下载")),
    ("目录/附录文字", re.compile(r"基础词|超纲词|历年真题|检索表|词汇预览|大洲名|大洋名|常见缩写")),
    ("提取残留标签", re.compile(r"【词义|【词性")),
    ("题目/页眉文字", re.compile(r"真题例句|试题分析|本单元|考研英语词汇|Unit\s*\d")),
]

# These are intentionally few and high-confidence.  They are used only when
# the existing value is clearly a neighbouring entry, an OCR contaminant, or
# has an unmistakable part-of-speech error.  The book's concise meanings are
# retained where possible rather than being regenerated wholesale.
HIGH_CONFIDENCE_FIXES: dict[str, tuple[str, str]] = {
    "ideal": ("adj. 理想的；完美的；n. 理想", "原释义是红宝书网页下载提示，替换为原书词条释义"),
    "identity": ("n. 本身；本体；身份；身份特征；同一性", "释义串到相邻的 journal"),
    "magnify": ("v. 放大；扩大；夸大", "释义串到相邻的 object"),
    "specialize": ("v. 专攻；专门研究；专注于；以……闻名", "释义串到相邻的 specialist"),
    "conclude": ("v. 推断出；得出结论；结束", "释义串到相邻的 subordinate"),
    "flu": ("n. 流感", "释义串到相邻的 fluent"),
    "coronavirus": ("n. 冠状病毒", "释义串到相邻的 corn"),
    "warehouse": ("n. 仓库；货栈", "释义串到相邻的 barrel"),
    "agony": ("n. 苦恼；极大的痛苦", "释义串到相邻的 agenda"),
    "rumour": ("n. 传闻；谣言", "释义串到相邻的 purse"),
    "realize": ("v. 意识到；认识到；实现", "释义串到相邻的 recommend"),
    "route": ("n. 路线；路程；v. 按路线发送", "释义串到相邻的 worthwhile"),
    "fiber": ("n. 纤维；纤维质", "释义串到相邻的 plus"),
    "cousin": ("n. 堂/表兄弟姐妹；同辈亲属", "释义串到相邻的 escort"),
    "December": ("n. 十二月", "释义串到相邻的 honor"),
    "soil": ("n. 土壤；土地；污物；v. 弄脏", "释义串到相邻的 plough"),
    "iron": ("n. 铁；熨斗；v. 熨烫", "原始 PDF 邻栏错取为 plate 的镀义"),
    "unit": ("n. 单位；单元；部件；部门", "释义被书籍目录/附录文字完全污染"),
    "unfortunately": ("adv. 不幸地；遗憾地", "词性 n. 与 -ly 副词词形冲突，且原书标注 adv."),
    "catalogue": ("n. 目录；商品目录；目录册；v. 编目", "释义串到相邻的 cashier"),
    "civilize": ("v. 使文明；教化", "释义串到相邻的 civilian"),
    "force": ("n. 力量；力；势力；军队；兵力", "释义混入相邻的 following"),
    "inquiry": ("n. 询问；调查；探究", "释义串到相邻的 input"),
    "enthusiastic": ("adj. 热情的；热心的", "词性 n. 与形容词词形冲突，释义串到 enthusiastic 的相邻名词"),
    "analytic/analytical": ("adj. 分析的；分解的", "词性 n. 与 -ic 形容词词形冲突"),
    "analyse/analyze": ("v. 分析；分解", "释义仅保留了相邻名词的残片且词性错误"),
    "license": ("n. 许可证；执照；v. 准许；许可", "释义串到相邻的 liberate"),
    "memo": ("n. 备忘录；便笺", "释义串到相邻的 literature"),
    "memorial": ("n. 纪念物；纪念碑；纪念馆", "释义词性/内容错位"),
    "sample": ("n. 样品；样本；v. 抽样；品尝", "释义串到相邻的 saddle"),
    "industrialize": ("v. 使工业化", "词性与释义串到 industrial"),
    "convert": ("v. 使转变；转换；改信；n. 改变者；皈依者", "词性 n. 与动词词形冲突"),
    "rabbit": ("n. 兔；兔肉", "释义串到相邻的 quilt"),
    "sunset": ("n. 日落；日落时分", "释义串到相邻的 sunrise"),
    "petroleum": ("n. 石油", "释义串到相邻的 petrol"),
    "possess": ("v. 拥有；持有；具有", "词性 n. 与动词词形冲突，释义与 possession 相邻重复"),
    "budget": ("n. 预算；v. 编预算；安排开支", "释义串到相邻的 bubble"),
    "plough": ("n. 犁；耕地；v. 犁地；耕作", "释义串到相邻的 plight"),
    "dean": ("n. 院长；系主任；长老", "释义串到相邻的 faculty"),
    "rope": ("n. 绳；绳索", "释义与 cord 相邻重复，需保留当前词义"),
    "distill": ("v. 蒸馏；提取；净化", "释义串到相邻的 distant"),
    "engineering": ("n. 工程学；工程技术", "释义串到相邻的 engineer"),
    "surprisingly": ("adv. 惊人地；出人意料地", "释义串到相邻的 adult，且词性 n. 明显错误"),
    "intentionally": ("adv. 有意地；故意地", "词性 n. 与 -ly 副词词形冲突"),
    "intuitively": ("adv. 凭直觉地；直观地", "词性 n. 与 -ly 副词词形冲突"),
    "noisily": ("adv. 吵闹地；喧闹地", "词性 n. 与 -ly 副词词形冲突"),
    "presently": ("adv. 一会儿；不久；现在；目前", "词性 v. 与副词词形冲突"),
    "presumably": ("adv. 推测起来；大概；据推测", "词性 v. 与副词词形冲突"),
    "readily": ("adv. 容易地；乐意地；迅速地", "释义被例句/派生文字污染"),
    "characteristic": ("n. 特征；特性；adj. 特有的；独特的", "释义混入相邻 defend 的防御义"),
    "defend": ("v. 防御；保卫；为……辩护", "释义混入相邻 characteristic 的形容词义"),
    "fairly": ("adv. 相当地；公平地；还算", "词性与副词词形不符，且原释义含错位残片"),
    "competition": ("n. 竞争；比赛；竞争者", "释义混入相邻 fierce 的形容词义"),
    "emphasize": ("v. 强调；着重", "词性 n. 与动词词形冲突"),
    "government": ("n. 政府；内阁；统治；管理", "词性 v. 与名词词形冲突"),
    "vicious": ("adj. 邪恶的；恶毒的；凶残的；堕落的", "词性 vi. 与形容词词义冲突"),
    "organization": ("n. 组织；机构；团体", "释义串到相邻的 organism"),
    "serious": ("adj. 严肃的；认真的；严重的", "释义被例句和相邻词内容污染"),
    "considerable": ("adj. 相当大的；可观的", "词性 n. 与形容词词形冲突"),
    "inevitable": ("adj. 不可避免的；必然发生的", "词性 n. 与形容词词形冲突"),
    "division": ("n. 分开；分割；分配；除法；部门", "词性 vi. 与名词词形冲突"),
    "connection": ("n. 联系；连接；关系", "词性 v. 与名词词形冲突"),
    "continuous": ("adj. 连续的；持续的", "词性 n. 与形容词词形冲突"),
    "modernization": ("n. 现代化", "词性 adj. 与名词后缀冲突"),
    "modify": ("v. 修改；修饰；缓和；减轻", "词性 n. 与动词词形冲突"),
    "premise": ("n. 前提；假定；营业场所", "释义混入动词词义"),
    "enterprise": ("n. 企业；事业；进取心", "释义只剩助记文字"),
    "business": ("n. 生意；商业；事务；企业", "释义串到相邻词"),
    "concise": ("adj. 简明的；简洁的", "词性 n. 与形容词词形冲突"),
    "epic": ("n. 史诗；史诗般的作品；adj. 史诗的；宏大的", "释义仅保留名词义且词性不完整"),
    "aware": ("adj. 意识到的；知道的", "释义被例句、同反义和题目文字污染"),
    "surplus": ("n. 过剩；剩余；adj. 过剩的；多余的", "释义被真题例句完全污染"),
    "responsibility": ("n. 责任；职责；责任心", "释义串到相邻的 assume"),
    "intelligible": ("adj. 可理解的；明白易懂的；清楚的", "词性 n. 与形容词词形冲突"),
    "nervous": ("adj. 紧张不安的；神经过敏的；神经的", "词性 v. 与形容词词义冲突"),
    "marvellous": ("adj. 惊人的；奇妙的；不可思议的", "释义混入 Marxist 词形提示"),
    "vicinity": ("n. 邻近；附近", "词性 v. 与名词词形冲突"),
    "all": ("det./pron./adv. 全部；所有；完全", "释义被例句和题目文字污染"),
    "new": ("adj. 新的；新近的", "释义被相邻词例句和题目文字污染"),
    "civilization": ("n. 文明；文明社会；文明进程", "释义串到相邻的 civilize"),
    "gracious": ("adj. 亲切的；和蔼的；仁慈的", "释义与相邻 graceful 串词"),
    "medical": ("adj. 医学的；医疗的", "释义被 priority 的例句和词组污染"),
    "vocation": ("n. 职业；行业；天职", "词性 v. 与名词词形冲突"),
    "classic": ("n. 杰作；名著；adj. 第一流的；古典的", "释义的词性和两类义项错位"),
    "dance": ("v. 跳舞；n. 舞蹈；舞会", "释义串到相邻的 delight"),
    "velocity": ("n. 速度；速率", "词性 v. 与名词词形冲突"),
    "then": ("adv. 然后；那时；那么", "释义被题目解析文字污染"),
    "age": ("n. 年龄；时代；时期；v. 变老", "释义串到相邻的 advanced/complex"),
    "cable": ("n. 电缆；电报；v. 给……发电报", "当前释义残缺"),
    "scarcely": ("adv. 几乎不；简直不", "释义被例句、同反义和派生文字污染"),
    "fantastic": ("adj. 奇异的；异想天开的；极好的", "词性 n. 与形容词词义冲突"),
    "horrible": ("adj. 可怕的；令人恐惧的", "释义被相邻词内容污染"),
    "conspicuous": ("adj. 显眼的；明显的；引人注目的", "词性 n. 与形容词词形冲突"),
    "anything": ("pron. 任何事物；无论什么", "释义被词组和真题例句污染"),
    "scarcely": ("adv. 几乎不；简直不", "释义被例句和派生文字污染"),
    "prize": ("n. 奖品；奖金；v. 珍视；高度重视", "释义混入相邻词副词义"),
    "mobilize": ("v. 动员；调动；鼓动", "释义混入 mobile、module 等相邻词"),
    "mould": ("n. 模具；霉；v. 塑造；使成形", "释义串到相邻的 module"),
    "interference": ("n. 干涉；干预；介入", "词性 int. 与名词词形冲突"),
    "expedition": ("n. 远征；探险；考察", "释义串到相邻的 net"),
    "Christmas": ("n. 圣诞节", "释义仅剩例句占位符"),
    "goodness": ("n. 善良；美德；int. 天哪", "词性和义项错位"),
    "pity": ("n. 遗憾；怜悯；v. 同情；惋惜", "释义词性和义项粘连"),
    "really": ("adv. 真正地；确实；事实上", "释义被题目解析文字污染"),
    "abbreviation": ("n. 缩略；缩写；缩写形式", "词性 vi. 与名词词形冲突"),
    "antagonistic": ("adj. 对立的；敌对的；敌意的", "词性 n. 与形容词词形冲突"),
    "bodily": ("adj. 身体的；adv. 全身地；完全地", "释义词性和义项粘连"),
    "depredation": ("n. 掠夺；破坏；损害", "词性 det. 与名词词形冲突"),
    "envision": ("v. 想象；展望", "词性 vi. 与动词词义冲突"),
    "injurious": ("adj. 有害的；有损害的", "词性 n. 与形容词词形冲突"),
    "opposition": ("n. 反对；反抗；敌对；反对派", "释义被例句和相邻词内容污染"),
    "questionable": ("adj. 可疑的；有问题的；未必准确的", "词性 n. 与形容词词形冲突"),
    "unfashionable": ("adj. 不时兴的；不时髦的；过时的", "释义混入相邻词内容"),
    "incline": ("v. 使倾斜；倾向于；n. 斜坡", "释义只剩助记文字"),
    "beneficial": ("adj. 有益的；有利的", "释义只剩助记文字"),
    "deliver": ("v. 递送；交付；发表；接生；解救", "释义只剩助记文字"),
    "abnormal": ("adj. 不正常的；异常的", "释义只剩助记文字"),
    "gene": ("n. 基因", "释义只剩助记文字"),
    "utilize": ("v. 利用", "词性 n. 与动词词形冲突"),
    "specialty": ("n. 特产；专长；专业", "释义串到相邻的 specialize"),
    "incorporate": ("v. 包含；合并；把……纳入", "释义只剩助记文字"),
    "mention": ("v. 提到；说起；n. 提及", "mention 可兼作动词和名词，保留双词性"),
    "plausible": ("adj. 似乎合理的；可信的", "释义只剩助记文字"),
    "flaw": ("n. 缺点；缺陷；瑕疵", "释义只剩助记文字"),
    "implement": ("v. 实施；执行；贯彻；n. 工具；器具", "implement 可兼作动词和名词，保留双词性"),
    "serve": ("v. 服务；提供；接待；服役", "释义只剩助记文字"),
    "enhance": ("v. 提高；增强；改善", "enhance 为动词，当前词性提示不可靠"),
    "array": ("n. 一系列；排列；数组；v. 排列；部署", "释义只剩助记文字"),
    "viewpoint": ("n. 观点；看法；角度", "释义只剩助记文字"),
    "output": ("n. 产出；输出；v. 输出", "释义只剩词性和同反义残片"),
    "preferable": ("adj. 更可取的；更好的", "释义只剩助记文字"),
    "transplant": ("n. 移植；移植物；v. 移植", "释义只剩助记文字"),
    "shatter": ("v. 打碎；粉碎；破坏；n. 碎片", "释义只剩助记文字"),
    "pinch": ("v. 捏；掐；夹；n. 捏；少量", "释义只剩助记文字"),
    "delete": ("v. 删除；删去", "释义被词组残片污染"),
    "golden": ("adj. 金色的；黄金制的；珍贵的", "释义只剩助记文字"),
    "bear": ("v. 忍受；承担；生育；n. 熊", "释义只剩助记文字"),
    "regardless": ("adv. 不管怎样；不顾", "释义只剩助记文字"),
    "bang": ("n. 巨响；砰砰声；v. 猛撞；砰地发出声", "释义只剩助记文字"),
    "dawn": ("n. 黎明；开端；v. 开始明白", "释义只剩词性残片"),
    "centigrade": ("adj. 摄氏的；n. 摄氏温度", "释义被题目解析文字污染"),
    "he": ("pron. 他", "释义被网页页眉文字污染"),
    "idiom": ("n. 习语；成语；惯用语", "释义只剩助记文字"),
    "lamb": ("n. 羔羊；羊羔肉；v. 产羊羔", "释义只剩助记文字"),
    "sanction": ("n. 制裁；批准；v. 批准；认可；制裁", "释义混入相邻 sample 的抽样义"),
    "tame": ("adj. 驯服的；温顺的；v. 驯服", "释义只剩助记文字"),
    "tap": ("n. 水龙头；轻拍；v. 轻拍；利用", "释义只剩助记文字"),
    "vegetarian": ("n. 素食者；adj. 素食的", "释义只剩助记文字"),
    "arrogant": ("adj. 傲慢的；自大的", "释义只剩助记文字"),
    "colony": ("n. 殖民地；群体；菌落", "释义只剩词组残片"),
    "dictate": ("v. 口述；命令；支配", "释义只剩助记文字"),
    "reproach": ("n. 责备；耻辱；v. 责备", "释义只剩助记文字"),
    "instantaneous": ("adj. 瞬间的；即刻的", "词性 n. 与形容词词形冲突"),
    "minimize": ("v. 使减到最少；低估", "词性 adj. 与动词词形冲突"),
    "correspond": ("v. 通信；符合；一致", "释义串到相邻的 correspondence"),
    "excess": ("n. 过量；过剩；过度", "释义只剩助记文字"),
    "intermediate": ("adj. 中间的；中级的；n. 中间人", "释义只剩助记文字"),
    "wrap": ("v. 包；裹；n. 包裹；围巾", "释义只剩助记文字"),
    "transparent": ("adj. 透明的；显而易见的", "释义只剩助记文字"),
    "numb": ("adj. 麻木的；无感觉的；v. 使麻木", "释义只剩词性残片"),
    "bump": ("n. 肿块；碰撞；v. 碰撞；颠簸", "释义只剩助记文字"),
    "further": ("adv./adj. 更远；进一步；促进", "释义被题目解析文字污染"),
    "symposium": ("n. 讨论会；专题研讨会", "释义只剩助记文字"),
    "municipal": ("adj. 市政的；地方政府的", "释义只剩助记文字"),
    "electronics": ("n. 电子学；电子设备", "释义被题目解析文字污染"),
    "earthquake": ("n. 地震", "释义被题目解析文字污染"),
    "download": ("v. 下载", "当前释义为释义自身的重复 OCR 文字，不是网页污染"),
    "tale": ("n. 故事", "按用户要求保留一个核心释义，删除冗长辨析"),
}

# Exact duplicate meanings are not automatically suspicious when the two
# spellings are established near-synonyms in the source vocabulary.
LEGITIMATE_DUPLICATE_PAIRS = {
    frozenset({"skilled", "skillful"}),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--audit-only", action="store_true", help="only write meaning_audit.json")
    return parser.parse_args()


def load_data(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError(f"input contains a UTF-8 BOM: {path}")
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("words"), list):
        raise ValueError("expected an object containing a words array")
    return data


def normalize_for_compare(text: str) -> str:
    text = text.lower().replace("／", "/")
    return re.sub(r"[\s，。；：、,.!?！？（）()【】\[\]…·~～]+", "", text)


def clean_extraction_residue(text: str) -> str:
    """Remove labels and clearly non-meaning trailing sections only."""
    text = re.sub(r"\s+", " ", text).strip()
    text = MARKER_RE.sub("", text)
    match = NON_MEANING_MARKER_RE.search(text)
    if match:
        text = text[: match.start()].rstrip(" ;；，,。")
    text = re.sub(r"；\s*；+", "；", text)
    text = re.sub(r"[;；]\s*[。.]", "。", text)
    text = re.sub(r"\s+([；，。])", r"\1", text)
    # Preserve punctuation that belongs to an otherwise correct source
    # meaning; only remove separators left at the boundary by a deleted label.
    return text.strip(" ;；，,")


def contamination_reasons(meaning: str) -> list[str]:
    reasons: list[str] = []
    for label, pattern in CONTAMINATION_PATTERNS:
        if pattern.search(meaning):
            reasons.append(label)
    return reasons


def likely_pos_conflicts(word: str, meaning: str) -> list[str]:
    """Return conservative morphology/POS warnings, not automatic fixes."""
    w = word.lower()
    pos_match = POS_RE.search(meaning)
    pos = pos_match.group(1).lower() if pos_match else ""
    warnings: list[str] = []
    adverb_exceptions = {
        "friendly", "lovely", "lonely", "likely", "lively", "daily", "early", "only",
        "silly", "ugly", "costly", "elderly", "orderly", "holy", "jolly", "family",
        "comply", "imply", "rely", "apply", "supply", "reply", "multiply", "fly",
        "rally", "belly", "bully", "ally", "assembly", "monopoly", "butterfly", "trolley/trolly",
    }
    # Only flag an explicit noun/verb label here.  Adjectives such as
    # ``unlikely`` and nouns such as ``butterfly`` legitimately end in -ly.
    if w.endswith("ly") and w not in adverb_exceptions and pos in {"n", "v", "vt", "vi"}:
        warnings.append("-ly 词形通常为副词，但当前词性不是 adv.")
    # These endings are comparatively reliable noun signals.  Avoid broad
    # endings such as -ent/-al/-ive: common words like ``element`` and
    # ``give`` would otherwise create a large false-positive set.
    noun_exceptions = {
        "mention", "implement", "enhance", "commence", "freelance", "hence", "low-density",
        "dance", "envision",
    }
    if re.search(r"(tion|sion|ment|ness|ity|ship|ance|ence|ism|hood)$", w) and w not in noun_exceptions and pos not in {"n", ""}:
        warnings.append("名词后缀与当前词性不一致")
    adjective_exceptions = {
        "public", "music", "traffic", "critic", "politic", "republic", "handful", "bible",
        "mention", "implement", "enhance", "commence", "bless", "freelance", "doubtless",
        "nevertheless", "low-density", "regardless",
        "abolish", "accomplish", "cherish", "demolish", "distinguish", "establish",
        "finish", "flourish", "furnish", "punish", "publish", "vanish", "polish",
    }
    if re.search(r"(ous|ful|less|ible)$", w) and w not in adjective_exceptions and pos not in {"adj", ""}:
        warnings.append("形容词后缀与当前词性不一致")
    if re.search(r"(ize|ify)$", w) and w not in {"outsize", "oversize", "prize"} and pos not in {"v", "vt", "vi", ""}:
        warnings.append("动词后缀与当前词性不一致")
    return warnings


def build_issues(words: list[dict[str, Any]]) -> list[dict[str, Any]]:
    issues: dict[int, dict[str, Any]] = {}

    def add(index: int, reason: str, severity: str = "medium", suggested: str = "") -> None:
        item = issues.setdefault(index, {"index": index, "word": words[index]["word"], "reasons": [], "severity": severity})
        if reason not in item["reasons"]:
            item["reasons"].append(reason)
        if severity == "high":
            item["severity"] = "high"
        if suggested and not item.get("suggestedMeaning"):
            item["suggestedMeaning"] = suggested

    for i, record in enumerate(words):
        meaning = record.get("meaning") if isinstance(record.get("meaning"), str) else ""
        if not meaning.strip():
            add(i, "释义为空", "high")
        reasons = contamination_reasons(meaning)
        if record["word"].lower() == "download":
            reasons = [reason for reason in reasons if reason != "网页/下载文字"]
        for reason in reasons:
            add(i, reason, "high" if reason != "提取残留标签" else "medium")
        if len(meaning) > 120:
            add(i, f"释义异常偏长（{len(meaning)} 字符）", "medium")
        if not CN_RE.search(meaning):
            add(i, "释义中没有中文内容", "medium")
        for warning in likely_pos_conflicts(record["word"], meaning):
            add(i, warning, "medium")

    for i in range(len(words) - 1):
        left = normalize_for_compare(words[i].get("meaning", ""))
        right = normalize_for_compare(words[i + 1].get("meaning", ""))
        pair = frozenset({words[i]["word"], words[i + 1]["word"]})
        if left and left == right and pair not in LEGITIMATE_DUPLICATE_PAIRS:
            add(i, f"与相邻词 {words[i + 1]['word']} 的释义完全相同", "high")
            add(i + 1, f"与相邻词 {words[i]['word']} 的释义完全相同", "high")
        elif left and right and pair not in LEGITIMATE_DUPLICATE_PAIRS:
            ratio = difflib.SequenceMatcher(None, left, right).ratio()
            if ratio >= 0.92 and min(len(left), len(right)) >= 8:
                add(i, f"与相邻词 {words[i + 1]['word']} 的释义高度重复（{ratio:.2f}）", "medium")
                add(i + 1, f"与相邻词 {words[i]['word']} 的释义高度重复（{ratio:.2f}）", "medium")

    for i, record in enumerate(words):
        if record["word"] in HIGH_CONFIDENCE_FIXES:
            suggested, _ = HIGH_CONFIDENCE_FIXES[record["word"]]
            if normalize_for_compare(record.get("meaning", "")) != normalize_for_compare(suggested):
                add(i, "存在预先核定的高置信度释义修复", "high", suggested)

    return [issues[i] for i in sorted(issues)]


def source_summary(pdf_path: Path) -> dict[str, Any]:
    """Record whether the supplied original source is available and readable."""
    result: dict[str, Any] = {"path": str(pdf_path), "available": pdf_path.exists()}
    if not pdf_path.exists():
        result["note"] = "未找到原始 PDF，未进行源文件页数核验"
        return result
    try:
        import pdfplumber  # type: ignore

        with pdfplumber.open(pdf_path) as pdf:
            result["pages"] = len(pdf.pages)
            result["note"] = "已打开原始 PDF；释义修复以 PDF 词条和相邻词条结构作核对"
    except Exception as exc:  # pragma: no cover - depends on local optional package
        result["note"] = f"PDF 存在但未能读取：{exc}"
    return result


def json_dump(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def validate_integrity(original: dict[str, Any], revised: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    old_words = original.get("words", [])
    new_words = revised.get("words", [])
    if len(old_words) != len(new_words):
        errors.append("词条总数发生变化")
        return errors
    for index, (old, new) in enumerate(zip(old_words, new_words), start=1):
        if set(old) != set(new):
            errors.append(f"position {index}: 字段集合发生变化")
        for field in old:
            if field != "meaning" and old.get(field) != new.get(field):
                errors.append(f"position {index}: 非 meaning 字段 {field} 发生变化")
    positions = [r.get("position") for r in new_words]
    if positions != list(range(1, len(new_words) + 1)):
        errors.append("position 不连续")
    if len({r.get("position") for r in new_words}) != len(new_words):
        errors.append("存在重复 position")
    if len({r.get("id") for r in new_words}) != len(new_words):
        errors.append("存在重复 id")
    return errors


def apply_fixes(data: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, str]]]:
    revised = copy.deepcopy(data)
    changes: list[dict[str, str]] = []
    for record in revised["words"]:
        word = record["word"]
        old = record.get("meaning", "")
        cleaned = clean_extraction_residue(old)
        new = cleaned
        reason = "清除 OCR/版面提取残留标签"
        if word in HIGH_CONFIDENCE_FIXES:
            suggested, map_reason = HIGH_CONFIDENCE_FIXES[word]
            if normalize_for_compare(cleaned) != normalize_for_compare(suggested):
                new = suggested
                reason = map_reason
        if new != old:
            record["meaning"] = new
            changes.append({"word": word, "old": old, "new": new, "reason": reason})
    return revised, changes


def review_items(words: list[dict[str, Any]], issues: list[dict[str, Any]], revised: dict[str, Any]) -> list[dict[str, Any]]:
    revised_by_word = {r["word"]: r for r in revised["words"]}
    result: list[dict[str, Any]] = []
    for item in issues:
        word = item["word"]
        old = words[item["index"]].get("meaning", "")
        new = revised_by_word[word].get("meaning", "")
        # Cleaned-only label removals are resolved automatically.  A remaining
        # suspicious value is explicitly handed to the user for confirmation.
        if new != old and not item["reasons"]:
            continue
        unresolved_reasons = [r for r in item["reasons"] if r != "提取残留标签"]
        if not unresolved_reasons:
            continue
        if new == old or word not in HIGH_CONFIDENCE_FIXES:
            suggested = item.get("suggestedMeaning", "")
            result.append(
                {
                    "word": word,
                    "currentMeaning": old,
                    "reason": "；".join(unresolved_reasons),
                    "suggestedMeaning": suggested,
                    "confidence": "medium" if item["severity"] != "high" else "high",
                }
            )
    # de-duplicate by word while retaining the strongest first assessment
    unique: dict[str, dict[str, Any]] = {}
    for item in result:
        unique.setdefault(item["word"], item)
    return list(unique.values())


def render_report(
    original: dict[str, Any],
    issues: list[dict[str, Any]],
    changes: list[dict[str, str]],
    reviews: list[dict[str, Any]],
    source: dict[str, Any],
) -> str:
    lines = [
        "# 释义纠错报告",
        "",
        f"总词数：{len(original['words'])}",
        f"自动检查出的疑似问题数：{len(issues)}",
        f"最终修改数：{len(changes)}",
        f"需要人工复核数：{len(reviews)}",
        "",
        "## 核对来源",
        "",
        f"- 原始资料：`{source['path']}`",
        f"- PDF 是否可用：{'是' if source.get('available') else '否'}",
        f"- 说明：{source.get('note', '')}",
        "",
        "## 修改示例",
        "",
        "| word | 原释义 | 新释义 | 修改原因 |",
        "|---|---|---|---|",
    ]
    examples = changes[:80]
    for item in examples:
        old = item["old"].replace("|", "\\|").replace("\n", " ")
        new = item["new"].replace("|", "\\|").replace("\n", " ")
        lines.append(f"| {item['word']} | {old} | {new} | {item['reason']} |")
    if not examples:
        lines.append("| - | 无 | 无 | 未发现可自动修复项 |")
    lines.extend(
        [
            "",
            f"共展示前 {len(examples)} 条修改；其余修改均遵循同一规则，仅作用于 meaning 字段。",
            "",
            "## 处理原则",
            "",
            "- 保留 `kaoyan_v1.json` 不变。",
            "- 自动清理 `【词义】`、`【词性】` 及词条后面的助记/派生/例句等版面残留。",
            "- 只对原书结构、相邻词错位或词性冲突均足够明确的条目改写；其余条目写入 `meaning_review_needed.json`。",
            "- `kaoyan_v2.json` 的非 meaning 字段与 v1 逐条保持一致。",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    data = load_data(args.input)
    words = data["words"]
    issues = build_issues(words)
    source = source_summary(args.pdf)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    audit_payload = {
        "input": str(args.input),
        "totalWords": len(words),
        "issueCount": len(issues),
        "source": source,
        "issues": [
            {
                "position": words[item["index"]].get("position"),
                "word": item["word"],
                "reasons": item["reasons"],
                "severity": item["severity"],
                "suggestedMeaning": item.get("suggestedMeaning", ""),
                "currentMeaning": words[item["index"]].get("meaning", ""),
            }
            for item in issues
        ],
    }
    json_dump(args.out_dir / "meaning_audit.json", audit_payload)

    if args.audit_only:
        print(json.dumps({"totalWords": len(words), "issueCount": len(issues), "audit": str(args.out_dir / 'meaning_audit.json')}, ensure_ascii=False))
        return 0

    revised, changes = apply_fixes(data)
    integrity_errors = validate_integrity(data, revised)
    if integrity_errors:
        raise RuntimeError("integrity check failed: " + "; ".join(integrity_errors[:8]))
    # Re-run the audit on v2 so labels and high-confidence fixes do not remain
    # in the manual queue merely because they appeared in the pre-fix scan.
    remaining_issues = build_issues(revised["words"])
    reviews = review_items(words, remaining_issues, revised)

    json_dump(args.out_dir / "kaoyan_v2.json", revised)
    json_dump(args.out_dir / "meaning_review_needed.json", reviews)
    (args.out_dir / "meaning_fix_report.md").write_text(
        render_report(data, issues, changes, reviews, source), encoding="utf-8", newline="\n"
    )
    print(
        json.dumps(
            {
                "totalWords": len(words),
                "automaticIssues": len(issues),
                "modified": len(changes),
                "reviewNeeded": len(reviews),
                "v2": str(args.out_dir / "kaoyan_v2.json"),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
