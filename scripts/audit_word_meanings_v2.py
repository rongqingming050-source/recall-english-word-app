#!/usr/bin/env python3
"""Second-pass semantic audit for kaoyan_v2.json.

This pass focuses on meanings that are fluent Chinese but belong to another
English headword.  It combines duplicate-meaning groups, +/-5 neighbour
comparison, textbook-pollution markers, basic-word length checks, negative
prefix pairs, and conservative part-of-speech checks.

Run the audit before applying fixes:

    python scripts/audit_word_meanings_v2.py --audit-only
    python scripts/audit_word_meanings_v2.py
"""

from __future__ import annotations

import argparse
import copy
import difflib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "蒸馏" / "output" / "kaoyan_v2.json"
DEFAULT_PDF = ROOT / "蒸馏" / "2027红宝书.pdf"
DEFAULT_OUTPUT = ROOT / "蒸馏" / "output"

POS_RE = re.compile(r"(?<![A-Za-z])(n|v|vt|vi|adj|adv|prep|conj|pron|aux|modal|num|det|art|int)\.", re.I)
CN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")

POLLUTION_RULES: list[tuple[re.Pattern[str], int, str]] = [
    (re.compile(r"【句意】|【解析】"), 5, "出现【句意】/【解析】真题解析标记"),
    (re.compile(r"历年真题|重点词|基础词|超纲词|附录|检索表"), 3, "出现教材目录或分区文字"),
    (re.compile(r"请.?登[陆录]|红宝书网站|增值服务|网站下载"), 3, "出现网页或下载提示"),
    (re.compile(r"【试题分析】|答案|本题|该句"), 2, "出现试题答案或题目分析文字"),
    (re.compile(r"辨析|例如|例：|同根词汇|词根"), 2, "出现辨析/例句/词根正文残留"),
    (re.compile(r"【助记】|【真题例句】|【典型考题】|【派生】|【词组】"), 2, "出现非释义栏目残留"),
]
RESIDUE_RE = re.compile(r"～|【词义】|【词性】|【句意】|【解析】")

NEGATIVE_PREFIXES = ("un", "in", "im", "ir", "il", "dis", "non")
ISSUE_TYPES = (
    "duplicate_meaning", "neighbor_shift", "textbook_pollution", "pos_conflict",
    "antonym_conflict", "abnormal_length", "basic_word_abnormal", "manual_review",
)

# Short/common words receive additional scrutiny when their meanings look like
# a full example or a neighbouring dictionary article.
BASIC_COMMON_WORDS = {
    "a", "an", "the", "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
    "my", "your", "his", "its", "our", "their", "this", "that", "these", "those", "who", "what", "which",
    "where", "when", "why", "how", "all", "any", "some", "no", "none", "nothing", "something", "anything",
    "be", "am", "is", "are", "was", "were", "been", "do", "does", "did", "have", "has", "had", "can",
    "could", "may", "might", "must", "shall", "should", "will", "would", "and", "or", "but", "because",
    "if", "as", "than", "though", "although", "while", "for", "from", "to", "of", "in", "on", "at", "by",
    "with", "without", "about", "after", "before", "above", "below", "under", "over", "into", "out", "up",
    "down", "high", "low", "dark", "light", "main", "ordinary", "try", "hire", "female", "male",
}

# Duplicate meanings that are semantically plausible and should be reported in
# the duplicate-group inventory but should not be treated as corruption.
LEGITIMATE_DUPLICATE_GROUPS = {
    frozenset({"capable", "competent"}),
    frozenset({"fabricate", "create"}),
    frozenset({"gigantic", "huge"}),
    frozenset({"energetic", "vigorous"}),
    frozenset({"toss", "throw"}),
    frozenset({"fortunate", "lucky"}),
    frozenset({"compose", "constitute"}),
    frozenset({"petrol", "gasoline/gasolene"}),
    frozenset({"plentiful", "wealthy"}),
    frozenset({"skilled", "skillful"}),
    frozenset({"warehouse", "storehouse"}),
    frozenset({"pamphlet", "brochure"}),
    frozenset({"dove", "pigeon"}),
}

# In these suspicious duplicate pairs the listed word was checked against the
# source and is the correct side of the pair.  Keep the duplicate-group record,
# but do not send the known-good anchor to manual review.
CORRECT_DUPLICATE_ANCHORS = {"meditation", "valid", "brisk", "grasp"}

# These entries triggered mechanical length/residue rules, but their headword
# meaning was checked against the PDF and is semantically correct.  They remain
# visible in the full audit while being excluded from the unresolved review file.
SOURCE_VERIFIED_UNCHANGED = {
    "elementary", "dedicate", "basis", "mandate", "merely", "become", "corporation", "accurate",
    "prior", "diminish", "reputation", "low", "declare", "accident", "hazard", "lately", "damn",
    "naked", "conquest", "boundary", "probable", "breast",
}

