using Meltype.Composition;
namespace Meltype.Tests;

internal static class BoundaryMemoryTests
{
    [Test]
    public static void BoundaryMemory_ContextSeparatesOppositeCutsAndAbstainsWithoutEvidence()
    {
        var m = new ContextBoundaryMemory(null);
        m.Remember("ここではきものを", [3,5], "玄関で靴を脱ぐ。", "");
        m.Remember("ここではきものを", [4,4], "更衣室で着物を着替える。", "");
        Assert.Equal("3,5", string.Join(",", m.Find("ここではきものを", "玄関で靴を脱ぐ。", "")!));
        Assert.Equal("4,4", string.Join(",", m.Find("ここではきものを", "更衣室で着物を着替える。", "")!));
        Assert.True(m.Find("ここではきものを", "天気予報を確認した。", "") is null, "Do not apply the last correction globally");
        Assert.True(m.Find("ここではきものを", "", "") is null, "Missing context is not evidence");
    }

    [Test]
    public static void BoundaryMemory_PersistsAndLatestExplicitCorrectionReplacesSameContext()
    {
        var path = Path.Combine(Path.GetTempPath(), "boundary-"+Guid.NewGuid()+".json");
        try {
            var m = new ContextBoundaryMemory(path);
            m.Remember("きょうはいしゃに", [4,4], "体調が悪い。", "");
            m.Remember("きょうはいしゃに", [3,5], "体調が悪い。", "");
            var loaded = new ContextBoundaryMemory(path);
            Assert.Equal(1, loaded.Count);
            Assert.Equal("3,5", string.Join(",", loaded.Find("きょうはいしゃに", "体調が悪い。", "")!));
        } finally { if (File.Exists(path)) File.Delete(path); }
    }

    [Test]
    public static void BoundaryMemory_RejectsInvalidPatternsAndIgnoresBrokenFile()
    {
        var m = new ContextBoundaryMemory(null);
        Assert.True(!m.Remember("きょう", [0,3], "", ""), "No zero length clauses");
        Assert.True(!m.Remember("きょう", [1,1], "", ""), "Readings must be conserved");
        Assert.True(!m.Remember("https://example.com", [19], "", ""), "Protected/literal text is not a Japanese boundary sample");
        var path=Path.Combine(Path.GetTempPath(),"boundary-"+Guid.NewGuid()+".json");
        try { File.WriteAllText(path,"not json"); Assert.Equal(0,new ContextBoundaryMemory(path).Count); }
        finally { File.Delete(path); }
    }

    [Test]
    public static void BoundaryMemory_TwoThousandContextLookupsDoNotLeakAcrossReadings()
    {
        var m = new ContextBoundaryMemory(null);
        var readings=new List<string>();
        for(var i=0;i<500;i++) {
            var n=i;var word="あ";for(var j=0;j<5;j++){word+="かきくけこさしすせそ"[n%10];n/=10;}
            readings.Add(word);
            m.Remember(word,[2,4],"玄関で靴を脱ぐ。","");
            m.Remember(word,[3,3],"更衣室で着物を着替える。","");
        }
        foreach(var word in readings) {
            Assert.Equal("2,4",string.Join(",",m.Find(word,"玄関で靴を脱ぐ。","")!));
            Assert.Equal("3,3",string.Join(",",m.Find(word,"更衣室で着物を着替える。","")!));
            Assert.True(m.Find(word,"電車の運行情報を読む。","") is null,"Unrelated context must not inherit a correction");
            Assert.True(m.Find(word+"あ","玄関で靴を脱ぐ。","") is null,"Another reading must not inherit a correction");
        }
    }

    [Test]
    public static void BoundaryMemory_TenThousandAlternatingCorrectionsKeepContextsSeparate()
    {
        var m=new ContextBoundaryMemory(null);
        for(var i=0;i<10000;i++) {
            var a=i%2==0;
            m.Remember("ここではきものを",a?[3,5]:[4,4],a?"玄関で靴を脱ぐ。":"更衣室で着物を着替える。","");
            Assert.Equal(a?"3,5":"4,4",string.Join(",",m.Find("ここではきものを",a?"玄関で靴を脱ぐ。":"更衣室で着物を着替える。","")!));
        }
        Assert.Equal(2,m.Count);
    }

