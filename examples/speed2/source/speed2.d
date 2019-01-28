module speed2;
/**
Test program to try and measure the performance cost of building internal XML document, Elements, attributes, etc, from its streamed XML text form.
Trade offs include, the number of function calls and call-backs, size of the character buffers, size of character and UTF encoding, overheads of validation.
*/

import std.stdint;
import core.time: Duration;
import std.datetime.stopwatch : benchmark, StopWatch;

import std.file;
import xml.util.buffer;

import std.stdio;
import core.memory;
import std.random;
import std.conv;
import xml.util.bomstring;
import xml.attribute;
import std.container.array;
import std.algorithm;
import std.string;
import std.range;
import xml.input;
import xml.txml;
import xml.xmlLinkDom;
import xml.xmlArrayDom;
import xml.attribute;

struct Book
{
    string id;
    string author;
    string title;
    string genre;
    string price;
    string pubDate;
    string description;
}

double timedSeconds(ref StopWatch sw)
{
    auto d = sw.peek();
    // 100 ns hecto-nanoseconds 10^7
    return d.total!"hnsecs" * 1e-7;
}

void fullCollect()
{
	GC.collect();
	ulong created, deleted;

	writeln("Full collect done:
          Enter to continue");
	//getchar();
}

import std.file;

void StdXmlRun( string input)
{
    import xml.jcn;
    // Make a DOM tree
    auto doc = new xml.jcn.Document(input);
}

void simpleBookLoad(string s)
{

}

void testXmlInput(string s)
{

	auto xin = new InputCharRange!char();

	xin.entireText(s);

	while(!xin.empty())
	{
		auto test = xin.front();
		xin.popFront();
	}
}

/// run through a basic XML document but no construction
/// of DOM
class SliceResults(T) : xmlt!T.NullDocHandler  {

	alias xmlt!T.XmlErrorImpl XmlErrorImpl;

	void parseSlice(immutable(T)[] xml)
	{
		auto parser = new XmlParser!T();
		parser.errorInterface = new XmlErrorImpl();
		parser.docInterface = this;
		parser.initSource(xml);
		parser.parseAll();
	}

}

void arrayDomPrint(S)(immutable(S)[] xml) {
    auto d = new XMLArrayDom!S.Document();
    XMLArrayDom!S.parseArrayDom!(S)(d, xml);

    auto result = d.pretty(4);
    foreach(a ; result) {
        write(a);
    }
}
void dxmlSliceThroughPut(S)(immutable(S)[] xml)
{
    auto d = new XMLArrayDom!S.Document();
    XMLArrayDom!S.parseArrayDom!(S)(d, xml);
}

auto dxmlMakeDoc(T,S)(immutable(S)[] s)
{
	alias xml.dom.domt.XMLDOM!T	xmldom;

	auto builder = new DXmlDomBuild!(T)();
	auto doc = new xmldom.Document();
	builder.parseNoSlice!S(doc, s);
	return doc;
}
// parser and dom assembly independent of source character type
void dxmlLinkDom(T,S)(immutable(S)[] s)
{
	auto doc = dxmlMakeDoc!(T,S)(s);

	version(Explode)
	{
		doc.explode();
	}
}

void testPrintDom(T)(string s)
{
	alias xml.dom.domt.XMLDOM!T	xmldom;
    void dgStdOut(const(T)[] s)
	{
		write(s);
	}
	auto doc = dxmlMakeDoc!(T,char)(s);
	xmldom.printDocument(doc, &dgStdOut,2);
}

double testHackBuf(uintptr_t repeats, uintptr_t bsize)
{
	Buffer!char	hackBuf;
	StopWatch sw;
	sw.start();
	for(uintptr_t i = 0; i < repeats; i++)
	{
		// grow and reset cycle
		hackBuf.length = 1;
		for(uintptr_t k = 0; k < bsize; k++)
			hackBuf ~= 'X';

	}
	sw.stop();
	auto stime = timedSeconds(sw);
	writefln("HackBuf = %s",stime);
	return stime;
}

double testNativeBuf(uintptr_t repeats, uintptr_t bsize)
{
	char[]		nativeBuf;
	StopWatch sw;
	sw.start();
	for(uintptr_t i = 0; i < repeats; i++)
	{
		// grow and reset cycle
		nativeBuf.length = 1;
		for(uintptr_t k = 0; k < bsize; k++)
			nativeBuf ~= 'X';

	}
	sw.stop();
	auto stime = timedSeconds(sw);
	writefln("NativeBuf = %s",stime);
	return stime;

}

void testValidate(string s)
{
    import xml.jcn;
	xml.jcn.check(s);
}

void singleTest(string inputFile, uintptr_t runs, int testid)
{
    int bomMark = -1;
    auto s = readFileBom!char(inputFile, bomMark);

    enum uint numTests = 5;
	double[numTests] sum;
	double[numTests] sample;
	string[numTests] names = ["xml.jcn",  "check",  "input",  "arrayDom",  "linkDom"];

	//arrayDomPrint!char(s);

    writeln("Run test id ", testid+1, " " , names[testid]);
	sum[] = 0.0;
	StopWatch sw;
	const uint repeat_ct = 10;
    uintptr_t i = 0;
    for (uintptr_t rpt  = 1; rpt <= repeat_ct; rpt++)
	{

        switch(testid)
        {

            case 0:
                sw.start();
                for(i = 0;  i < runs; i++)
                {
                    StdXmlRun(s);
                }
                sw.stop();
                sample[testid] = timedSeconds(sw);
                break;
            case 1:
                sw.start();
                for(i = 0;  i < runs; i++)
                {
                    testValidate(s);
                    //test_throughput(s);
                }
                sw.stop();
                sample[testid] = timedSeconds(sw);

                break;

            case 2:
                sw.start();
                for(i = 0;  i < runs; i++)
                {
                    testXmlInput(s);
                }
                sw.stop();
                sample[testid] = timedSeconds(sw);
                break;
            case 3:
                sw.start();
                for(i = 0;  i < runs; i++)
                {
                    dxmlSliceThroughPut!(char)(s);
                }
                sw.stop();
                sample[testid] = timedSeconds(sw);
                break;
            case 4:
                sw.start();
                for(i = 0;  i < runs; i++)
                {
                    dxmlLinkDom!(char,char)(s);
                    //test_throughput(s);
                }
                sw.stop();
                sample[testid] = timedSeconds(sw);
                break;
            case 5:
                break;
            default:
                break;
        }

        sw.reset();


        writef(" %6.3f", sample[testid]);

		writeln(" ---");
		sum[testid] += sample[testid];
	}

	sum[testid] /= repeat_ct;

	writeln("averages: ", runs, " runs");
	writefln(" %8s", names[testid]);
    writefln(" %8.4f", sum[testid]);
	writeln(" ---");
}

void runTests(string inputFile, uintptr_t runs)
{
	int bomMark = -1;

    auto s = readFileBom!char(inputFile, bomMark);

	simpleBookLoad(s);
	testValidate(s);
	//fullCollect();

	enum uint numTests = 5;
	double[numTests] sum;
	double[numTests] sample;

	testPrintDom!char(s);

	sum[] = 0.0;

	writeln(`
 xml.jcn:       Parse to simple array dom without checking
 check:         Run the verification code for xml.jcn
 input:         Load the xml document with proper filtering
 fullparser:    Use validating parser
 linkdom:       Standard bidirectional linked node DOM`);
	StopWatch sw;
	double ms2 = 0;
	writeln("\n 10 repeats., rotate sequence.");

	const uint repeat_ct = 10;
	auto testIX = new uintptr_t[numTests];
	foreach(ix, ref kn ; testIX)
        kn = ix;
	uintptr_t i;

	for (uintptr_t rpt  = 1; rpt <= repeat_ct; rpt++)
	{
		randomShuffle(testIX);
		for(uintptr_t kt = 0; kt < numTests; kt++)
		{
			auto startix = testIX[kt];

			switch(startix)
			{

                case 0:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        StdXmlRun(s);
                    }
                    sw.stop();
					sample[startix] = timedSeconds(sw);
                    break;
                case 1:
					sw.start();
                    for(i = 0;  i < runs; i++)
                    {
						testValidate(s);
                        //test_throughput(s);
                    }
                    sw.stop();
					sample[startix] = timedSeconds(sw);

                    break;

                case 2:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        testXmlInput(s);
                    }
                    sw.stop();
					sample[startix] = timedSeconds(sw);
                    break;
                case 3:
					sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        dxmlSliceThroughPut!(char)(s);
                    }
                    sw.stop();
					sample[startix] = timedSeconds(sw);
                    break;
                case 4:
					sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        dxmlLinkDom!(char,char)(s);
                        //test_throughput(s);
                    }
                    sw.stop();
					sample[startix] = timedSeconds(sw);
                    break;
                case 5:
                    break;
                default:
                    break;
			}

			sw.reset();
		}
		foreach(v ; sample)
            writef(" %6.3f", v);

		writeln(" ---");
		sum[] += sample[];
	}

	sum[] /= repeat_ct;

	double control = sum[$-1];
	writeln("averages: ", runs, " runs");
	writefln(" %8s %8s %8s %8s %8s %8s", "xml.jcn",  "check",  "input",  "arrayDom",  "linkDom", "handler");
	foreach(v ; sum)
        writef(" %8.4f", v);
	writeln(" ---");

	sum[] *= (100.0/control);
	write("t/control %% = ");
	foreach(v ; sum)
        writef(" %3.0f", v);
	writeln(" ---");
}

