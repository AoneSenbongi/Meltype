"""Authored held-out boundary ambiguity experiment; no user history or model training."""
import argparse, json, math, re, time, urllib.request
from pathlib import Path

# Each variant has its own reading boundaries and natural rendered text.
PAIRS = [
    ("ここではきものをぬぐ", [([3,5,2], "ここで履物を脱ぐ"), ([4,4,2], "ここでは着物を脱ぐ")],
     [["玄関で靴を脱いで入る。", "下駄箱に履物をしまう。"], ["更衣室で着物を着替える。", "和服を脱いで浴衣に着替える。"]],
     [["玄関に靴をそろえて入ってください。", "下駄箱は入口の隣にあります。", "土足禁止なのでスリッパを用意した。", "履いてきたブーツを置く場所だ。", "畳を汚さないため、足元のものを外す。"],
      ["更衣室で着物をハンガーに掛ける。", "着替える和服を持ってきました。", "浴衣から洋服に着替える場所です。", "帯をほどいて服を交換する。", "衣装替えのため舞台裏へ移動した。"]]),
    ("きょうはいしゃにいく", [([4,4,2], "今日は医者に行く"), ([3,5,2], "今日歯医者に行く")],
     [["風邪で熱が出たので病院へ行く。", "内科で咳の薬をもらう。"], ["虫歯が痛いので歯科へ行く。", "歯の詰め物を治療する。"]],
     [["風邪で熱が下がらない。", "内科で咳を診てもらう。", "発熱して体調が悪い。", "頭痛と吐き気が続いている。", "診察で血液検査を受けたい。"],
      ["虫歯を歯科で治療する。", "歯の詰め物が取れた。", "奥歯がずきずき痛む。", "歯茎が腫れて噛めなくなった。", "定期的な口腔清掃の予約がある。"]]),
    ("おしょくじけんがある", [([5,3,2], "お食事券がある"), ([4,4,2], "汚職事件がある")],
     [["レストランで食事券を使う。", "飲食店の割引券をもらった。"], ["政治家の汚職事件を捜査する。", "贈収賄で警察が動いた。"]],
     [["レストランでもらった食事券を探す。", "飲食店の割引券を財布に入れた。", "ランチの無料チケットを見つけた。", "ホテルで夕飯に使えるクーポンだ。", "店の支払いに使える金券がある。"],
      ["政治家の汚職を捜査している。", "贈収賄の容疑で警察が逮捕した。", "議員が業者から賄賂を受け取った。", "公金の不正について検察が調べる。", "役人と企業の癒着が発覚した。"]]),
    ("にわにはにわがある", [([3,4,2], "庭に埴輪がある"), ([4,3,2], "庭には庭がある")],
     [["庭に古墳の埴輪を飾る。", "土製の人形を屋外に展示する。"], ["庭の中に小さな庭を設けた。", "中庭の内側に別の庭がある。"]],
     [["古墳から出た埴輪を庭に展示する。", "土製の人形を家の外に飾った。", "考古学の展示品を屋外へ置いた。", "発掘した素焼きの像を並べる。", "歴史資料の人形を眺める。"],
      ["庭の中に別の庭を作った。", "中庭の内側に庭園を設けた。", "大きな庭園を小庭に分割する。", "入れ子になった緑地の設計だ。", "外側の庭からさらに内庭へ進む。"]]),
    ("だいぶつかった", [([3,4], "だいぶ使った"), ([4,3], "大仏買った")],
     [["お金をだいぶ使ってしまった。", "予算を消費して残りが少ない。"], ["寺に飾る大仏を買った。", "仏像を購入して運んだ。"]],
     [["お金を使いすぎて残りが少ない。", "予算を大量に消費した。", "ペンのインクが減ってきた。", "電池の残量がほとんどない。", "長年使い込んだ道具を片付ける。"],
      ["寺の大仏を買って運んだ。", "大きな仏像を購入した。", "青銅の如来像を入手した。", "巨大な釈迦の像を注文する。", "仏教美術の彫像を落札した。"]]),
    ("あくのじゅうじか", [([3,5], "悪の十字架"), ([3,4,1], "開くの十時か")],
     [["悪魔の十字架が物語に出てくる。", "呪われた宗教の象徴を描く。"], ["店が開く時間は十時だった。", "開店時刻を確認したい。"]],
     [["悪魔が持つ十字架を描いた。", "呪われた宗教の象徴が出てくる。", "邪悪な儀式に使われる印だ。", "恐怖映画に登場する不吉な道具。", "闇の力を象徴する装飾品。"],
      ["店が開く時間は十時だったかな。", "開店時刻を確認してから出かける。", "営業時間は午前十時からだそうだ。", "入口の鍵を開ける予定を聞く。", "施設のオープンは朝何時だろう。"]]),
]