    [Test]
    public static void BoundaryMemory_RightContextAndSameSurfaceCutsRemainDistinct()
    {
        // Same output can have different teacher-chosen cuts; text generation cannot distinguish them.
        var m=new ContextBoundaryMemory(null);
        m.Remember("きょうは",[3,1],"","日付の部分を選んで修正する。");
        m.Remember("きょうは",[4],"","挨拶をまとめて選んで修正する。");
        Assert.Equal("3,1",string.Join(",",m.Find("きょうは","","日付の部分を選んで修正する。")!));
        Assert.Equal("4",string.Join(",",m.Find("きょうは","","挨拶をまとめて選んで修正する。")!));
    }

    [Test]
    public static void BoundaryMemory_ClampsContextAndDefendsReturnedArrays()
    {
        var m=new ContextBoundaryMemory(null);var lengths=new[]{3,5};
        var left=new string('外',300)+"玄関で靴を脱ぐ。";var right="着替え"+new string('続',200);
        m.Remember("ここではきものを",lengths,left,right);lengths[0]=7;
        var found=m.Find("ここではきものを",left[^256..],right[..128])!;
        Assert.Equal("3,5",string.Join(",",found));found[0]=7;
        Assert.Equal("3,5",string.Join(",",m.Find("ここではきものを",left,right)!));
    }

    [Test]
    public static void BoundaryMemory_ConflictingSimilarContextsAbstain()
    {
        var m=new ContextBoundaryMemory(null);
        m.Remember("ここではきものを",[3,5],"玄関で着物と靴を整理する。甲","");
        m.Remember("ここではきものを",[4,4],"玄関で着物と靴を整理する。乙","");
        Assert.True(m.Find("ここではきものを","玄関で着物と靴を整理する。","") is null,"Close conflicting evidence should abstain");
    }

    [Test]
    public static void BoundaryMemory_CapacityEvictsOldestAndDoesNotGrowOnRepetition()
    {
        var m=new ContextBoundaryMemory(null);
        for(var i=0;i<1500;i++) m.Remember("きょうは",[3,1],"日付を修正する。"+i,"");
        Assert.Equal(1024,m.Count);
        // Update the latest record without increasing count.
        for(var i=0;i<100;i++) m.Remember("きょうは",[4],"日付を修正する。1499","");
        Assert.Equal(1024,m.Count);
    }

    [Test]
    public static void BoundaryMemory_ParallelReadsAndCorrectionsConserveLengths()
    {
        var m=new ContextBoundaryMemory(null);
        Parallel.For(0,3000,i=> {
            var left=i%2==0?"玄関で靴を脱ぐ。":"更衣室で着物を着替える。";
            m.Remember("ここではきものを",i%2==0?[3,5]:[4,4],left,"");
            var result=m.Find("ここではきものを",left,"")!;
            Assert.Equal(8,result.Sum());
            Assert.Equal(i%2==0?"3,5":"4,4",string.Join(",",result));
        });
        Assert.Equal(2,m.Count);
    }

    [Test]
    public static void BoundaryMemory_ValidatesStoredEntriesAndHandlesUnwritablePath()
    {
        var path=Path.Combine(Path.GetTempPath(),"boundary-"+Guid.NewGuid()+".json");
        try {
            File.WriteAllText(path,"[{\"Reading\":\"きょうは\",\"Lengths\":[0,4],\"Left\":\"日付\",\"Right\":\"\"},null]");
            Assert.Equal(0,new ContextBoundaryMemory(path).Count);
            // An existing file cannot be used as a parent directory.
            var m=new ContextBoundaryMemory(Path.Combine(path,"blocked.json"));
            Assert.True(m.Remember("きょうは",[3,1],"日付を修正する。",""),"In-memory learning survives persistence failure");
            Assert.Equal("3,1",string.Join(",",m.Find("きょうは","日付を修正する。","")!));
        } finally { File.Delete(path); }
    }
}
