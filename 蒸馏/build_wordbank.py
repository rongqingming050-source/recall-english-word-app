import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pdfplumber


PDF_PATH = Path(sys.argv[1])
OUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else PDF_PATH.parent
OUT_DIR.mkdir(parents=True, exist_ok=True)

try:
    import eng_to_ipa
except Exception:
    eng_to_ipa = None


PREVIEW_TITLE = "\u672c\u5355\u5143\u8bcd\u6c47\u9884\u89c8"
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z0-9'()/\-.]*$")
HEAD_RE = re.compile(
    r"^\s*([A-Za-z][A-Za-z0-9'()/.\-]*(?:/[A-Za-z][A-Za-z0-9'()/.\-]*)?)\s*\["
)
CN_RE = re.compile(r"[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]+")
POS_RE = re.compile(r"\b(?:n|v|vt|vi|adj|adv|prep|conj|pron|aux|num|int|det|art|modal)\.?\b", re.I)


def clean_token(text: str):
    text = re.sub(r"^[\u25a0\u25a1]+", "", text)
    return text if WORD_RE.fullmatch(text) else None


def preview_words(page):
    words = page.extract_words(x_tolerance=1, y_tolerance=2)
    title = [w for w in words if PREVIEW_TITLE in w["text"]]
    if not title:
        return None
    title_top = min(w["top"] for w in title)
    candidates = []
    for w in words:
        if title_top + 12 < w["top"] < 500 and w["x0"] < 530:
            token = clean_token(w["text"])
            if token:
                candidates.append((w["top"], w["x0"], token))
    rows = sorted({round(top, 1) for top, _, _ in candidates})
    end = 500
    for before, after in zip(rows, rows[1:]):
        if before > title_top + 20 and after - before > 16:
            end = before + 2
            break
    candidates = [item for item in candidates if item[0] < end]

    # The seven-column preview is the book's stable order: top-to-bottom
    # within each column, then left-to-right across columns.
    x_values = sorted({x for _, x, _ in candidates})
    x_groups = []
    for x in x_values:
        if not x_groups or x - x_groups[-1][-1] > 25:
            x_groups.append([x])
        else:
            x_groups[-1].append(x)

    ordered = []
    for group in x_groups:
        column = [item for item in candidates if item[1] in group]
        column.sort(key=lambda item: (item[0], item[1]))
        column_tokens = [item[2] for item in column]
        i = 0
        while i < len(column_tokens):
            if (
                column_tokens[i] == "according"
                and i + 1 < len(column_tokens)
                and column_tokens[i + 1] == "to"
            ):
                ordered.append("according to")
                i += 2
            else:
                ordered.append(column_tokens[i])
                i += 1
    return {"words": ordered, "entry_start": end + 10}


def simple_words(page):
    result = []
    bottom = min(755, page.height)
    right = min(560, page.width)
    for side, box in (
        ("L", (20, 150, 280, bottom)),
        ("R", (280, 150, right, bottom)),
    ):
        text = page.crop(box).extract_text(x_tolerance=1, y_tolerance=3) or ""
        for line in text.splitlines():
            match = HEAD_RE.match(line)
            if match:
                result.append(match.group(1))
    return result


def normalize_word(word: str):
    word = word.strip()
    explicit = {
        "judg(e)ment": "judgment/judgement",
        "accommodation(s)": "accommodation",
        "among(st)": "among/amongst",
        "favo(n)rable": "favourable",
        "marvel(1)ous": "marvellous",
        "humo(u)rous": "humorous",
        "behavio(n)r": "behaviour",
        "special(i)ty": "specialty",
        "analytic(al)": "analytic/analytical",
        "amid(st)": "amid/amongst",
        "gram(me)": "gram/gramme",
        "clasification": "classification",
        "analyse/-yze": "analyse/analyze",
        "wag(g)on": "wagon",
        "fantastic(al)": "fantastic",
        "out-0f-town": "out-of-town",
        "savanna(h)": "savanna/savannah",
        "lcheat": "cheat",
        "Iyric": "lyric",
        "Ibreast": "breast",
        "mouId": "mould",
        "fexibility": "flexibility",
        "int.": "",
        "carcease/carcass": "carcase/carcass",
        "disappearr": "disappear",
    }
    if word in explicit:
        return explicit[word]
    lower_explicit = {key.lower(): value for key, value in explicit.items()}
    if word.lower() in lower_explicit:
        return lower_explicit[word.lower()]
    substitutions = [
        ("(u)", "u"),
        ("(ue)", "ue"),
        ("(e)", "e"),
        ("(a)", "a"),
        ("(l)", "l"),
        ("(1)", "l"),
        ("(s)", ""),
    ]
    for old, new in substitutions:
        word = word.replace(old, new)
    if word.endswith("/-ise"):
        base = word[:-5]
        word = base + "/" + (base[:-3] + "ise" if base.endswith("ize") else base + "ise")
    return word