# Confirmed against the supplied book pages or unambiguous textbook headwords.
# Only these entries are automatically overwritten; medium-confidence findings
# are left in meaning_review_needed_v2.json.
HIGH_CONFIDENCE_FIXES: dict[str, tuple[str, str, str]] = {
    "negotiate": ("v. 谈判；协商", "释义完全复制自 meditation", "原书词条/同义提示确认 negotiate 为谈判、协商"),
    "invalid": ("adj. 无效的；不合法的；站不住脚的", "否定前缀遗漏，释义复制自 valid", "原书 valid 词条明确列出反义词 invalid：无效的"),
    "I": ("pron. 我", "释义复制自 brisk", "基础代词，当前释义与词性均不可能对应"),
    "high": ("adj. 高的；高水平的；adv. 高；n. 高处；高水平", "释义复制自 grasp", "基础词，当前释义属于 grasp"),
    "can": ("modal v. 能；会；可以；n. 罐；罐头；v. 把……装罐", "释义串到 eliminate/exclude", "基础情态动词及名词/动词常用义"),
    "because": ("conj. 因为；由于", "整条被 access 的真题解析覆盖", "原书版面中 because 只出现在 access 例题正文，当前并非词条释义"),
    "female": ("adj. 女性的；雌性的；n. 女性；雌性动物", "释义串到 ratio", "当前整段解释 rate/ratio，不属于 female"),
    "dark": ("adj. 黑暗的；深色的；n. 黑暗", "释义串到 beam/glare/flare", "原书对应文本是 beam 的光柱、横梁及辨析"),
    "as": ("conj. 当……时；因为；正如；prep. 作为；adv. 同样地", "释义串到 magnify", "当前内容是 magnify 的例句与辨析"),
    "ordinary": ("adj. 普通的；平常的；平凡的", "释义串到 testify/verify/certify", "当前内容是证明类动词辨析"),
    "chemical": ("adj. 化学的；n. 化学品", "释义串到 forbid", "当前内容是 forbid 的例句与辨析"),
    "hire": ("v. 雇用；租用；n. 租用；雇用", "释义串到 venture/adventure", "当前内容是 venture/adventure 的冒险义辨析"),
    "statement": ("n. 陈述；声明；报表", "释义串到 deduction/inference", "当前内容是 deduction 等推论词辨析"),
    "genuine": ("adj. 真正的；真诚的；名副其实的", "释义串到 distinguish", "原书当前文本属于 distinguish 的区别、识别义"),
    "mechanical": ("adj. 机械的；机械般的；呆板的", "释义串到 conceive", "原书当前文本属于 conceive 的构思、怀胎义"),
    "try": ("v. 尝试；努力；试验；审判；n. 尝试", "释义串到 imaginable/imaginative", "当前内容是 imaginable/imaginative 的例句和辨析"),
    "main": ("adj. 主要的；最重要的；n. 总管道；干线", "释义串到 object", "当前内容是 object 的对象、目的、宾语义"),
    "nothing": ("pron. 没有什么；无事；无物", "释义串到 boast", "当前内容是 boast 的自夸、自豪义"),
    "certify": ("vt. 证明；证实；发证书（或执照）", "释义末尾混入栏目残留", "原书 certify 词条：证明、证实；发证书（或执照）"),
    "raise": ("vt. 举起；提高；增加；提出；发起；n. 提高；增加（工资）", "释义串到 scheme/design", "原书 raise 词条列出举起、提高、增加、提出、发起及加薪义"),
    "member": ("n. 成员；会员", "释义串到 accept/receive", "原书 member 词条：成员，会员"),
    "virus": ("n. 病毒；（精神、道德方面的）有害影响", "整条被真题解析覆盖", "原书 virus 词条：病毒；精神或道德方面的有害影响"),
    "although": ("conj. 虽然；尽管；即使", "释义仅剩真题例句", "原书 although 词条：虽然，尽管，即使"),
    "order": ("n. 命令；次序；顺序；订购；订货单；等级；v. 命令；订购", "释义串到 catalogue/list/roster", "原书 order 词条列出命令、次序、订购、等级等义"),
    "microscope": ("n. 显微镜", "释义混入 fiber/textile 内容", "原书 microscope 词条：显微镜"),
    "fluctuate": ("v. 波动；起伏；变动", "释义前半串到 alter/convert 辨析", "原书 fluctuate 词条用于价格、股票等上下波动"),
    "better": ("adj. 较好的；更好的；adv. 更好地；n. 较佳者；较优者", "释义串到 finish/accomplish", "原书 better 词条列出形容词、副词和名词义"),
    "diligent": ("adj. 勤奋的；勤勉的", "释义串到 idle", "原书当前文本是 idle 的闲荡、无所事事义，和 diligent 相反"),
    "count": ("v. 数；计算；算入；认为；n. 计数；计算；总数", "释义串到 female/feminine", "原书 count 词条列出数、计算、算入、认为及总数义"),
    "bound": ("v. 跳跃；弹回；adj. 一定的；受约束的；n. 界限", "释义串到 obligation/duty", "原书 bound 词条以跳跃、弹回义起始；当前长段落属于义务辨析"),
    "mist": ("n. 薄雾", "释义后半串到 rouse", "原书 mist 词条：薄雾"),
    "rude": ("adj. 粗鲁的；无礼的；猛烈的；粗糙的；简陋的", "释义串到 conscious/aware", "原书 rude 词条列出粗鲁、无礼、猛烈、粗糙、简陋等义"),
    "but": ("conj. 可是；但是；prep. 除……外；adv. 只；仅仅；不过", "释义被小费制度正文覆盖", "原书 but 词条列出连词、介词和副词常用义"),
    "about": ("prep. 关于；adv. 大约；在周围", "释义仅剩 consider 的例句", "原书当前文本是仔细考虑的例句，不是 about 的词条释义"),
    "after": ("prep./conj./adv. 在……之后；以后", "释义仅剩 model/copy 的例句", "原书当前文本是仿照唐代原件的例句，不是 after 的词条释义"),
    "be": ("v. 是；在；存在；成为", "释义串到 observe/comment", "原书当前文本是遵守及评论、评述义，不属于 be"),
    "could": ("modal v. can 的过去式；能够；可以；可能", "释义被法院判例正文覆盖", "原书当前文本是第四修正案判例句，不是 could 的词条释义"),
    "administration": ("n. 管理；行政；政府", "释义残缺且仅剩治理结构例句", "原书 administration 词条对应管理、行政及政府义"),
    "endeavour": ("n./v. 努力；尽力", "释义混入例句和辨析残留", "原书 endeavour 词条核心义为努力、尽力"),
    "toilet": ("n. 厕所；盥洗室；梳妆", "释义串到 comprise/constitute", "原书当前文本是套房组成及 comprise 辨析；toilet 仅是其中例词"),
    "nation": ("n. 民族；国家", "释义混入失效药物的相邻例句", "原书 nation 词条：民族，国家"),
    "lover": ("n. 爱人；情人；爱好者", "释义混入 married/couple 内容", "回查原书基础词表及当前相邻正文，后半不属于 lover"),
    "generous": ("adj. 丰富的；大量的；慷慨的；大方的", "释义仅剩例句", "原书 generous 词条列出丰富、大量、慷慨、大方等义"),
    "significant": ("adj. 有意义的；重要的；重大的；显著的", "释义仅剩真题例句", "原书 significant 词条列出有意义、重要、重大等义"),
    "command": ("n. 命令；指令；指挥；掌握；v. 命令；指挥", "释义仅剩真题例句", "原书 command 词条列出命令、指挥、掌握及动词义"),
    "training": ("n. 训练；培养；培训", "释义串到 pattern", "原书 training 词条：训练，培养"),
    "natural": ("adj. 自然的；天然的；天生的", "释义仅剩例句", "原书 natural 词条以自然的、天然的为主释义"),
    "turn": ("v. 转动；旋转；翻转；变成；n. 转动；转弯；轮流", "释义被技术系统正文覆盖", "原书 turn 词条列出转动、翻转、变成及名词义"),
    "survival": ("n. 幸存；生存；残留下来的人或物", "释义后半串到 grim", "原书 survival 词条列出幸存、生存及残留者/物"),
    "responsible": ("adj. 应负责的；有责任的；可靠的；责任重大的", "释义串到 maintenance", "原书 responsible 词条列出负责、可靠和责任重大等义"),
    "suitable": ("adj. 合适的；适宜的", "释义仅剩例句", "原书 suitable 词条：合适的，适宜的"),
    "court": ("n. 法院；法庭；院子；球场；v. 讨好；求爱", "释义串到 witness/evidence", "原书 court 词条列出法院、法庭、院子、球场、讨好和求爱等义"),
    "march": ("v. 行军；行进；迫使……到某处；n. 行军；三月", "释义串到 date", "原书 march 词条列出行军、行进及名词义"),
    "office": ("n. 办公室；办事处；职务；公职；部；局；处", "释义串到 site", "原书 office 词条列出办公室、办事处、职务和机构等义"),
    "behind": ("prep. 在……后面；落后于；adv. 在后面", "释义串到 defend/excuse", "原书 behind 词条列出在后面、落后于及副词义"),
    "pilot": ("n. 飞行员；驾驶员；领航员；v. 驾驶；带领", "释义串到 qualification", "原书 pilot 词条列出飞行员、驾驶、带领等义"),
    "endure": ("v. 忍受；忍耐；持久；持续", "释义仅剩耐高温例句", "原书 endure 词条：忍受；持久，持续"),
    "meet": ("v. 遇见；会见；迎接；满足；达到", "释义串到 appointment", "原书 meet 词条列出遇见、会见、迎接、满足和达到等义"),
    "class": ("n. 班级；年级；课；阶级；等级；类别", "释义残缺并混入相邻正文", "原书 class 词条列出班级、课、阶级、等级和类别等义"),
    "scrape": ("v. 刮；擦；勉强通过；n. 刮擦；困境", "释义串到 incentive", "原书 scrape 词条以刮、擦义起始；当前后半不属于 scrape"),
    "people": ("n. 人们；人民；民族", "释义被消费者反馈例句覆盖", "原书 people 词条列出人民、民众和民族义"),
    "race": ("n. 竞赛；赛跑；种族；v. 赛跑；竞速", "释义仅剩真题例句", "原书 race 词条列出竞赛、赛跑、种族及动词义"),
    "ease": ("v. 减轻；使舒适；使安心；n. 容易；舒适；自在", "释义串到 leisurely/concise", "原书 ease 词条列出减轻、使安心、容易和舒适等义"),
    "scandal": ("n. 民愤；公愤；丑行；丑闻；诽谤", "释义后半串到 influence", "原书 scandal 词条列出民愤、丑行、丑闻及诽谤等义"),
    "undermine": ("v. 在……下挖；暗中破坏；逐渐削弱", "释义仅剩真题例句", "原书 undermine 词条列出下挖、暗中破坏和逐渐削弱等义"),
    "tire": ("v. 使疲倦；使厌倦；n. 轮胎", "释义仅剩轮胎例句且词性错误", "原书 tire 词条列出使疲倦、使厌倦及轮胎义"),
    "tissue": ("n. 织物；薄纸；组织", "释义仅剩例句且词性错误", "原书 tissue 词条列出织物、薄纸及动植物组织义"),
    "around": ("adv. 各处；周围；大约；prep. 在……周围；在……附近", "释义串到 immune", "原书 around 词条列出各处、周围、大约及介词义"),
    "splendid": ("adj. 华丽的；精美的；极好的；壮丽的；辉煌的", "释义串到 performance", "原书 splendid 词条列出华丽、极好、壮丽和辉煌等义"),
    "enormous": ("adj. 巨大的；庞大的", "释义串到 overlook/tolerance", "原书 enormous 词条：巨大的，庞大的"),
    "dioxide": ("n. 二氧化物", "释义仅剩二氧化碳例句", "原书 dioxide 词条：二氧化物"),
    "diplomatic": ("adj. 外交的；圆滑的；有策略的", "释义串到 protocol", "原书 diplomatic 词条：外交的，圆滑的，策略的"),
    "still": ("adv. 还；仍旧；更；adj. 静止的；n. 寂静", "释义串到 conscious", "原书 still 词条列出还、仍旧、更等副词义；当前后半属于 conscious"),
    "correct": ("adj. 正确的；恰当的；v. 改正；纠正", "释义仅剩例句且词性错误", "原书 correct 词条列出正确、恰当及改正、纠正义"),
    "interview": ("v. 采访；面试；n. 接见；会见；面试", "释义串到 exclusive", "原书 interview 词条列出采访、面试、接见和会见等义"),
    "event": ("n. 事件；事情；活动；比赛项目", "释义仅剩例句", "原书 event 词条以事件、事情为主释义"),
    "ridiculous": ("adj. 可笑的；荒唐的；荒谬的", "释义串到 noticeable", "原书 ridiculous 词条：可笑的，荒唐的，荒谬的"),
    "sunshine": ("n. 日光；日照；欢乐", "释义串到 intention", "原书 sunshine 词条列出日光、日照；当前后半不属于 sunshine"),
    "ownership": ("n. 所有权；所有制", "释义串入下一词 ozone", "原书 ownership 词条：所有权，所有制；其后臭氧内容属于 ozone"),
    "cure": ("v. 治愈；医治；消除；改正；n. 治愈；疗法", "释义被环境问题例句覆盖", "原书 cure 词条列出治愈、医治、改正及疗法等义"),
    "also": ("adv. 也；而且；还", "释义被评价论点的真题正文覆盖", "回查原书当前版面，整段是阅读正文而非 also 释义"),
    "both": ("det./pron. 两者；双方；adj. 两者的", "释义混入 restriction/certificate", "回查原书基础词表及当前正文，后半释义属于相邻词"),
    "furniture": ("n. 家具", "释义仅剩例句", "回查原书基础词表，当前仅保留家具例句而无主释义"),
    "gate": ("n. 大门；门口；登机口", "释义串到 reaction/reply", "回查原书基础词表，当前内容属于反应、回答类词义"),
    "just": ("adv. 刚刚；正好；只是；adj. 公正的；合理的", "释义仅剩刚刚的例句", "回查原书基础词表，当前只保留一个例句而无词条释义"),
    "middle": ("n. 中部；中间；adj. 中部的；中间的", "释义串到 concern/regard", "回查原书基础词表，当前后半属于关心、涉及等词义"),
    "plan": ("n. 计划；方案；v. 计划；打算", "释义串到 formulate", "回查原书基础词表，当前后半属于系统阐述、公式表示"),
    "protection": ("n. 保护；防护", "释义串到 initiate", "回查原书基础词表，当前后半开始、实行义不属于 protection"),
    "snack": ("n. 小吃；快餐；v. 吃点心", "释义仅剩例句", "回查原书基础词表，当前只保留快餐例句而无主释义"),
    "achieve": ("v. 达到；完成；实现；取得", "释义串到 damage", "原书 achieve 词条列出达到、完成和成功义"),
    "preserve": ("v. 保护；保存；维持", "释义仅剩 maintain 的例句", "原书 preserve 词条：保护，保存"),
    "appointment": ("n. 约会；预约；约定；任命；职务", "释义仅剩例句", "原书 appointment 词条列出约会、预约、任命和职务等义"),
    "moral": ("adj. 道德的；道义的；品行端正的；n. 道德；寓意", "释义被真题正文覆盖", "原书 moral 词条列出道德、道义和品行端正等义"),
    "produce": ("v. 生产；制造；产生；提出；n. 农产品", "释义串到 associate", "原书 produce 词条列出生产、产生、提出等义；当前后半属于联合、联想"),
    "knowledge": ("n. 知识；学问；知道；了解", "释义仅剩真题例句", "原书 knowledge 词条列出知识、学问、知道和了解等义"),
    "salary": ("n. 薪水；薪金", "释义残缺且仅剩例句", "原书 salary 词条：薪水，薪金"),
    "according": ("prep. 根据；按照（according to）", "释义仅剩例句", "原书 according to 词条列出根据、按照等义"),
    "against": ("prep. 对着；逆着；反对；违反；倚靠", "释义仅剩例句", "原书 against 词条列出对着、逆着、反对、违反和倚靠等义"),
    "damp": ("adj. 潮湿的；v. 使减弱；抑制", "释义仅剩例句", "原书 damp 词条列出潮湿以及使减弱、抑制义"),
    "across": ("prep./adv. 穿过；横过；在对面", "释义串到 vessel", "原书当前整段列出船、容器、血管等 vessel 义，不属于 across"),
    "time": ("n. 时间；时刻；时期；次数；v. 计时", "释义串到 preach", "原书 time 词条列出时间、时机、时期、次数及动词义"),
    "between": ("prep./adv. 在……之间；在中间", "释义仅剩引文", "原书 between 词条列出在两者之间及中间义"),
    "finally": ("adv. 最后；最终；终于；彻底地", "释义仅剩例句", "原书 finally 词条列出最后、最终和彻底地等义"),
    "finish": ("v. 结束；完成；n. 结尾；最后阶段", "释义串到 endeavour", "原书 finish 词条列出结束、完成及结尾义"),
    "torment": ("n. 痛苦；苦恼；v. 折磨；欺负；虐待", "释义串到 naughty/wicked", "原书 torment 词条列出痛苦、折磨、欺负和虐待等义"),
    "country": ("n. 国家；郊外；乡村", "释义仅剩例句", "原书 country 词条列出国家、郊外和乡村义"),
    "fool": ("n. 笨蛋；傻瓜；v. 玩弄；愚弄", "释义串到 absolute/certain", "原书 fool 词条列出笨蛋、傻瓜、玩弄和愚弄义"),
    "much": ("adj./pron. 许多；大量；adv. 非常；更加", "释义仅剩例句", "原书 much 词条列出许多、大量及非常、更加等义"),
    "purpose": ("n. 目的；意图；用途；效果", "释义残缺并混入字符", "原书 purpose 词条列出目的、意图、用途和效果等义"),
    "rural": ("adj. 乡村的；农村的", "释义仅剩真题正文", "原书 rural 词条：乡村的，农村的"),
    "beauty": ("n. 美；美丽；美人；美好的事物", "释义串到 expression/wording", "回查原书基础词表，当前后半属于语句、措词义"),
    "best": ("adj. 最好的；adv. 最好地；n. 最佳；最好的人或物", "释义串到 seem", "回查原书基础词表，当前后半属于似乎、好像义"),
    "child": ("n. 儿童；孩子；子女", "释义仅剩例句", "回查原书基础词表，当前只保留儿童心理学例句"),
    "dangerous": ("adj. 危险的；不安全的", "释义仅剩例句", "回查原书基础词表，当前只保留危险工作的例句"),
    "electricity": ("n. 电；电力；电学", "释义串到 generate/doubt", "回查原书基础词表，当前内容混入产生及怀疑义"),
    "enjoy": ("v. 喜欢；享受；享有", "释义仅剩真题例句", "回查原书基础词表，当前只保留喜欢的例句"),
    "excellent": ("adj. 优秀的；极好的；卓越的", "释义仅剩例句", "回查原书基础词表，当前只保留优异服务的例句"),
    "historic": ("adj. 有历史意义的；历史性的", "释义仅剩例句", "回查原书基础词表，当前只保留有历史意义事件的例句"),
    "history": ("n. 历史；历史学；经历", "释义仅剩例句", "回查原书基础词表，当前只保留历史时刻的例句"),
    "home": ("n. 家；住所；adv. 在家；回家；adj. 家庭的", "释义仅剩例句", "回查原书基础词表，当前只保留在家的例句"),
    "orphan": ("n. 孤儿；v. 使成为孤儿", "释义仅剩例句", "回查原书基础词表，当前只保留孤儿院例句"),
    "rather": ("adv. 相当；颇；宁愿；反而", "释义仅剩 rather than 例句", "回查原书基础词表，当前只保留 rather than 的例句"),
    "diligence": ("n. 勤奋；勤勉", "释义串到 quality", "回查原书基础词表，当前内容属于品质、质量义"),
    "cunning": ("adj. 狡猾的；狡诈的；巧妙的", "释义串入近义形容词辨析", "原书 cunning 词条：狡猾的，狡诈的；并列出巧妙义"),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--audit-only", action="store_true")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        raise ValueError(f"UTF-8 BOM is not allowed: {path}")
    data = json.loads(raw.decode("utf-8"))
    if not isinstance(data, dict) or not isinstance(data.get("words"), list):
        raise ValueError("expected an object with a words list")
    return data


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def normalized_meaning(text: str) -> str:
    text = text.lower().replace("／", "/")
    return re.sub(r"[\s，。；：、,.!?！？（）()【】\[\]…·~～]+", "", text)


def pos_of(meaning: str) -> str:
    match = POS_RE.search(meaning[:40])
    return match.group(1).lower() if match else ""


def add_issue(
    target: list[dict[str, Any]],
    record: dict[str, Any],
    issue_type: str,
    reason: str,
    score: int,
    confidence: str,
    suggested: str = "",
    related_words: Iterable[str] = (),
) -> None:
    target.append(
        {
            "position": record["position"],
            "word": record["word"],
            "currentMeaning": record["meaning"],
            "issueType": issue_type,
            "reason": reason,
            "riskScore": score,
            "suggestedMeaning": suggested,
            "confidence": confidence,
            "relatedWords": list(related_words),
        }
    )


def morphology_pos_conflicts(word: str, meaning: str) -> list[str]:
    w = word.lower()
    pos = pos_of(meaning)
    if not pos:
        return []
    result: list[str] = []
    ly_exceptions = {
        "friendly", "lovely", "lonely", "likely", "lively", "daily", "early", "only", "silly", "ugly",
        "costly", "elderly", "orderly", "holy", "jolly", "family", "comply", "imply", "rely", "apply",
        "supply", "reply", "multiply", "fly", "rally", "belly", "bully", "ally", "assembly", "monopoly",
        "butterfly", "trolley/trolly", "bodily", "priestly", "timely", "weekly", "yearly", "deadly",
    }
    if w.endswith("ly") and w not in ly_exceptions and pos in {"n", "v", "vt", "vi", "adj"}:
        result.append("-ly 词形通常为副词，但当前词性不是 adv.")
    noun_exceptions = {"mention", "implement", "enhance", "commence", "freelance", "hence", "low-density", "dance", "envision"}
    if re.search(r"(tion|sion|ment|ness|ity|ship|ance|ence|ism|hood)$", w) and w not in noun_exceptions and pos not in {"n"}:
        result.append("名词后缀与当前词性明显冲突")
    adjective_exceptions = {"bless", "doubtless", "nevertheless", "regardless", "handful", "bible"}
    if re.search(r"(ous|ful|less|ible)$", w) and w not in adjective_exceptions and pos not in {"adj"}:
        result.append("形容词后缀与当前词性明显冲突")
    if re.search(r"(ize|ify|fy)$", w) and w not in {"outsize", "oversize", "prize"} and pos not in {"v", "vt", "vi"}:
        result.append("动词后缀与当前词性明显冲突")
    return result


def positive_base_candidates(word: str, known: set[str]) -> list[str]:
    lower = word.lower()
    result: list[str] = []
    for prefix in NEGATIVE_PREFIXES:
        if lower.startswith(prefix) and len(lower) > len(prefix) + 2:
            base = lower[len(prefix) :]
            variants = {base}
            if prefix == "im" and base.startswith("m"):
                variants.add(base)
            if prefix in {"ir", "il"}:
                variants.add(base)
            for candidate in variants:
                if candidate in known:
                    result.append(candidate)
    return sorted(set(result))


def build_audit(words: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    issues: list[dict[str, Any]] = []
    duplicate_groups: list[dict[str, Any]] = []
    by_meaning: dict[str, list[int]] = defaultdict(list)
    by_word = {record["word"].lower(): record for record in words}
    known = set(by_word)

    for index, record in enumerate(words):
        by_meaning[normalized_meaning(record["meaning"])].append(index)

    for normalized, indexes in by_meaning.items():
        if not normalized or len(indexes) < 2:
            continue
        group_words = [words[i]["word"] for i in indexes]
        group_key = frozenset(group_words)
        legitimate = group_key in LEGITIMATE_DUPLICATE_GROUPS
        duplicate_groups.append(
            {
                "meaning": words[indexes[0]]["meaning"],
                "words": group_words,
                "positions": [words[i]["position"] for i in indexes],
                "classification": "legitimate_near_synonyms" if legitimate else "suspicious",
            }
        )
        for i in indexes:
            duplicate_word = words[i]["word"]
            suggested = HIGH_CONFIDENCE_FIXES.get(duplicate_word, ("", "", ""))[0]
            is_correct_anchor = duplicate_word in CORRECT_DUPLICATE_ANCHORS
            add_issue(
                issues,
                words[i],
                "duplicate_meaning",
                f"与 {', '.join(w for w in group_words if w != words[i]['word'])} 的 meaning 完全相同"
                + ("；该组为可接受近义词" if legitimate else ("；原书确认该词是正确一侧" if is_correct_anchor else "；需判断是否串词")),
                0 if legitimate or is_correct_anchor else 4,
                "low" if legitimate or is_correct_anchor else ("high" if suggested else "medium"),
                suggested,
                [w for w in group_words if w != words[i]["word"]],
            )

    for i, record in enumerate(words):
        meaning = record["meaning"]
        word = record["word"]
        lower = word.lower()
        suggested = HIGH_CONFIDENCE_FIXES.get(word, ("", "", ""))[0]

        pollution_score = 0
        pollution_reasons: list[str] = []
        for pattern, score, reason in POLLUTION_RULES:
            if pattern.search(meaning):
                if lower == "appendix" and reason == "出现教材目录或分区文字" and not re.search(
                    r"历年真题|重点词|基础词|超纲词|检索表", meaning
                ):
                    continue
                pollution_score += score
                pollution_reasons.append(reason)
        if pollution_reasons:
            add_issue(
                issues, record, "textbook_pollution", "；".join(pollution_reasons), pollution_score,
                "high" if pollution_score >= 5 and suggested else "medium", suggested,
            )

        if len(meaning) > 80:
            add_issue(
                issues, record, "abnormal_length", f"meaning 长度为 {len(meaning)}，超过 80 字符", 3,
                "high" if suggested else "medium", suggested,
            )

        looks_sentence_like = len(meaning) > 15 and bool(
            re.match(
                r"^(?:adj\.|adv\.|n\.|v\.|vt\.|vi\.|conj\.|pron\.|prep\.|art\.)?\s*"
                r"(?:他|她|他们|我们|你们|这|该|一个|一种|所有|政府|当前|研究人员|面对|值得注意|例如)",
                meaning,
            )
        )
        if looks_sentence_like and not pollution_reasons:
            add_issue(
                issues,
                record,
                "textbook_pollution",
                "meaning 以完整例句或教材正文开头，可能已覆盖词条释义",
                3,
                "high" if suggested else "medium",
                suggested,
            )
        if lower in BASIC_COMMON_WORDS and (len(meaning) > 50 or pollution_reasons or looks_sentence_like):
            add_issue(
                issues, record, "basic_word_abnormal",
                f"基础常用词的 meaning 异常：长度 {len(meaning)}" + ("，且以例句式正文开头" if looks_sentence_like else ""),
                3, "high" if suggested else "medium", suggested,
            )

        for reason in morphology_pos_conflicts(word, meaning):
            add_issue(issues, record, "pos_conflict", reason, 2, "high" if suggested else "medium", suggested)

        for base in positive_base_candidates(word, known):
            base_record = by_word[base]
            left = normalized_meaning(meaning)
            right = normalized_meaning(base_record["meaning"])
            ratio = difflib.SequenceMatcher(None, left, right).ratio() if left and right else 0.0
            if left == right or ratio >= 0.9:
                add_issue(
                    issues, record, "antonym_conflict",
                    f"否定前缀词与正词 {base_record['word']} 的释义相同或高度近似（{ratio:.2f}）",
                    2, "high" if suggested else "medium", suggested, [base_record["word"]],
                )

        current_norm = normalized_meaning(meaning)
        neighbours: list[tuple[float, dict[str, Any]]] = []
        for j in range(max(0, i - 5), min(len(words), i + 6)):
            if j == i:
                continue
            other_norm = normalized_meaning(words[j]["meaning"])
            if not current_norm or not other_norm:
                continue
            ratio = difflib.SequenceMatcher(None, current_norm, other_norm).ratio()
            if current_norm == other_norm or (ratio >= 0.92 and min(len(current_norm), len(other_norm)) >= 8):
                neighbours.append((ratio, words[j]))
        if neighbours:
            best_ratio, best = max(neighbours, key=lambda item: item[0])
            pair = frozenset({word, best["word"]})
            if pair not in LEGITIMATE_DUPLICATE_GROUPS:
                add_issue(
                    issues, record, "neighbor_shift",
                    f"与前后 5 词中的 {best['word']} 释义高度重复（{best_ratio:.2f}）",
                    4, "high" if suggested else "medium", suggested, [best["word"]],
                )

        if RESIDUE_RE.search(meaning):
            add_issue(issues, record, "textbook_pollution", "出现～或栏目标签等提取残留", 1, "low", suggested)

        if suggested and not any(x["word"] == word and x["confidence"] == "high" for x in issues):
            _, reason, _ = HIGH_CONFIDENCE_FIXES[word]
            add_issue(issues, record, "neighbor_shift", reason, 4, "high", suggested)

    # Add an explicit manual_review record for each unresolved medium/high-risk word.
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for issue in issues:
        grouped[issue["word"]].append(issue)
    for word, word_issues in list(grouped.items()):
        if word in HIGH_CONFIDENCE_FIXES or word in SOURCE_VERIFIED_UNCHANGED:
            continue
        score = sum(item["riskScore"] for item in word_issues)
        if score < 3:
            continue
        record = next(item for item in words if item["word"] == word)
        add_issue(
            issues, record, "manual_review",
            "；".join(sorted({item["reason"] for item in word_issues})), score,
            "medium", "", sorted({related for item in word_issues for related in item["relatedWords"]}),
        )

    issues.sort(key=lambda item: (-item["riskScore"], item["position"], item["issueType"]))
    duplicate_groups.sort(key=lambda item: item["positions"])
    return issues, duplicate_groups


def apply_high_confidence_fixes(data: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    revised = copy.deepcopy(data)
    changes: list[dict[str, Any]] = []
    for record in revised["words"]:
        fix = HIGH_CONFIDENCE_FIXES.get(record["word"])
        if not fix:
            continue
        new_meaning, reason, source_basis = fix
        if record["meaning"] == new_meaning:
            continue
        changes.append(
            {
                "position": record["position"],
                "word": record["word"],
                "before": record["meaning"],
                "after": new_meaning,
                "reason": reason,
                "sourceBasis": source_basis,
            }
        )
        record["meaning"] = new_meaning
    revised["book"]["id"] = "kaoyan_v3"
    revised["book"]["version"] = 3
    return revised, changes


def build_review(words: list[dict[str, Any]], issues: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_word: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for issue in issues:
        if issue["issueType"] == "manual_review":
            by_word[issue["word"]].append(issue)
    record_by_word = {record["word"]: record for record in words}
    result: list[dict[str, Any]] = []
    for word, word_issues in sorted(by_word.items(), key=lambda item: record_by_word[item[0]]["position"]):
        issue = max(word_issues, key=lambda item: item["riskScore"])
        result.append(
            {
                "position": record_by_word[word]["position"],
                "word": word,
                "currentMeaning": record_by_word[word]["meaning"],
                "issueType": "manual_review",
                "reason": issue["reason"],
                "suggestedMeaning": issue.get("suggestedMeaning", ""),
                "confidence": "medium",
            }
        )
    return result


def validate_integrity(original: dict[str, Any], revised: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    old_words = original["words"]
    new_words = revised["words"]
    if len(old_words) != len(new_words) or len(new_words) != 5847:
        errors.append("单词数量不是 5847 或发生变化")
        return errors
    if [r["position"] for r in new_words] != list(range(1, 5848)):
        errors.append("position 不连续")
    if len({r["position"] for r in new_words}) != len(new_words):
        errors.append("position 不唯一")
    if len({r["id"] for r in new_words}) != len(new_words):
        errors.append("id 不唯一")
    for old, new in zip(old_words, new_words):
        if not isinstance(new.get("word"), str) or not new["word"].strip():
            errors.append(f"position {new.get('position')} word 为空")
        if not isinstance(new.get("meaning"), str) or not new["meaning"].strip():
            errors.append(f"position {new.get('position')} meaning 为空")
        for field in ("id", "position", "word", "phonetic", "example"):
            if old.get(field) != new.get(field):
                errors.append(f"position {old.get('position')} 字段 {field} 被修改")
    for field in ("expectedWordCount", "source", "licenseNote"):
        if original["book"].get(field) != revised["book"].get(field):
            errors.append(f"book.{field} 被修改")
    if revised["book"].get("id") != "kaoyan_v3" or revised["book"].get("version") != 3:
        errors.append("book.id/version 未更新为 v3")
    return errors


def render_report(
    total: int,
    issues: list[dict[str, Any]],
    duplicate_groups: list[dict[str, Any]],
    changes: list[dict[str, Any]],
    reviews: list[dict[str, Any]],
    pdf_path: Path,
) -> str:
    risk_words = {item["word"] for item in issues if item["riskScore"] >= 3}
    type_words: dict[str, set[str]] = defaultdict(set)
    for item in issues:
        type_words[item["issueType"]].add(item["word"])
    lines = [
        "# 第二轮词库释义纠错报告",
        "",
        f"总词数：{total}",
        f"本轮扫描条目：{total}",
        f"风险条目：{len(risk_words)}",
        f"高置信度错误：{len(changes)}",
        f"实际修改：{len(changes)}",
        f"人工复核：{len(reviews)}",
        f"PDF 回查后保留原样：{len(SOURCE_VERIFIED_UNCHANGED)}",
        f"完全相同 meaning 分组数量：{len(duplicate_groups)}",
        f"教材正文污染数量：{len(type_words['textbook_pollution'])}",
        f"疑似相邻串词数量：{len(type_words['neighbor_shift'])}",
        f"词性异常数量：{len(type_words['pos_conflict'])}",
        "",
        "## 原始来源",
        "",
        f"- PDF：`{pdf_path}`",
        "- 高风险词优先回查原书双栏词条、词汇预览和相邻正文。",
        "",
        "## 修改前后 diff",
        "",
        "| position | word | 修改前 | 修改后 | 原因 |",
        "|---:|---|---|---|---|",
    ]
    for change in changes:
        before = change["before"].replace("|", "\\|").replace("\n", " ")
        after = change["after"].replace("|", "\\|").replace("\n", " ")
        reason = change["reason"].replace("|", "\\|")
        lines.append(f"| {change['position']} | {change['word']} | {before} | {after} | {reason} |")
    if not changes:
        lines.append("| - | - | 无 | 无 | 本轮无高置信度修改 |")
    lines.extend(
        [
            "",
            "## 完整性要求",
            "",
            "- `kaoyan_v2.json` 保留不覆盖。",
            "- v3 仅修改高置信度条目的 `meaning`，并将 `book.id/version` 更新为 `kaoyan_v3/3`。",
            "- `expectedWordCount`、`source`、`licenseNote` 保持不变。",
            "- `phonetic`、`example`、单词顺序、id 和 position 均保持不变。",
            "- 完整性校验已通过：JSON 可解析，5847 个 position 连续且唯一，id 唯一，word/meaning 均非空。",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)
    data = read_json(args.input)
    issues, duplicate_groups = build_audit(data["words"])
    source = {
        "path": str(args.pdf),
        "available": args.pdf.exists(),
        "pages": None,
    }
    if args.pdf.exists():
        try:
            from pypdf import PdfReader  # type: ignore

            source["pages"] = len(PdfReader(str(args.pdf)).pages)
        except Exception as exc:  # pragma: no cover
            source["readError"] = str(exc)
    audit_payload = {
        "input": str(args.input),
        "totalWords": len(data["words"]),
        "source": source,
        "riskScoring": {
            "textbookSentenceAnalysis": 5,
            "unrelatedExactDuplicate": 4,
            "neighborShift": 4,
            "basicWordOver80": 3,
            "directoryOrWebPollution": 3,
            "posConflict": 2,
            "distinguishOrExampleResidue": 2,
            "negativePrefixConflict": 2,
            "minorExtractionResidue": 1,
        },
        "duplicateMeaningGroupCount": len(duplicate_groups),
        "duplicateMeaningGroups": duplicate_groups,
        "issueCount": len(issues),
        "issueTypeCounts": {
            issue_type: sum(1 for issue in issues if issue["issueType"] == issue_type)
            for issue_type in ISSUE_TYPES
        },
        "issues": issues,
    }
    write_json(args.out_dir / "meaning_audit_full_v2.json", audit_payload)
    if args.audit_only:
        print(
            json.dumps(
                {
                    "totalWords": len(data["words"]),
                    "issues": len(issues),
                    "riskWords": len({item['word'] for item in issues if item['riskScore'] >= 3}),
                    "duplicateGroups": len(duplicate_groups),
                    "audit": str(args.out_dir / "meaning_audit_full_v2.json"),
                },
                ensure_ascii=False,
            )
        )
        return 0

    revised, changes = apply_high_confidence_fixes(data)
    reviews = build_review(data["words"], issues)
    integrity_errors = validate_integrity(data, revised)
    if integrity_errors:
        raise RuntimeError("integrity validation failed: " + "; ".join(integrity_errors[:10]))
    write_json(args.out_dir / "kaoyan_v3.json", revised)
    write_json(args.out_dir / "meaning_review_needed_v2.json", reviews)
    (args.out_dir / "meaning_fix_report_v2.md").write_text(
        render_report(len(data["words"]), issues, duplicate_groups, changes, reviews, args.pdf),
        encoding="utf-8",
        newline="\n",
    )
    print(
        json.dumps(
            {
                "totalWords": len(data["words"]),
                "riskWords": len({item['word'] for item in issues if item['riskScore'] >= 3}),
                "highConfidenceErrors": len(changes),
                "modified": len(changes),
                "manualReview": len(reviews),
                "duplicateGroups": len(duplicate_groups),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