void testAttribute()
{
	alias xml.attribute.XmlAttribute!char     XmlAttribute;
	alias xml.attribute.AttributeMap!char     AttributeMap;

	AttributeMap map;

	XmlAttribute a1 = XmlAttribute("a1","value1");
	XmlAttribute a2 = XmlAttribute("a2","value2");
	XmlAttribute a3 = XmlAttribute("a3","value3");
	XmlAttribute a4;

	map.push(a3);
	map.push(a2);
	map.push(a1);

	map.removeName(a2.name);
	assert(map.length==2);
	writefln("count = %s", map.length);
    for(auto i = 0; i < map.length; i++)
	{
		auto attr = map[i];
		writefln("%s = %s", attr.name, attr.value);
	}
	//auto d = new xml.xmlArrayDom.XMLArrayDom!char.Document();
}
void makeArrayDom()
{
	auto d = new xml.xmlArrayDom.XMLArrayDom!char.Document();
}

void usage()
{
	writefln("Working directory is %s", getcwd());
	write("speed.exe  --input <path to books.xml>");
	writeln(" --test <1 - 5> --runs <repetitions (default==100)>");
	return;
}

void main(string[] argv)
{
    string inputFile;
    uintptr_t	  runs = 100;

	//unit_test_1();
	//unit_test_2();
	//unit_test_3();
	 unit_test_4();
	 testAttribute();
    // testDomAssembly();

    uintptr_t act = argv.length;

    uintptr_t i = 0;
    int testid = 0;

    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "--input" && i < act)
            inputFile = argv[i++];
        else if (arg == "--runs" && i < act)
            runs = to!(uint)(argv[i++]);
        else if (arg == "--test" && i < act)
            testid = to!(int)(argv[i++]);
    }

    if (inputFile.length == 0)
    {
		usage();
        return;
    }
    if (inputFile.length > 0)
    {
        if (testid < 1) {
            if (!exists(inputFile))
            {
                auto msg = format("%s not found : from dir %s", inputFile, getcwd());

                writeln(msg);
                usage();
                return;
            }
            runTests(inputFile,runs);
        }
        else {
            if (testid > 5) {
                writeln("test number not between 1 and 5");
                usage();
                return;
            }
            singleTest(inputFile,runs, testid-1);
        }
    }

	//fullCollect();
	version(GC_STATS)
	{
        GC.collect();
		GCStatsSum.AllStats();
		//getchar();
		//GCStatsSum.AllStats();
		//writeln("If some objects are still alive, try calling  methods.explode");
		//version(TrackCount)
		//	listTracks();
		writeln("Enter to exit");

	}
	writeln("All done");
	//getchar();
}