def split_variants(word: str):
    return [part for part in re.split(r"/", word) if part and part != "-ise"]


def ipa_for(word: str):
    if eng_to_ipa is None:
        return ""
    manual = {
        "favourable": "/ˈfeɪvərəbəl/", "up-to-date": "/ˌʌp tə ˈdeɪt/",
        "characterise": "/ˈkærəktəraɪz/", "paralyse": "/ˈpærəlaɪz/",
        "specialty": "/ˈspɛʃəlti/", "analyse/-yze": "/ˈænəlaɪz/",
        "analyse/analyze": "/ˈænəlaɪz/", "analytic/analytical": "/ˌænəˈlɪtɪk/; /ˌænəˈlɪtɪkəl/",
        "ski": "/skiː/", "amid/amongst": "/əˈmɪd/; /əˈmʌŋst/",
        "clasification": "/ˌklæsəfɪˈkeɪʃən/", "gram/gramme": "/ɡræm/",
        "manoeuvre": "/məˈnuːvə/", "wagon": "/ˈwæɡən/",
        "vapour": "/ˈveɪpə/", "fantastic": "/fænˈtæstɪk/",
        "flavour": "/ˈfleɪvə/", "flu": "/fluː/", "lyric": "/ˈlɪrɪk/",
        "coronavirus": "/ˌkɔːrəˈnaɪvərəs/", "breast": "/brɛst/",
        "mould": "/məʊld/", "living-room": "/ˈlɪvɪŋˌruːm/",
        "preposition": "/ˌprɛpəˈzɪʃən/", "tumour": "/ˈtuːmə/",
        "arrestee": "/ˌærəˈstiː/", "asocial": "/eɪˈsoʊʃəl/",
        "baluster": "/ˈbæləstər/", "biophilia": "/ˌbaɪəˈfɪliə/",
        "biotic": "/baɪˈɑtɪk/", "bisect": "/baɪˈsɛkt/",
        "by-product": "/ˈbaɪˌprɑdʌkt/", "cure-all": "/ˈkjʊrˌɔl/",
        "dazzlingly": "/ˈdæzəlɪŋli/", "dishonour": "/dɪsˈɑnər/",
        "double-glaze": "/ˌdʌbəlˈɡleɪz/", "enchantingly": "/ɪnˈtʃæntɪŋli/",
        "ephemera": "/ɪˈfɛmərə/", "explicatory": "/ɪkˈsplɪkətɔri/",
        "fieldcraft": "/ˈfiːldkræft/", "flexibility": "/ˌflɛksəˈbɪləti/",
        "fritillary": "/ˈfrɪtəˌlɛri/", "frizzle": "/ˈfrɪzəl/",
        "futurologist": "/ˌfjuːtʃəˈrɑlədʒɪst/", "greengrocer": "/ˈɡriːnˌɡroʊsər/",
        "heatstroke": "/ˈhiːtˌstroʊk/", "illiberal": "/ɪˈlɪbərəl/",
        "inexpressible": "/ˌɪnɪkˈsprɛsəbəl/", "jobseeker": "/ˈdʒɑbˌsiːkər/",
        "know-it-all": "/ˈnoʊɪtˌɔl/", "longline": "/ˈlɔŋˌlaɪn/",
        "low-density": "/ˌloʊˈdɛnsəti/", "male-dominated": "/ˌmeɪlˈdɑməˌneɪtəd/",
        "marquetry": "/ˈmɑrkɪtri/", "monoglot": "/ˈmɑnəˌɡlɑt/",
        "mutability": "/ˌmjuːtəˈbɪləti/", "neolithic": "/ˌniːəˈlɪθɪk/",
        "netball": "/ˈnɛtˌbɔl/", "non-materialistic": "/ˌnɑn məˌtɪriəˈlɪstɪk/",
        "off-the-cuff": "/ˌɔf ðə ˈkʌf/", "omnivore": "/ˈɑmnɪˌvɔr/",
        "out-of-town": "/ˌaʊt əv ˈtaʊn/", "over-the-counter": "/ˌoʊvər ðə ˈkaʊntər/",
        "paediatrics": "/ˌpiːdiˈætrɪks/", "peer-reviewed": "/ˌpɪr rɪˈvjuːd/",
        "profit-making": "/ˈprɑfətˌmeɪkɪŋ/", "pushback": "/ˈpʊʃˌbæk/",
        "quick-witted": "/ˌkwɪkˈwɪtɪd/", "rasher": "/ˈræʃər/",
        "re-evaluate": "/ˌriɪˈvæljuˌeɪt/", "sea-pink": "/ˈsiːˌpɪŋk/",
        "savanna/savannah": "/səˈvænə/", "int": "/ɪnt/",
        "skint": "/skɪnt/", "slipup": "/ˈslɪpˌʌp/", "stickiness": "/ˈstɪkɪnəs/",
        "subhead": "/ˈsʌbˌhɛd/", "suboptimal": "/ˌsʌbˈɑptəməl/",
        "think-tank": "/ˈθɪŋkˌtæŋk/", "timescale": "/ˈtaɪmˌskeɪl/",
        "toll-free": "/ˈtoʊlˌfriː/", "transcendentalist": "/ˌtrænsɛndənˈtælɪst/",
        "unlearned": "/ˌʌnˈlɜrnd/", "woodcut": "/ˈwʊdˌkʌt/",
    }
    if word in manual:
        return manual[word]
    aliases = {
        "characterise": "characterize", "paralyse": "paralyze",
        "specialty": "specialty", "up-to-date": "up to date",
        "living-room": "living room", "preposition": "preposition",
        "analytic/analytical": "analytic/analytical", "specialize/specialise": "specialize/specialise",
    }
    values = []
    for variant in split_variants(word.lower()):
        variant = aliases.get(variant, variant)
        if variant.endswith("/ise"):
            variant = variant[:-4] + "ise"
        try:
            value = eng_to_ipa.convert(variant).strip()
        except Exception:
            value = ""
        if value and "*" not in value and value != variant:
            values.append(value)
    if not values:
        return ""
    unique = []
    for value in values:
        if value not in unique:
            unique.append(value)
    return "; ".join(f"/{value}/" for value in unique)


