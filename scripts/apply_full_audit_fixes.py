#!/usr/bin/env python3
"""Apply the 300 targeted fixes from kaoyan_full_audit.json.

The mapping is intentionally explicit and position-based.  The script refuses
to run unless every audit item still matches the source word and meaning, and
it verifies that no per-word field other than ``meaning`` changes.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "蒸馏" / "output" / "kaoyan_final.json"
DEFAULT_AUDIT = Path("E:/Google下载/kaoyan_full_audit.json")
DEFAULT_OUTPUT = ROOT / "蒸馏" / "output" / "kaoyan_final_fixed.json"
DEFAULT_REPORT = ROOT / "蒸馏" / "output" / "kaoyan_full_audit_fix_report.md"
DEFAULT_RESULTS = ROOT / "蒸馏" / "output" / "kaoyan_full_audit_fix_results.json"


# position<TAB>word<TAB>new meaning
# Keep this table explicit: each audit row has one independently reviewable fix.
FIX_TSV = """\
15\tobvious\tadj. 明显的；显而易见的；平淡无奇的
62\tscenery\tn. 风景；景色；舞台布景
125\tfavourable\tadj. 有利的；赞许的；令人满意的
209\tfinancial\tadj. 财政的；金融的
213\tfirst\tadj. 第一的；首要的；adv. 首先；最初；n. 第一次；第一名
274\tgeneral\tadj. 一般的；普遍的；总的；n. 将军
275\tgeneralize\tv. 概括；归纳；推广；使一般化
315\tleadership\tn. 领导；领导地位；领导能力；领导人员
411\tscope\tn. 范围；机会；余地
427\turban\tadj. 城市的；都市的
441\ttake\tv. 拿；带领；吃；接受；花费；捕获；n. 一次拍摄；看法；收入
595\tbias\tn. 偏见；偏重；v. 使有偏见；使偏心
616\temerge\tv. 出现；浮现；显露；摆脱出来
650\timmune\tadj. 免疫的；免除的；不受影响的
664\tborn\tadj. 出生的；天生的；生来的
674\tacute\tadj. 敏锐的；剧烈的；严重的；急性的
684\tfollow\tv. 跟随；接着；遵循；领会；结果是
685\tfollowing\tadj. 接着的；下列的；n. 追随者；拥护者
711\tliterature\tn. 文学；文学作品；文献
802\tsociety\tn. 社会；社团；协会；学会
814\tsound\tadj. 健康的；健全的；可靠的；明智的；n. 声音；v. 发声；听起来
915\timportant\tadj. 重要的；重大的；有地位的
939\treason\tn. 原因；理由；理性；v. 推理；思考
945\tset\tv. 放置；设置；确定；使处于；n. 一套；一组；adj. 固定的；规定的
953\tshare\tn. 份额；股份；一份；v. 分享；分担；共有
996\tsense\tn. 感觉；意识；意义；理智；v. 感觉到
1006\ttogether\tadv. 一起；共同；同时；连续地
1036\thonourable\tadj. 可敬的；光荣的；正直的；体面的
1048\tneglect\tv. 忽视；疏忽；漏做；n. 忽略；疏忽
1068\treligious\tadj. 宗教的；信教的；虔诚的
1073\tstrategy\tn. 战略；策略；行动计划
1079\ttransform\tv. 使变形；使改观；转变
1094\tvisual\tadj. 视觉的；视力的；可见的
1102\tconservative\tadj. 保守的；守旧的；n. 保守者
1105\tconsiderate\tadj. 考虑周到的；体谅的
1113\tconfine\tv. 限制；使局限；幽禁；禁闭
1114\tconfirm\tv. 证实；确认；批准；巩固
1121\ttrain\tn. 火车；列车；一系列；v. 训练；培养
1266\tconform\tv. 遵守；符合；顺应；使一致
1267\tconfront\tv. 使面临；使遭遇；勇敢面对
1270\tcongress\tn. 代表大会；国会；议会
1275\tcontinue\tv. 继续；持续；延续；重新开始
1293\tmodern\tadj. 现代的；近代的；新式的；n. 现代人
1310\treform\tn./v. 改革；改造；改进
1323\tstandpoint\tn. 立场；观点
1343\tanticipate\tv. 预期；预料；期望；预先考虑
1358\tcondemn\tv. 谴责；宣判有罪；判刑
1359\tcondense\tv. 压缩；凝结；使简洁
1376\tnarrative\tn. 叙述；故事；adj. 叙事的
1380\tnational\tadj. 国家的；全国的；民族的；n. 国民
1514\tstable\tadj. 稳定的；安定的；沉稳的；可靠的
1537\tcritical\tadj. 批评的；关键的；危急的；临界的
1547\tdue\tadj. 到期的；预定的；应得的；由于
1582\tsuppose\tv. 猜想；假定；认为；期望
1585\tsupreme\tadj. 最高的；至高无上的；最大的
1591\tresearch\tn./v. 研究；调查
1619\tconvene\tv. 召集；召开；集合
1621\tconverge\tv. 汇合；集中；趋同
1622\tconvey\tv. 运送；输送；表达；传达
1644\texpand\tv. 扩大；扩展；膨胀；详述
1655\tinstitution\tn. 机构；制度；创立；习俗
1659\tintegrate\tv. 使结合；使一体化；融入
1682\tpurchase\tn./v. 购买；购置；购买物
1693\trisk\tn. 风险；危险；v. 冒险；使遭受危险
1800\tprotocol\tn. 礼仪；外交礼节；协议；规程
1811\tattention\tn. 注意；注意力；关心；立正
1812\tattitude\tn. 态度；看法；姿势
1829\textension\tn. 延长；扩大；扩建部分；分机
1832\thuman\tadj. 人的；人类的；有人性的；n. 人
1845\tinternational\tadj. 国际的；世界性的；n. 国际比赛；国际组织
1847\tlose\tv. 丢失；失去；输掉；迷失；亏损
1872\tmarble\tn. 大理石；大理石制品；玻璃弹子
1876\tmarried\tadj. 已婚的；婚姻的
1879\tMarxist\tadj. 马克思主义的；n. 马克思主义者
1889\tneighbourhood\tn. 四邻；街坊；街区；附近地区
1915\ttheatre\tn. 剧院；戏剧；手术室；战区
1924\tvia\tprep. 经由；通过；凭借
1992\tfee\tn. 费用；酬金；服务费
1996\tgrin\tn./v. 咧嘴笑；露齿而笑
2010\talloy\tn. 合金；v. 使成合金；使降低价值
2011\talone\tadj. 单独的；独自的；adv. 单独；仅仅
2040\tmay\tmodal v. 可能；可以；也许；祝愿
2056\tplay\tv. 玩；演奏；扮演；比赛；n. 游戏；戏剧；比赛
2083\tchairman\tn. 主席；委员长；董事长
2135\tpetty\tadj. 琐碎的；次要的；小气的；狭隘的
2213\tnominate\tv. 提名；推荐；任命；指定
2226\trehearse\tv. 排练；排演；详述；默诵
2234\tsingle\tadj. 单一的；单个的；单身的；n. 单程票；单曲；单人间
2252\tjuvenile\tadj. 青少年的；幼稚的；n. 青少年；少年读物
2281\tclip\tn. 夹子；剪下物；短片；v. 剪；修剪；夹住
2308\tmedicine\tn. 药；药物；医学；医术
2312\tmelt\tv. 熔化；融化；逐渐消失；n. 熔化物
2323\tfilm\tn. 电影；胶片；薄膜；v. 拍摄；覆盖薄层
2355\tsilly\tadj. 愚蠢的；糊涂的；不明事理的
2409\tdepth\tn. 深度；深处；深刻；浓度
2451\tacid\tn. 酸；adj. 酸的；酸性的；尖刻的
2489\tfaith\tn. 信任；信念；信仰；忠诚
2509\tpath\tn. 小路；路线；途径；轨道
2541\tcenter\tn. 中心；中央；v. 集中；以……为中心
2543\tcentury\tn. 世纪；一百年
2545\tcentimetre\tn. 厘米；公分
2546\tcereal\tn. 谷物；谷类食品；adj. 谷类的
2547\tdebt\tn. 债；债务；欠款；人情债
2566\tgiggle\tn./v. 咯咯笑；傻笑
2575\thasty\tadj. 匆忙的；仓促的；草率的
2607\tundo\tv. 松开；解开；取消；撤销
2623\theroin\tn. 海洛因
2660\tseal\tn. 封条；印章；海豹；v. 密封；盖章
2664\tsecretary\tn. 秘书；书记；部长；大臣
2666\tsector\tn. 部门；行业；区域；扇形
2689\tpermanent\tadj. 永久的；持久的；固定的
2744\twarn\tv. 警告；告诫；提醒
2748\taffluent\tadj. 富裕的；丰富的；n. 支流
2763\tlight\tn. 光；灯；adj. 轻的；浅色的；v. 点燃；照亮
2770\tbad\tadj. 坏的；糟糕的；有害的；严重的
2849\tlabour\tn. 劳动；劳工；分娩；v. 劳动；努力
2851\tlack\tn./v. 缺乏；不足
2855\tmachine\tn. 机器；机械；机构
2872\tpack\tn. 包；包裹；一群；一副；v. 打包；挤满
2900\tsacred\tadj. 神圣的；宗教的；不可侵犯的
2905\tsandwich\tn. 三明治；v. 把……夹在中间；挤入
2906\tsane\tadj. 心智健全的；理智的；明智的
2918\tvalve\tn. 阀；电子管；心脏瓣膜
2922\twaken\tv. 醒来；唤醒；使觉醒；激发
2968\ttailor\tn. 裁缝；v. 缝制；使适合特定需要
2979\ttax\tn. 税；负担；v. 征税；使负重
2985\tvanity\tn. 虚荣；虚荣心；自负；空虚
3052\tlife\tn. 生命；生活；生涯；寿命；生物
3074\torient\tn. 东方；东方国家；v. 确定方向；使适应
3079\tpopular\tadj. 流行的；受欢迎的；大众的；通俗的
3089\tpostman\tn. 邮递员；邮差
3099\trepeat\tv. 重复；重说；重做；n. 重复；重播
3105\ttiresome\tadj. 令人厌倦的；烦人的
3114\thormone\tn. 激素；荷尔蒙
3134\tmissile\tn. 导弹；投射物；发射物
3138\tnuclear\tadj. 核的；核能的；原子核的；核心的
3158\ttraffic\tn. 交通；运输；交易；v. 做非法交易
3219\tbiography\tn. 传记；传记文学
3234\tcombination\tn. 结合；联合；组合；联合体
3237\tentire\tadj. 全部的；整个的；完全的
3247\twhereby\tadv. 凭此；借以；由此
3316\tdiscern\tv. 看出；觉察；识别；区别
3346\tcome\tv. 来；来到；出现；发生；成为
3359\tdialect\tn. 方言；地方话
3418\tspacecraft\tn. 航天器；宇宙飞船
3430\twet\tadj. 湿的；下雨的；n. 潮湿；v. 弄湿
3441\tannounce\tv. 宣布；宣告；通知；声称
3453\tclothes\tn. 衣服；服装
3462\tdespair\tn./v. 绝望；失去希望
3472\tenquire\tv. 询问；打听；调查
3477\tfine\tadj. 优良的；精细的；晴朗的；n. 罚款；v. 罚款
3497\tpole\tn. 杆；柱；地极；电极
3561\tdirector\tn. 主管；董事；导演；负责人
3573\tinstall\tv. 安装；设置；使就职；安顿
3592\tminister\tn. 部长；大臣；牧师；外交使节
3626\texcuse\tn. 借口；理由；v. 原谅；为……辩解
3628\texercise\tn. 练习；运动；锻炼；v. 练习；锻炼；行使
3657\tinvaluable\tadj. 非常宝贵的；无价的
3671\tmotive\tn. 动机；目的；adj. 运动的；发动的
3674\tmourn\tv. 哀悼；悲悼；对……感到痛心
3767\tstream\tn. 小河；流；潮流；v. 流动；涌出
3789\tbribe\tn. 贿赂；v. 向……行贿；收买
3790\tbridge\tn. 桥；桥梁；v. 架桥；弥合
3801\tdown\tadv. 向下；在下面；adj. 向下的；沮丧的；prep. 沿着
3812\texhibit\tv. 展出；陈列；显示；n. 展览品；证物
3833\tboss\tn. 老板；上司；工头；v. 指挥；支配
3841\tartifact\tn. 人工制品；手工艺品；人为现象
3844\tartistic\tadj. 艺术的；有艺术天赋的；精美的
3845\tdisrupt\tv. 扰乱；破坏；使中断
3855\teven\tadj. 平坦的；均匀的；偶数的；adv. 甚至；更加
3859\tfor\tprep. 为了；给；对于；达；因为；conj. 因为
3862\tforeign\tadj. 外国的；对外的；陌生的；异质的
3886\trid\tv. 使摆脱；清除；除去
3903\ttranscend\tv. 超越；胜过；超出
3915\tcontrive\tv. 设计；想出；谋划；设法做到
3917\tconvenient\tadj. 便利的；方便的；合适的
3922\tconvict\tv. 宣判有罪；证明有罪；n. 已决犯；囚犯
3924\tconvince\tv. 使信服；使确信；说服
4009\tcontain\tv. 包含；容纳；控制；抑制
4010\tcontaminate\tv. 污染；玷污；毒害
4014\tburst\tv. 爆裂；突然闯入；迸发；n. 爆裂；突发
4032\tfriendly\tadj. 友好的；友善的；有利的
4046\thumiliate\tv. 羞辱；使丢脸
4047\thumour\tn. 幽默；诙谐；心情；v. 迁就；迎合
4090\tsummit\tn. 顶峰；最高点；峰会
4091\tsummon\tv. 召见；召集；传唤；鼓起
4099\taudience\tn. 听众；观众；读者；正式会见
4103\taugment\tv. 增加；扩大；提高
4136\tdrum\tn. 鼓；鼓状物；v. 打鼓；反复灌输
4168\tstubborn\tadj. 顽固的；倔强的；顽强的；难对付的
4189\tavenue\tn. 林荫大道；大街；途径；手段
4293\tsympathize\tv. 同情；赞同；支持
4295\tsymphony\tn. 交响乐；交响曲；和谐
4304\tmurder\tn. 谋杀；凶杀；v. 谋杀；糟蹋
4315\tpump\tn. 泵；抽水机；v. 用泵抽送；盘问
4320\tpure\tadj. 纯的；纯净的；纯粹的；清白的
4366\tagain\tadv. 再；又；重新；另一方面
4371\tair\tn. 空气；天空；神态；v. 晾晒；播出；表达
4372\talbeit\tconj. 虽然；尽管
4380\talways\tadv. 总是；一直；永远
4391\task\tv. 问；询问；请求；邀请；要价
4392\tat\tprep. 在；向；以；处于；因为
4425\tbig\tadj. 大的；重大的；年长的；成功的
4429\tborrow\tv. 借；借用；借入；采用
4433\tboy\tn. 男孩；少年；儿子
4435\tbreakfast\tn. 早餐；早饭；v. 吃早餐
4457\tbuy\tv. 买；购买；收买；n. 购买；便宜货
4485\tcheap\tadj. 便宜的；低劣的；卑劣的；adv. 便宜地
4497\tchina\tn. 瓷器；瓷料；陶瓷餐具
4503\tchurch\tn. 教堂；礼拜；教会
4506\tcinema\tn. 电影院；电影；电影业
4508\tcity\tn. 城市；都市；全市居民
4512\tclean\tadj. 清洁的；洁白的；v. 打扫；使干净；adv. 完全地
4554\tdeath\tn. 死；死亡；毁灭
4556\tdeep\tadj. 深的；深刻的；低沉的；adv. 深深地；n. 深处
4562\tdifferent\tadj. 不同的；有差异的；各种的
4563\tdifficult\tadj. 困难的；难做的；难相处的
4568\tdirt\tn. 污物；污垢；泥土；下流话
4596\tenemy\tn. 敌人；敌军；危害物
4598\tenough\tadj./pron. 足够的；adv. 足够地；相当地
4601\texam/examination\tn. 考试；检查；审查
4623\tfound\tv. 建立；创办；创立
4628\tfull\tadj. 满的；充满的；完整的；吃饱的
4648\tgulf\tn. 海湾；鸿沟；分歧；深渊
4660\thide\tv. 隐藏；隐瞒；躲藏；n. 兽皮
4668\thospital\tn. 医院
4669\thot\tadj. 热的；辣的；激烈的；热门的
4673\thurry\tn./v. 匆忙；赶紧；催促
4674\thurt\tv. 使受伤；伤害；疼痛；n. 伤害；痛苦；adj. 受伤的
4685\tinstead\tadv. 代替；反而；却
4725\tluggage\tn. 行李
4751\tnoisy\tadj. 吵闹的；喧闹的
4801\tplane\tn. 飞机；平面；水平；刨子；v. 刨平；滑翔
4803\tpleasant\tadj. 令人愉快的；舒适的；和蔼的
4805\tpoem\tn. 诗；韵文
4808\tpopulation\tn. 人口；全体居民；种群
4815\tpresident\tn. 总统；主席；校长；总裁
4817\tprice\tn. 价格；代价；v. 给……定价
4821\tprison\tn. 监狱；牢狱；禁锢
4823\tprofessor\tn. 教授；教师
4840\treal\tadj. 真实的；实际的；真正的；adv. 很；非常
4848\tring\tn. 戒指；环；铃声；v. 按铃；鸣响；打电话
4856\tseldom\tadv. 很少；不常
4860\tshort\tadj. 短的；矮的；不足的；adv. 短暂地；突然地
4866\tslow\tadj. 慢的；迟缓的；adv. 缓慢地；v. 减速
4874\tsoldier\tn. 士兵；军人
4875\tsolitary\tadj. 单独的；孤独的；n. 独居者
4876\tsoon\tadv. 不久；很快；早
4879\tsoutheast\tn. 东南；adj. 东南的；adv. 向东南
4955\tvolt\tn. 伏特
4960\twedding\tn. 婚礼；结婚庆典；adj. 婚礼的
4961\twest\tn. 西；西方；adj. 西方的；adv. 向西
4967\twhite\tadj. 白色的；白皙的；n. 白色；白色物
4987\tadorn\tv. 装饰；使生色
5032\tavalanche\tn. 雪崩；山崩；大量涌入；v. 雪崩般涌来
5044\tbiological\tadj. 生物的；生物学的；亲生的
5138\tcultural\tadj. 文化的；文明的；教养的
5151\tdecoration\tn. 装饰；装饰品；勋章
5190\teconomist\tn. 经济学家
5293\tidealize/idealise\tv. 把……视为理想；使理想化
5298\timpend\tv. 即将发生；逼近
5308\tinborn\tadj. 天生的；天赋的
5310\tinclement\tadj. 恶劣的；严酷的
5327\tinfirm\tadj. 虚弱的；不坚定的；不稳固的
5332\tinfuse\tv. 注入；灌输；泡制
5366\tinvalidate\tv. 证明错误；使无效；使作废
5379\tjudiciary\tn. 司法机关；司法系统；全体法官
5387\tlandmark\tn. 地标；路标；里程碑
5447\tminimal\tadj. 极小的；极少的；最低限度的
5499\tobscene\tadj. 淫秽的；猥亵的；下流的；骇人听闻的
5501\tobserver\tn. 观察者；观测者；观察员
5551\tpeacock\tn. 孔雀；爱炫耀的人；v. 炫耀
5561\tpersistence\tn. 坚持；锲而不舍；持续存在
5579\tpolymer\tn. 聚合物；聚合体
5595\tprimarily\tadv. 主要地；根本地
5604\tprojection\tn. 预测；推断；投射；放映；投影
5612\tpsychologist\tn. 心理学家
5644\treplicate\tv. 复制；重做；复现；再生
5645\tretrofit\tn./v. 式样翻新；更新；改进
5648\trichness\tn. 丰富；富饶；浓烈
5653\trotunda\tn. 圆形大厅；有圆顶的圆形建筑
5655\trut\tn. 车辙；槽；凹痕；常规；老规矩
5657\tsavanna/savannah\tn. 稀树草原
5663\tsea-pink\tn. 海石竹
5667\tself-help\tadj. 自助的；自救的；n. 自助；自救
5668\tsensational\tadj. 引起轰动的；哗众取宠的；极好的
5672\tsermon\tn. 布道；说教；冗长的训话
5680\tskint\tadj. 身无分文的；穷困的
5707\tstanding\tn. 地位；名望；资格；adj. 长期的；常设的；直立的
5708\tsteadfast\tadj. 坚定的；不动摇的
5719\tstuck\tadj. 卡住的；动弹不得的；陷入困境的；stick 的过去式和过去分词
5779\tunaffordable\tadj. 买不起的；负担不起的
5780\tunattractive\tadj. 不悦目的；不漂亮的；无趣的；令人反感的
5782\tunbiased\tadj. 公正的；不偏不倚的；无偏见的
5784\tuncertain\tadj. 不确定的；无把握的；多变的
5785\tuncharted\tadj. 地图上未标明的；人迹罕至的；陌生的
5797\tunfocused\tadj. 漫不经心的；目的不明确的；松散的
5801\tunintentional\tadj. 无意的；非故意的；偶然的
5806\tunleash\tv. 发泄；释放；使爆发
5827\tvault\tn. 拱顶；地下室；撑竿跳；v. 跳跃；撑竿跳过；使成穹状
"""


def parse_fixes() -> dict[int, tuple[str, str]]:
    fixes: dict[int, tuple[str, str]] = {}
    for line_no, raw in enumerate(FIX_TSV.splitlines(), 1):
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) != 3:
            raise ValueError(f"Bad FIX_TSV line {line_no}: {raw!r}")
        position = int(parts[0])
        if position in fixes:
            raise ValueError(f"Duplicate fix position: {position}")
        fixes[position] = (parts[1], parts[2])
    return fixes


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_integrity(before: dict[str, Any], after: dict[str, Any], changed: set[int]) -> None:
    before_words = before["words"]
    after_words = after["words"]
    if len(before_words) != 5847 or len(after_words) != 5847:
        raise ValueError("Word count must remain 5847")
    if before.get("book") != after.get("book") or before.get("schemaVersion") != after.get("schemaVersion"):
        raise ValueError("Top-level metadata changed")

    positions = [row["position"] for row in after_words]
    if len(set(positions)) != 5847 or sorted(positions) != list(range(1, 5848)):
        raise ValueError("Positions are not unique and continuous from 1 to 5847")
    ids = [row["id"] for row in after_words]
    if len(set(ids)) != 5847:
        raise ValueError("Word ids are not unique")

    actual_changed: set[int] = set()
    for old, new in zip(before_words, after_words, strict=True):
        if not new.get("word") or not new.get("meaning"):
            raise ValueError(f"Empty word or meaning at position {new.get('position')}")
        if old["position"] != new["position"]:
            raise ValueError("Word order or position changed")
        differing = {key for key in old.keys() | new.keys() if old.get(key) != new.get(key)}
        if differing:
            actual_changed.add(new["position"])
            if differing != {"meaning"}:
                raise ValueError(
                    f"Unexpected field change at {new['position']} {new['word']}: {sorted(differing)}"
                )
    if actual_changed != changed:
        raise ValueError(
            f"Changed-position mismatch: expected {len(changed)}, actual {len(actual_changed)}"
        )


def markdown_cell(text: str) -> str:
    return str(text).replace("|", "\\|").replace("\n", " ")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--audit", type=Path, default=DEFAULT_AUDIT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--results", type=Path, default=DEFAULT_RESULTS)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    fixes = parse_fixes()
    if len(fixes) != 300:
        raise ValueError(f"Expected 300 explicit fixes, got {len(fixes)}")

    source = read_json(args.input)
    audit = read_json(args.audit)
    issues = audit.get("issues", [])
    if len(issues) != 300 or audit.get("flaggedTotal") != 300:
        raise ValueError("Audit must contain exactly 300 flagged issues")

    source_by_position = {row["position"]: row for row in source["words"]}
    audit_by_position = {row["position"]: row for row in issues}
    if set(fixes) != set(audit_by_position):
        raise ValueError("Explicit fix positions do not exactly match audit positions")

    for position, (expected_word, _) in fixes.items():
        current = source_by_position.get(position)
        issue = audit_by_position[position]
        if current is None:
            raise ValueError(f"Missing source position {position}")
        if current["word"] != expected_word or issue["word"] != expected_word:
            raise ValueError(f"Word mismatch at position {position}")
        if current["meaning"] != issue["currentMeaning"]:
            raise ValueError(f"Current meaning no longer matches audit at {position} {expected_word}")

    output = copy.deepcopy(source)
    output_by_position = {row["position"]: row for row in output["words"]}
    results: list[dict[str, Any]] = []
    for issue in issues:
        position = issue["position"]
        word, new_meaning = fixes[position]
        old_meaning = output_by_position[position]["meaning"]
        output_by_position[position]["meaning"] = new_meaning
        results.append(
            {
                "position": position,
                "word": word,
                "category": issue["category"],
                "oldMeaning": old_meaning,
                "newMeaning": new_meaning,
                "status": "fixed",
            }
        )

    validate_integrity(source, output, set(fixes))
    write_json(args.output, output)
    # Reparse the exact bytes written to catch serialization failures.
    reparsed = read_json(args.output)
    validate_integrity(source, reparsed, set(fixes))
    write_json(args.results, results)

    counts = Counter(row["category"] for row in results)
    lines = [
        "# 考研词库 300 条定点修复报告",
        "",
        f"- 输入文件：`{args.input.name}`",
        f"- 审计清单：`{args.audit.name}`",
        f"- 总词数：{len(output['words'])}",
        f"- 清单问题数：{len(issues)}",
        f"- 实际修改数：{len(results)}",
        f"- 未处理数：0",
        f"- 释义不完整/部分污染：{counts['释义不完整/部分污染']}",
        f"- 词性标注错误：{counts['词性标注错误']}",
        f"- 确定错配/严重污染：{counts['确定错配/严重污染']}",
        f"- 输出 SHA-256：`{sha256(args.output)}`",
        "",
        "## 完整性校验",
        "",
        "- JSON 可正常解析：通过",
        "- 单词总数为 5847：通过",
        "- position 唯一且连续：通过",
        "- id 唯一：通过",
        "- word、meaning 均非空：通过",
        "- book 元数据及 schemaVersion 未修改：通过",
        "- 除 meaning 外所有单词字段均未修改：通过",
        "- 300 个审计 position/word/currentMeaning 与输入精确匹配：通过",
        "",
        "## 逐条修改",
        "",
        "| position | word | 类别 | 原释义 | 新释义 |",
        "|---:|---|---|---|---|",
    ]
    for row in results:
        lines.append(
            f"| {row['position']} | `{markdown_cell(row['word'])}` | "
            f"{markdown_cell(row['category'])} | {markdown_cell(row['oldMeaning'])} | "
            f"{markdown_cell(row['newMeaning'])} |"
        )
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"fixed={len(results)}")
    print(f"output={args.output}")
    print(f"report={args.report}")
    print(f"results={args.results}")
    print(f"sha256={sha256(args.output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