void unit_test_1()
{
    import xml.jcn;

	try
	{
		check(q"[<?xml version="1.0"?>
				<catalog>
				<book id="bk101">
				<author>Gambardella, Matthew</author>
				<title>XML Developer's Guide</title>
				<genre>Computer</genre>
				<price>44.95</price>
				<publish_date>2000-10-01</publish_date>
				<description>An in-depth look at creating applications
				with XML.</description>
				</book>
				<book id="bk102">
				<author>Ralls, Kim</author>
				<title>Midnight Rain</title>
				<genre>Fantasy</genres>
				<price>5.95</price>
				<publish_date>2000-12-16</publish_date>
				<description>A former architect battles corporate zombies,
				an evil sorceress, and her own childhood to become queen
				of the world.</description>
				</book>
				<book id="bk103">
				<author>Corets, Eva</author>
				<title>Maeve Ascendant</title>
				<genre>Fantasy</genre>
				<price>5.95</price>
				<publish_date>2000-11-17</publish_date>
				<description>After the collapse of a nanotechnology
				society in England, the young survivors lay the
				foundation for a new society.</description>
				</book>
				</catalog>
				]");
		assert(false);
	}
	catch(CheckException e)
	{
		auto msg = e.toString();
		auto n = msg.indexOf("end tag name 'genres' differs" ~
										" from start tag name 'genre'");
		assert(n != -1);
	}
}


void unit_test_3()
{
    import xml.jcn;
    string s = q"EOS
<?xml version="1.0"?>
<set>
<one>A</one>
<!-- comment -->
<two>B</two>
</set>
EOS";

    try
    {
        check(s);
    }
    catch (CheckException e)
    {
        assert(0, e.toString());
    }
}

void unit_test_4()
{
    import xml.jcn;

    string s = `<tag attr="&quot;value&gt;" />`;
    auto doc = new Document(s);
    assert(doc.toString() == s);
}