def first_english_token(line: str):
    line = line.strip()
    match = re.match(r"([A-Za-z][A-Za-z0-9'()/\.\-]*)", line)
    return match.group(1) if match else ""


def normalize_pos(text: str):
    match = POS_RE.search(text.replace("ado.", "adv.").replace("adu.", "adv.").replace("ut.", "vt."))
    return match.group(0).lower().rstrip(".") if match else ""


def chinese_meaning(text: str):
    text = re.sub(r"\s+", " ", text).strip()
    # Keep concise material before the first example or comparison section.
    pieces = []
    for part in re.split(r"(?=[①②③④⑤⑥⑦])", text):
        part = part.strip(" ;,，")
        if not part:
            continue
        if "：" in part:
            part = part.split("：", 1)[0]
        elif ":" in part:
            part = part.split(":", 1)[0]
        chinese = "".join(CN_RE.findall(part))
        if chinese:
            pieces.append(chinese)
    if not pieces:
        pieces = ["".join(CN_RE.findall(text))]
    result = "；".join(pieces)
    result = re.sub(r"；+", "；", result).strip("；")
    return result


def meaning_from_block(block: str):
    block = re.sub(r"\s+", " ", block).strip()
    pos = normalize_pos(block[:260])
    marker_match = re.search(r"【词义[】\]]", block)
    if marker_match:
        section = block[marker_match.end() :]
        section = re.split(r"【(?:同义|反义|辨析|词组|派生|典型考题|真题例句|助记)[】\]]", section, 1)[0]
        meaning = chinese_meaning(section)
        if meaning:
            return (f"{pos}. {meaning}" if pos else meaning).replace("..", ".")
    # Simple entries and super-words put the Chinese meaning after the IPA/POS.
    meaning = chinese_meaning(block)
    if meaning:
        return (f"{pos}. {meaning}" if pos else meaning).replace("..", ".")
    return ""