# Additional explicitly annotated segment preferences. Cuts are the teacher's choices,
# not a claim that a sentence has only one linguistically valid segmentation.
EXTRA = [
 ("きせいちゅう",[( ["きせい","ちゅう"],"帰省中"),(["きせいちゅう"],"寄生虫")],
  [["実家に帰省して家族に会う。","正月休みに故郷へ帰った。"],["体内に寄生する虫を調べる。","寄生虫の検査を受ける。"]],
  [["実家に帰省する予定です。","正月休みは故郷で過ごす。","両親の家へ帰ってきた。","盆休みに田舎に戻っている。","家族と地元で連休を過ごす。"],
   ["体内に寄生する虫を検査する。","寄生虫の卵を顕微鏡で見る。","宿主から栄養を奪う生物だ。","消化管に住みつく線虫を調べる。","感染を防ぐため魚を加熱する。"]]),
 ("さいせいし",[(["さいせいし"],"再生紙"),(["さいせい","し"],"再生し")],
  [["古紙から作った紙を使う。","環境に配慮した印刷用紙だ。"],["音楽を再生して聴く。","録音した音声を流す。"]],
  [["古紙で作った紙を買う。","環境に配慮した印刷用紙を選ぶ。","回収した新聞を原料にした。","リサイクルされた素材でノートを作る。","資源を再利用した包装を使う。"],
   ["音楽を再生して聴いた。","録音した音声を流した。","動画のプレーヤーを操作する。","停止していた曲をもう一度かける。","保存した映像を画面に映す。"]]),
 ("しないで",[(["しない","で"],"市内で"),(["しないで"],"しないで")],
  [["市内の店舗を探す。","街の中心部で会う。"],["危険なのでその操作は禁止だ。","勝手に変更してはいけない。"]],
  [["市内の店舗を予約した。","街の中心部で待ち合わせる。","この自治体の区域で探す。","住んでいる町で買い物をする。","都市の中で活動する。"],
   ["危険な操作は禁止です。","勝手に変更してはいけません。","その作業はやめてください。","触ると壊れるので手を出さない。","実行を控えてほしい。"]]),
 ("あけまして",[(["あけまして"],"明けまして"),(["あけ","まして"],"開けまして")],
  [["新年の挨拶をする。","お正月のお祝いを伝える。"],["箱を開けて中身を見る。","封筒を開封した。"]],
  [["新年の挨拶を送りたい。","お正月のお祝いです。","年が変わったので祝辞を書く。","元旦に会って年始の言葉を伝える。","今年もよろしくと挨拶する。"],
   ["箱を開けて中身を出す。","封筒を開封して確認した。","蓋を外して容器の中を見た。","窓を開放して換気する。","入口の扉を押して入った。"]]),
 ("ちょうない",[(["ちょうない"],"町内"),(["ちょう","ない"],"腸内")],
  [["町内の住民が集まる。","自治会で清掃をする。"],["腸の中の細菌を調べる。","消化管の環境を整える。"]],
  [["町内の住民が集まりました。","自治会で清掃をします。","近隣の家庭に回覧板を配る。","地域の祭りに参加する。","この地区の道路を掃除する。"],
   ["腸の中の細菌を検査した。","消化管の環境を改善する。","乳酸菌やビフィズス菌を調べる。","お腹の微生物の働きを研究する。","善玉菌を増やす食事を考える。"]]),
 ("こうせいぶっしつ",[(["こうせい","ぶっしつ"],"構成物質"),(["こうせいぶっしつ"],"抗生物質")],
  [["素材を構成する成分を分析する。","材料に含まれる物質を測る。"],["細菌感染に効く薬を処方する。","医師が抗菌薬を出した。"]],
  [["素材を構成する成分を分析した。","材料に含まれる物質を調べる。","製品の元素の比率を測る。","合金の原料を確認する。","部品を作る化学成分を比較する。"],
   ["細菌感染に効く薬を処方された。","医師から抗菌薬をもらう。","肺炎の治療で薬を飲む。","耐性菌に注意して投薬する。","病原菌の増殖を抑える薬剤だ。"]])
]
for reading,variants,training,tests in EXTRA:
    PAIRS.append((reading,[(list(map(len,chunks)),text) for chunks,text in variants],training,tests))

