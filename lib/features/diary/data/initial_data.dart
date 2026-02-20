List<Map<String, dynamic>> initialDiaries = [
  {
    'content':
        '今天終於把項目的架子搭起來了！雖然只是個開始，但看著空白的畫布被一點點填滿，心裡充滿了成就感。\n\n特別是設計圖示的時候，想了好久，最後決定用小白狐作為我們的吉祥物。它象徵著靈動和守護，就像我希望「白守」能帶給每一個用戶的感覺一樣。\n\n加油！一定要把這個 App 做到最好！',
    'date': DateTime.now().subtract(const Duration(days: 0)).toIso8601String(),
    'tags': ['開發日誌', '心情', '新開始'],
  },
  {
    'content':
        '今天除錯了一個超級頑固的 Bug，明明邏輯都對，就是跑不通。最後發現居然是一個該死的拼寫錯誤！氣死我了！😤\n\n不過解決掉的那一瞬間，所有的鬱悶都煙消雲散了。這就是編程的魅力吧，痛並快樂著。',
    'date': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
    'tags': ['Bug修復', '痛苦', '快樂'],
  },
  {
    'content':
        '下雨了。🌧️\n\n喜歡雨天，聽著雨聲敲打窗戶的聲音，感覺世界都安靜下來了。泡了一杯熱咖啡，一邊喝一邊寫程式碼，感覺效率特別高。\n\n要是能一直這樣安靜下去就好了。',
    'date': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
    'tags': ['雨天', '咖啡', '平靜'],
  },
  {
    'content':
        '今天去試了那家新開的拉麵店。🍜\n\n湯頭很濃郁，麵條也很勁道，但是... 只有三片肉！三片！老闆你也太摳了吧！\n\n下次不去了，哼。',
    'date': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
    'tags': ['美食', '吐槽', '拉麵'],
  },
  {
    'content':
        '突然想到了一個絕妙的點子！✨\n\n如果在日記列表裡加入時間軸的設計，會不會更有代入感？就像是在回溯自己的人生軌跡一樣。\n\n趕緊記下來，明天去試試看！',
    'date': DateTime.now().subtract(const Duration(days: 4)).toIso8601String(),
    'tags': ['靈感', '功能設計', '興奮'],
  },
  {
    'content': '今天好累啊... 感覺身體被掏空。😵\n\n連續加班了好幾天，腦子都有點轉不動了。今晚早點睡吧，狗命要緊。',
    'date': DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
    'tags': ['加班', '疲憊', '休息'],
  },
  {
    'content':
        '在路上看到了一隻流浪貓，橘色的，胖胖的。🐱\n\n它一點都不怕人，還主動蹭我的褲腿。可惜家裡不能養寵物，不然真想把它帶回去。\n\n給它買了一根火腿腸，希望它能吃飽一點。',
    'date': DateTime.now().subtract(const Duration(days: 6)).toIso8601String(),
    'tags': ['貓咪', '偶遇', '溫暖'],
  },
  {
    'content':
        '終於到了週末！🎉\n\n睡到了自然醒，然後把家裡徹底打掃了一遍。看著整潔的房間，心情也變得明亮起來。\n\n下午打算去看場電影，聽說最近上映的那部科幻片很不錯。',
    'date': DateTime.now().subtract(const Duration(days: 7)).toIso8601String(),
    'tags': ['週末', '大掃除', '放鬆'],
  },
  {
    'content': '看完電影回來了。🎬\n\n講真，特效很棒，但是劇情稍微有點拉胯。有些邏輯根本講不通嘛！\n\n不過爆米花很好吃，這就夠了。',
    'date': DateTime.now().subtract(const Duration(days: 8)).toIso8601String(),
    'tags': ['電影', '影評', '爆米花'],
  },
  {
    'content':
        '今天嘗試做了一道新菜：紅燒肉。🍖\n\n雖然賣相不太好，黑乎乎的，但是味道意外地還不錯！肥而不膩，入口即化。\n\n看來我有當大廚的潛力啊，哈哈！',
    'date': DateTime.now().subtract(const Duration(days: 9)).toIso8601String(),
    'tags': ['廚藝', '紅燒肉', '自戀'],
  },
  {
    'content':
        '心情有點低落。☁️\n\n感覺自己最近進步好慢，有點迷茫。看著別人一個個都那麼厲害，心裡難免會焦慮。\n\n但是路還是要一步一步走的，對吧？只要不放棄，總會變好的。',
    'date': DateTime.now().subtract(const Duration(days: 10)).toIso8601String(),
    'tags': ['迷茫', '自我反省', '鼓勵'],
  },
  {
    'content':
        '不僅修好了之前的 Bug，還順手把性能最佳化提升了 20%！🚀\n\n我也太強了吧！今天的我，是無敵的！\n\n獎勵自己一杯奶茶！🥤',
    'date': DateTime.now().subtract(const Duration(days: 11)).toIso8601String(),
    'tags': ['性能最佳化', '成就感', '奶茶'],
  },
  {
    'content':
        '讀完了一本書，《被討厭的勇氣》。📖\n\n深受震撼。關於尋找自我，關於體驗生命。所有的經歷，無論是好是壞，都是生命的一部分。',
    'date': DateTime.now().subtract(const Duration(days: 12)).toIso8601String(),
    'tags': ['閱讀', '思考', '人生'],
  },
  {
    'content':
        '今天去公園散步，看到櫻花開了。🌸\n\n粉白色的花瓣隨風飄落，美得像一幅畫。春天真的來了啊。\n\n拍了好多照片，每張都想做成桌布！',
    'date': DateTime.now().subtract(const Duration(days: 13)).toIso8601String(),
    'tags': ['春天', '櫻花', '攝影'],
  },
  {
    'content':
        '收到了一份意外的禮物！🎁\n\n居然是之前隨口提到過的那個機械鍵盤！太驚喜了！\n\n敲擊的手感簡直完美，寫程式碼都更有動力了！',
    'date': DateTime.now().subtract(const Duration(days: 14)).toIso8601String(),
    'tags': ['禮物', '驚喜', '機械鍵盤'],
  },
  {
    'content':
        '今天被拉去參加了一個毫無意義的會議。💤\n\n明明一封郵件就能說清楚的事情，非要講兩個小時。簡直是浪費生命！\n\n以後這種會能躲就躲，太折磨人了。',
    'date': DateTime.now().subtract(const Duration(days: 15)).toIso8601String(),
    'tags': ['開會', '吐槽', '效率'],
  },
  {
    'content':
        '在地鐵上看到了一個很可愛的小寶寶，一直衝著我笑。👶\n\n那一瞬間，心都要化了。小孩子的笑容真的是世界上最治癒的東西。\n\n希望能一直保持這份純真。',
    'date': DateTime.now().subtract(const Duration(days: 16)).toIso8601String(),
    'tags': ['治癒', '寶寶', '微笑'],
  },
  {
    'content':
        '今天挑戰了自己，去跑了 5 公里！🏃‍♂️\n\n雖然跑到一半就快斷氣了，但我還是堅持下來了！\n\n出汗的感覺真爽，感覺整個人都輕盈了。以後要堅持鍛鍊！',
    'date': DateTime.now().subtract(const Duration(days: 17)).toIso8601String(),
    'tags': ['運動', '跑步', '堅持'],
  },
  {
    'content':
        '整理以前的老照片，發現了很多小時候的回憶。📷\n\n那時候無憂無慮，每天只想著怎麼玩。現在長大了，煩惱雖然多了，但也擁有了更多。\n\n珍惜當下吧。',
    'date': DateTime.now().subtract(const Duration(days: 18)).toIso8601String(),
    'tags': ['回憶', '老照片', '感慨'],
  },
  {
    'content':
        '「白守」的初版終於快要完成了！🏁\n\n回顧這段時間的努力，真的感慨萬千。從一個簡單的想法，到現在初具雛形，每一步都凝聚了心血。\n\n但這只是個開始，未來還有很長的路要走。我們一起加油！',
    'date': DateTime.now().subtract(const Duration(days: 19)).toIso8601String(),
    'tags': ['里程碑', '總結', '展望'],
  },
];