MANUAL_MEANINGS = {
    "fierce": "adj. 凶猛的；激烈的；强烈的",
    "economical": "adj. 经济的；节俭的；合算的",
    "perfect": "adj. 完美的；完全的；v. 使完善",
    "mate": "n. 伙伴；配偶；v. 交配；使成对",
    "underlie": "v. 构成……的基础；位于……之下",
    "aim": "n. 目标；目的；v. 旨在；瞄准",
    "increasingly": "adv. 越来越多地；日益",
    "literary": "adj. 文学的；书面的",
    "collide": "v. 碰撞；冲突",
    "commit": "v. 犯错误或罪；承诺；投入",
    "political": "adj. 政治的；政党的",
    "impact": "n. 影响；冲击；v. 影响；撞击",
    "optimum": "adj. 最佳的；n. 最佳条件",
    "selection": "n. 选择；选拔；精选品",
    "locality": "n. 地区；位置",
    "application": "n. 申请；应用；施用",
    "information": "n. 信息；资料",
    "answer": "n. 答案；回答；v. 回答；适合",
    "construct": "v. 建造；构造；n. 建筑物；构想",
    "volunteer": "n. 志愿者；v. 自愿",
    "reply": "n. 回复；v. 回答",
    "productivity": "n. 生产率；生产力",
    "promise": "n. 诺言；希望；v. 承诺；有希望",
    "prospect": "n. 前景；可能性；景象",
    "terrible": "adj. 可怕的；糟糕的",
    "net": "n. 网；净额；v. 得到；捕捉",
    "deck": "n. 甲板；平台；一副；v. 装饰；打倒",
    "quarter": "n. 四分之一；季度；地区",
    "grade": "n. 等级；成绩；年级；v. 分级",
    "advertise": "v. 做广告；宣传；公布",
    "velvet": "n. 天鹅绒；adj. 天鹅绒的",
    "bail": "n. 保释金；v. 保释；帮助脱离困境",
    "tangle": "v. 使缠结；n. 纠结；混乱",
    "recession": "n. 衰退；不景气",
    "instrument": "n. 工具；仪器；乐器",
    "flavour": "n. 味道；风味；特色；v. 给……调味",
    "comet": "n. 彗星",
    "workout": "n. 锻炼；训练；解决办法",
    "steep": "adj. 陡峭的；过高的；v. 浸泡；急剧上升",
    "discount": "n. 折扣；不信；v. 打折；不重视",
    "broad": "adj. 宽的；广泛的；adv. 宽阔地",
    "sturdy": "adj. 结实的；坚固的；强健的",
    "avert": "v. 避免；转移",
    "cyberspace": "n. 网络空间",
    "courtship": "n. 求爱；求偶",
    "pool": "n. 水池；游泳池；一组；v. 集中",
    "object": "n. 物体；对象；目的；v. 反对",
    "observation": "n. 观察；观测；观察结果；评论",
    "identify": "v. 识别；确认；把……等同于",
    "justice": "n. 公平；正义；司法；法官",
    "medium": "n. 中间；媒介；介质；手段",
    "media": "n. 媒体；传媒",
    "separate": "adj. 分开的；单独的；不相关的；v. 分开；隔开",
    "mind": "n. 思想；头脑；介意；v. 留意；介意",
    "official": "adj. 官方的；正式的；公务的；n. 官员",
    "observable": "adj. 能看得到的；能察觉的",
    "person": "n. 人；个人；人身",
    "Christ": "n. 基督教救世主，特指耶稣基督",
    "abolish": "v. 废除；取消",
    "acceptance": "n. 接受；承认；赞同",
    "define": "v. 解释；给……下定义；规定",
    "happen": "v. 发生；碰巧",
    "occupation": "n. 职业；占领；消遣",
    "temper": "n. 脾气；性情；v. 调和；使缓和",
    "bill": "n. 账单；钞票；议案；v. 开账单",
    "feeling": "n. 感觉；感情；看法",
    "acquire": "v. 获得；学到；购得",
    "advice": "n. 建议；忠告",
    "toast": "n. 烤面包；祝酒；v. 烘烤；为……干杯",
    "remind": "v. 提醒；使想起",
    "statistics": "n. 统计学；统计数据",
    "amaze": "v. 使惊奇",
    "thread": "n. 线；线程；话题；v. 穿线",
    "pedal": "n. 踏板；v. 踩踏板",
    "permeate": "v. 渗透；弥漫",
    "lame": "adj. 跛的；蹩脚的；v. 使跛",
    "hijack": "v. 劫持；操纵",
    "ancient": "adj. 古代的；古老的",
    "bracket": "n. 括号；支架；档次；v. 把……括在一起",
    "stitch": "n. 一针；缝线；v. 缝合",
    "revolution": "n. 革命；旋转；变革",
    "crow": "n. 乌鸦；喧叫；v. 啼叫；自鸣得意",
    "muscular": "adj. 肌肉的；强壮的",
    "yearning": "n. 渴望；向往",
    "elaborate": "adj. 精心制作的；详尽的；复杂的；v. 详述；精心制作",
    "element": "n. 要素；元素；成分",
    "absence": "n. 缺席；不存在；缺乏",
    "site": "n. 地点；场所；网站；v. 安置",
    "elsewhere": "adv. 在别处；到别处",
    "behaviour": "n. 行为；举止",
    "generator": "n. 发电机；产生者",
    "partner": "n. 伙伴；搭档；合伙人；v. 合作",
    "oppose": "v. 反对；对抗",
    "underlying": "adj. 根本的；潜在的；在下面的",
    "browse": "v. 浏览；随意观看；吃嫩叶",
    "alternative": "n. 可供选择的事物；adj. 可替代的",
    "complicated": "adj. 复杂的；难懂的",
    "indicate": "v. 表明；指出；暗示",
    "indication": "n. 表明；迹象；指示",
    "accompany": "v. 陪伴；伴随；为……伴奏",
    "actual": "adj. 实际的；真实的",
    "mention": "v. 提到；说起；n. 提及",
    "signal": "n. 信号；暗号；v. 示意；向……发信号",
    "address": "n. 地址；演说；v. 对付；向……讲话",
    "personal": "adj. 个人的；私人的；亲自的",
    "guild": "n. 行会；协会",
    "deprive": "v. 剥夺；使丧失",
    "impair": "v. 损害；削弱",
    "optional": "adj. 可选择的；非强制的",
    "board": "n. 木板；委员会；董事会；v. 上船；寄宿",
    "ingredient": "n. 成分；原料；要素",
    "exert": "v. 运用；施加；努力",
    "subscribe": "v. 订阅；同意；捐款",
    "inference": "n. 推断；推论",
    "primitive": "adj. 原始的；简陋的；n. 原始人",
    "liability": "n. 责任；债务；不利条件",
    "region": "n. 地区；区域；领域",
    "assistance": "n. 帮助；援助",
    "prolong": "v. 延长；拉长",
    "rectify": "v. 纠正；整顿",
    "terror": "n. 恐怖；惊骇；恐怖行为",
    "kin": "n. 亲属；家族",
    "glide": "v. 滑行；悄悄移动；n. 滑行",
    "besides": "adv. 此外；而且；prep. 除……之外",
    "nominal": "adj. 名义上的；象征性的；微不足道的",
    "sink": "v. 下沉；陷入；n. 水槽；洗涤槽",
    "slam": "v. 砰地关上；猛击；n. 猛然撞击",
    "plunge": "v. 投入；骤降；n. 突然下降；投入",
    "trench": "n. 沟；战壕；海沟",
    "siege": "n. 包围；围攻",
    "silence": "n. 寂静；沉默；v. 使沉默",
    "volatile": "adj. 易变的；不稳定的；挥发性的",
    "accent": "n. 口音；重音；强调；v. 重读；强调",
    "tear": "n. 眼泪；撕裂；v. 撕裂",
    "coarse": "adj. 粗糙的；粗俗的",
    "abundant": "adj. 丰富的；充裕的",
    "handle": "n. 柄；把手；v. 处理；应付",
    "illiterate": "adj. 不识字的；文盲的",
    "acquaint": "v. 使熟悉；告知",
    "solar": "adj. 太阳的",
    "hierarchy": "n. 等级制度；层次；统治集团",
    "merchant": "n. 商人；店主",
    "instruct": "v. 指示；指导；教育",
    "liquid": "n. 液体；adj. 液体的；液态的",
    "stab": "v. 刺；戳；n. 刺；刺伤",
    "consolidate": "v. 巩固；合并",
    "bite": "v. 咬；刺痛；n. 咬；咬伤",
    "resolve": "v. 解决；决定；分解；n. 决心；解决",
    "spouse": "n. 配偶",
    "width": "n. 宽度；广度",
    "foam": "n. 泡沫；v. 起泡",
    "bleak": "adj. 阴冷的；荒凉的；黯淡的",
    "envisage": "v. 想象；设想",
    "mild": "adj. 温和的；轻微的；淡的",
    "anniversary": "n. 周年纪念日",
    "appall": "v. 使惊骇；使恐惧",
    "hollow": "adj. 空的；空洞的；n. 洞；凹陷",
    "installment": "n. 分期付款；一期；安装",
    "limb": "n. 肢体；树枝；分支",
    "dot": "n. 点；小圆点；v. 点缀；打点",
    "loyalty": "n. 忠诚；忠心",
    "forehead": "n. 前额",
    "static": "adj. 静态的；静止的；n. 静电；静态",
    "discreet": "adj. 谨慎的；慎重的",
    "dislike": "v. 不喜欢；n. 不喜欢",
    "retreat": "v. 撤退；退避；n. 撤退；隐居处",
    "auction": "n. 拍卖；v. 拍卖",
    "explode": "v. 爆炸；爆发；激增",
    "ozone": "n. 臭氧",
    "provoke": "v. 激起；引发；挑衅",
    "pull": "v. 拉；拖；吸引；n. 拉力；影响",
    "buck": "n. 雄鹿；美元；小伙子；v. 猛然弯曲；抵制",
}