def variations(context):
    filler="記録を整理して次の内容を確認した。" * 10
    return [
      ("plain_left",context,""),
      ("polite_left","状況を説明します。"+context,""),
      ("question_left",context+"この状況ではどう表記するだろう。",""),
      ("right_only","",context),
      ("right_polite","","補足すると、"+context),
      ("near_left",filler+context,""),
      ("far_left",context+filler,""),
      ("far_right","",filler+context),
      ("literal_neighbor","GitHub: "+context," API v1.5"),
      ("unrelated_neighbor","天気と交通情報を読んだ。"+context,"資料の編集を続ける。"),
    ]

def features(s):
    # Fixed before evaluation: character bigrams plus individual kanji, no hand-written topic rules.
    return set(s[i:i+2] for i in range(len(s)-1)) | set(c for c in s if '\u4e00' <= c <= '\u9fff')

def similarity(a,b):
    a,b=features(a),features(b)
    return len(a & b)/math.sqrt(len(a)*len(b)) if a and b else 0.0

def select_context(training, context):
    scores=[max(similarity(t,context) for t in variants) for variants in training]
    ranked=sorted(range(len(scores)),key=lambda i:scores[i],reverse=True)
    return ranked[0] if scores[ranked[0]] >= .45 and scores[ranked[0]]-scores[ranked[1]] >= .12 else None

def adversarial(context, opposite):
    # Teacher's intended current topic is explicit. These remain authored tests.
    return [
      ('topic_switch', '前の話題は「'+opposite+'」。ここからは別の話です。'+context, ''),
      ('quoted_other', '資料には「'+opposite+'」とあるが、今書いているのは次の内容。'+context, ''),
      ('deny_other', '「'+opposite+'」という意味ではありません。'+context, ''),
      ('right_current', '前の話題は「'+opposite+'」。', '今回の話題はこちら。'+context),
      ('left_current', '今回の話題はこちら。'+context, '追記：以前の別の話題は「'+opposite+'」だった。'),
      ('no_context', '', ''),
    ]