def example_for(word: str, meaning: str, position: int):
    target = split_variants(word)[0]
    pos = normalize_pos(meaning)
    special = {
        "a": "She bought a book for the long train journey.",
        "an": "An unexpected delay changed the schedule completely.",
        "at": "The meeting begins at nine o'clock tomorrow morning.",
        "be": "The results will be available after the review.",
        "in": "The researchers found a clear pattern in the data.",
        "of": "The final chapter explains the purpose of the study.",
        "to": "The team worked together to solve the difficult problem.",
        "and": "The report compares local conditions and national trends.",
        "or": "You can choose tea or coffee with your breakfast.",
        "if": "The plan will succeed if everyone follows the instructions.",
        "but": "The task was difficult, but the team finished it.",
        "for": "The new policy was designed for young workers.",
        "on": "The book is on the table beside the window.",
        "by": "The final decision was made by the committee.",
        "from": "The results differ from those reported last year.",
        "with": "She solved the problem with a simple method.",
        "about": "The lecture is about how technology changes daily work.",
    }
    if target in special:
        return special[target]
    templates = {
        "v": [
            "Researchers will {w} the evidence before making a decision.",
            "The team decided to {w} the plan after reviewing the data.",
            "Clear rules can help people {w} problems more effectively.",
        ],
        "vt": [
            "The committee will {w} the proposal after a careful review.",
            "This method can {w} the process and reduce unnecessary costs.",
        ],
        "adj": [
            "The researchers described the result as {w} and highly significant.",
            "{article} {w} approach can improve the quality of the final report.",
            "The committee considered the proposal {w} and practical.",
        ],
        "adv": [
            "The policy was {w} revised after the independent review.",
            "The two groups responded {w} to the same question.",
        ],
        "prep": [
            "The discussion focused {w} the causes of the problem.",
            "The students walked {w} the river before returning home.",
        ],
        "conj": [
            "The results were unexpected, {w} the researchers continued the study.",
        ],
        "pron": [
            "Each participant explained how {w} understood the difficult issue.",
        ],
        "aux": [
            "The findings {w} be checked again before publication.",
        ],
        "n": [
            "The study examines {w} and its effect on modern society.",
            "The report provides useful information about {w} in daily life.",
            "Researchers discussed the role of {w} in the new system.",
        ],
    }
    kind = pos if pos in templates else ("adv" if target.endswith("ly") else "adj" if target.endswith(("ous", "ive", "al", "ful", "less", "able", "ic")) else "n")
    choices = templates[kind]
    article = "An" if target[:1].lower() in "aeiou" else "A"
    return choices[position % len(choices)].format(w=target, article=article)


def build_source_index(pdf):
    pages = {}
    ordered_lists = {}
    for page_number, page in enumerate(pdf.pages, start=1):
        preview = preview_words(page)
        if preview:
            ordered_lists[page_number] = preview
            start_y = preview["entry_start"]
        else:
            # Some continuation pages begin their first entry just below the
            # running header, well above the unit-31/super-word headers.
            start_y = 50
        right = min(560, page.width)
        bottom = min(755, page.height)
        pages[page_number] = {
            "L": page.crop((20, start_y, 280, bottom)).extract_text(x_tolerance=1, y_tolerance=3) or "",
            "R": page.crop((280, start_y, right, bottom)).extract_text(x_tolerance=1, y_tolerance=3) or "",
        }
    return pages, ordered_lists


def build_line_index(source_pages, known_words=None):
    index = defaultdict(list)
    for page_number, cols in source_pages.items():
        for side, text in cols.items():
            lines = text.splitlines()
            for idx, line in enumerate(lines):
                token = first_english_token(line)
                if token:
                    index[normalize_word(token).lower()].append((page_number, side, idx, lines))
    return index


def block_lines(lines, start, limit=10, known_words=None, current_word=""):
    selected = [lines[start]]
    for line in lines[start + 1 : start + limit]:
        if HEAD_RE.match(line):
            break
        token = first_english_token(line)
        normalized = normalize_word(token).lower() if token else ""
        if (
            known_words
            and normalized in known_words
            and normalized != current_word.lower()
            and (len(line.strip()) < 90 or "[" in line or "]" in line)
        ):
            break
        selected.append(line)
    return selected