def main():
    p=argparse.ArgumentParser();p.add_argument('--endpoint',required=True);p.add_argument('--output',required=True);p.add_argument('--expanded',action='store_true');p.add_argument('--adversarial',action='store_true');args=p.parse_args()
    out=Path(args.output);out.mkdir(parents=True,exist_ok=True)
    conditions=6 if args.adversarial else 10 if args.expanded else 1
    total=sum(sum(len(c) for c in pair[3]) for pair in PAIRS)*conditions
    rows=[];started=time.time()
    for pair,(reading,variants,training,tests) in enumerate(PAIRS):
        for lengths,_ in variants:
            assert sum(lengths)==len(reading),(reading,lengths,len(reading))
        candidates=[v[1] for v in variants]
        for expected,contexts in enumerate(tests):
            for n,context in enumerate(contexts):
              for condition,left,right in adversarial(context,tests[1-expected][n]) if args.adversarial else variations(context) if args.expanded else [('plain_left',context,'')]:
                # Apply the same finite context window as the product.
                left=left[-256:];right=right[:128]
                local=select_context(training,left+right)
                outputs=[];latencies=[];error=None
                for choices in (candidates,candidates[::-1]):
                    body={"prompt":("\uee02"+left if left else '')+("\uee07"+right if right else '')+"\uee00"+''.join(chr(ord(c)+0x60) if 'ぁ'<=c<='ゖ' else c for c in reading)+"\uee01", "grammar":"root ::= "+" | ".join(json.dumps(c,ensure_ascii=False) for c in choices),"n_predict":128,"temperature":0,"seed":0,"cache_prompt":True,"stop":["\uee08","\uee00","\uee01","\uee02","\uee07"]}
                    try:
                        t=time.time();req=urllib.request.Request(args.endpoint.rstrip('/')+'/completion',json.dumps(body).encode(),{'Content-Type':'application/json'})
                        with urllib.request.urlopen(req,timeout=5) as r: value=json.load(r)['content']
                        outputs.append(candidates.index(value) if value in candidates else None);latencies.append((time.time()-t)*1000)
                    except Exception as e: outputs.append(None);error=type(e).__name__
                rows.append(dict(pair=pair,reading=reading,left=left,right=right,condition=condition,expected=expected,local=local,model=outputs,latencyMs=latencies,error=error))
                print(f'{len(rows)}/{total}',flush=True)
                with (out/'samples.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(rows[-1],ensure_ascii=False)+'\n')
                try:
                    temp=out/'status.tmp';temp.write_text(json.dumps(dict(status='running',processed=len(rows),total=total)),encoding='utf-8');temp.replace(out/'status.json')
                except OSError:pass
    summary=dict(cases=len(rows),meaningPairs=len(PAIRS),trainingExamples=sum(sum(len(x) for x in p[2]) for p in PAIRS),baselineFirst=sum(r['expected']==0 for r in rows),globalLast=sum(r['expected']==1 for r in rows),contextCorrect=sum((r['local'] if r['local'] is not None else 0)==r['expected'] for r in rows),contextUses=sum(r['local'] is not None for r in rows),contextWrongUses=sum(r['local'] is not None and r['local']!=r['expected'] for r in rows),modelCorrect=sum(r['model'][0]==r['expected'] for r in rows),modelReversedCorrect=sum(r['model'][1]==r['expected'] for r in rows),modelOrderChanges=sum(r['model'][0]!=r['model'][1] for r in rows),errors=sum(r['error'] is not None for r in rows),seconds=time.time()-started,limitations='Authored ambiguity examples with closed natural-text candidates; baselineFirst/globalLast are simulated policies, not measured Google accuracy. This does not prove same-surface boundary selection or daily accuracy.')
    summary['hybridCorrect']=sum((r['local'] if r['local'] is not None else r['model'][0])==r['expected'] for r in rows)
    summary['contextConditions']=conditions
    summary['uniqueMeaningContexts']=sum(sum(len(c) for c in p[3]) for p in PAIRS)
    summary['byCondition']={c:dict(cases=len(a),contextCorrect=sum((r['local'] if r['local'] is not None else 0)==r['expected'] for r in a),modelCorrect=sum(r['model'][0]==r['expected'] for r in a),hybridCorrect=sum((r['local'] if r['local'] is not None else r['model'][0])==r['expected'] for r in a)) for c in sorted(set(r['condition'] for r in rows)) for a in [[r for r in rows if r['condition']==c]]}
    (out/'cases.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8');(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    terminal=json.dumps(dict(status='completed',processed=len(rows),total=len(rows)))
    (out/'terminal.json').write_text(terminal,encoding='utf-8')
    try:
        temp=out/'status.tmp';temp.write_text(terminal,encoding='utf-8');temp.replace(out/'status.json')
    except OSError:pass
    print(json.dumps(summary,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