def locate_block(source_pages, raw_words, normalized_word, line_index=None, known_words=None):
    candidates = [raw_words]
    if normalized_word != raw_words:
        candidates.append(normalized_word)
    target_forms = {normalize_word(item).lower() for item in candidates}
    if line_index is not None:
        for form in target_forms:
            for page_number, side, idx, lines in line_index.get(form, []):
                block = "\n".join(block_lines(lines, idx, known_words=known_words, current_word=form))
                return block, page_number, side
    # The PDF text layer occasionally drops the first word of a heading or
    # joins it to a preceding line. Search nearby text as a second pass and
    # prefer contexts that contain the book's meaning marker.
    candidates_in_text = []
    forms = set()
    for form in target_forms:
        forms.update(part.lower() for part in split_variants(form))
    for page_number, cols in source_pages.items():
        for side, text in cols.items():
            lines = text.splitlines()
            for idx, line in enumerate(lines):
                lower = line.lower()
                if not any(re.search(rf"(?<![a-z]){re.escape(form)}(?![a-z])", lower) for form in forms):
                    continue
                context = lines[max(0, idx - 4) : idx + 10]
                context_text = " ".join(context)
                score = 0
                if re.search(r"【词义[】\]]", context_text):
                    score += 8
                if "[" in line or "]" in line:
                    score += 3
                if normalize_word(first_english_token(line)).lower() in target_forms:
                    score += 5
                candidates_in_text.append((score, page_number, side, idx, lines))
    if candidates_in_text:
        _, page_number, side, idx, lines = max(candidates_in_text, key=lambda item: (item[0], -item[1], -item[3]))
        block = "\n".join(lines[max(0, idx - 4) : idx + 10])
        return block, page_number, side
    for page_number, cols in source_pages.items():
        for side, text in cols.items():
            lines = text.splitlines()
            for idx, line in enumerate(lines):
                token = first_english_token(line)
                if token and normalize_word(token).lower() in target_forms:
                    block = "\n".join(block_lines(lines, idx, known_words=known_words, current_word=normalized_word))
                    return block, page_number, side
    return "", None, None


def collect_words(pdf):
    all_words = []
    for page_number, page in enumerate(pdf.pages, start=1):
        if 7 <= page_number <= 412:
            preview = preview_words(page)
            if preview:
                all_words.extend(("core", word) for word in preview["words"])
        if 404 <= page_number <= 412:
            # Unit 31 is a simple two-column list without a preview grid.
            all_words.extend(("basic", word) for word in simple_words(page))
        if 413 <= page_number <= 425:
            all_words.extend(("super", word) for word in simple_words(page))

    # A few simple lists overlap the preview range only by their page headers;
    # de-duplicate after normalizing spelling variants.
    cleaned = []
    seen = set()
    duplicates = []
    for section, raw in all_words:
        word = normalize_word(raw)
        word = word.replace("mouId", "mould").replace("fexibility", "flexibility")
        key = word.lower()
        if not key or key in seen:
            if key:
                duplicates.append({"word": word, "source": raw, "section": section})
            continue
        seen.add(key)
        cleaned.append({"section": section, "raw": raw, "word": word})
    return cleaned, duplicates


def main():
    with pdfplumber.open(PDF_PATH) as pdf:
        source_pages, _ = build_source_index(pdf)
        words, duplicates = collect_words(pdf)
        known_words = {item["word"].lower() for item in words}
        line_index = build_line_index(source_pages, known_words)
        total = len(words)
        records = []
        issues = []
        for position, item in enumerate(words, start=1):
            word = item["word"]
            block, page_number, side = locate_block(source_pages, item["raw"], word, line_index, known_words)
            meaning = MANUAL_MEANINGS.get(word, "") or meaning_from_block(block)
            if not meaning:
                issues.append({"position": position, "word": word, "issue": "未能从 PDF 可靠提取中文释义"})
                meaning = "n. 词条释义需人工核对"
            phonetic = ipa_for(word)
            if not phonetic:
                issues.append({"position": position, "word": word, "issue": "发音词典未覆盖，需人工核对 IPA"})
                phonetic = "/需核对/"
            if page_number is None and word not in MANUAL_MEANINGS:
                issues.append({"position": position, "word": word, "issue": "未定位到原书词条页"})
            example = example_for(word, meaning, position)
            records.append(
                {
                    "id": word.strip().lower(),
                    "position": position,
                    "word": word.strip(),
                    "phonetic": phonetic,
                    "meaning": meaning,
                    "example": example,
                }
            )

    data = {
        "schemaVersion": 1,
        "book": {
            "id": "kaoyan_v1",
            "name": "考研英语",
            "version": 1,
            "description": "《红宝书》考研英语词汇（必考词、基础词和超纲词）整理版",
            "expectedWordCount": total,
            "source": "用户提供的《2027红宝书.pdf》；整理范围为正文词汇部分（必考词、基础词、超纲词）。",
            "licenseNote": "原书版权归原权利人所有；本文件仅依据用户提供的资料整理，供个人学习使用，正式发布或分发前请核实授权。",
        },
        "words": records,
    }
    json_path = OUT_DIR / "kaoyan_v1.json"
    json_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    report_lines = [
        "# 数据校验报告",
        "",
        f"- 来源文件：`{PDF_PATH.name}`",
        f"- 词条总数：{total}",
        f"- 去重后重复项：{len(duplicates)}",
        f"- 自动发现问题：{len(issues)}",
        "",
        "## 结构校验",
        "",
        f"- schemaVersion：{data['schemaVersion']}",
        f"- book.id：{data['book']['id']}",
        f"- expectedWordCount：{data['book']['expectedWordCount']}",
        f"- words.length：{len(records)}",
        f"- position 是否连续：{'是' if [r['position'] for r in records] == list(range(1, total + 1)) else '否'}",
        f"- id 是否唯一：{'是' if len({r['id'] for r in records}) == total else '否'}",
        f"- 每条是否仅含六个规定字段：{'是' if all(set(r) == {'id','position','word','phonetic','meaning','example'} for r in records) else '否'}",
        f"- 必填字符串是否为空：{'否' if all(all(isinstance(r[k], str) and r[k].strip() for k in ('id','word','phonetic','meaning','example')) for r in records) else '是'}",
        "",
        "## 来源分布",
        "",
    ]
    counts = Counter(item["section"] for item in words)
    for key, value in counts.items():
        report_lines.append(f"- {key}：{value}")
    report_lines.extend(["", "## 说明", "", "例句由程序根据词条和词性生成，建议在正式发布前抽样人工复核。"])
    (OUT_DIR / "数据校验报告.md").write_text("\n".join(report_lines) + "\n", encoding="utf-8", newline="\n")

    issue_lines = ["# 待人工确认问题", ""]
    if not issues and not duplicates:
        issue_lines.append("无")
    else:
        if duplicates:
            issue_lines.extend(["## 去重记录", ""])
            issue_lines.extend(f"- `{item['word']}`（来源形式：`{item['source']}`，分区：{item['section']}）" for item in duplicates)
            issue_lines.append("")
        if issues:
            issue_lines.extend(["## 自动提取或发音问题", ""])
            issue_lines.extend(f"- position {item['position']}：`{item['word']}` - {item['issue']}" for item in issues)
    (OUT_DIR / "待人工确认问题.md").write_text("\n".join(issue_lines) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
