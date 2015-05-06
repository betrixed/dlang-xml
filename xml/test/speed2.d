module xml.test.speed2;
/**
Test program to try and measure the performance cost of building internal XML document, Elements, attributes, etc, from its streamed XML text form.
Trade offs include, the number of function calls and call-backs, size of the character buffers, size of character and UTF encoding, overheads of validation.
*/

import std.stdint;
import std.datetime;
import std.file;
import xml.util.buffer;
version(GC_STATS)
{
	import alt.gcstats;
}

import xml.std.xmlSlicer;
import std.stdio;
import core.memory;
import std.random;
import std.conv;
import xml.util.bomstring;
import xml.xmlAttribute;
import std.container.array;
import std.algorithm;
import std.string;
import std.range;
import xml.textInput;
import xml.xmlParser;
import xml.txml;
import xml.xmlLinkDom;
import xml.xmlArrayDom;

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
    auto duration = sw.peek();

    return duration.to!("seconds",double)();
}

void fullCollect()
{
	GC.collect();
	ulong created, deleted;

	writeln("Enter to continue");
	getchar();
}

import std.stream;

void StdXmlRun( string input)
{
	// Check for well-formedness
	debug {
		// Very slow as throws and catches exceptions all over the place.
	}
	else {
		//std.xml.check(input); // Very slow as throws and catches exceptions all over the place.
	}
    //std.xml.check(input);

    // Make a DOM tree
    auto doc = new Document(input);
}

void simpleBookLoad(string s)
{
    // Check for well-formedness
   check(s);

    // Take it apart
    Book[] books;

    auto xml = new DocumentParser(s);
    xml.onStartTag["book"] = (ElementParser xml)
    {
        Book book;
        book.id = xml.tag.attr["id"];

        xml.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
        xml.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
        xml.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
        xml.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
        xml.onEndTag["publish-date"] = (in Element e) { book.pubDate     = e.text(); };
        xml.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

        xml.parse();

        books ~= book;
    };
    xml.parse();

    // Put it back together again;
    auto doc = new Document(new Tag("catalog"));
    foreach(book;books)
    {
        auto element = new Element("book");
        element.attribute["id"] = book.id;

        element ~= new Element("author",      book.author);
        element ~= new Element("title",       book.title);
        element ~= new Element("genre",       book.genre);
        element ~= new Element("price",       book.price);
        element ~= new Element("publish-date",book.pubDate);
        element ~= new Element("description", book.description);

        doc ~= element;
    }

    // Pretty-print it
    writefln(join(doc.pretty(3),"\n"));
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
void dxmlSliceThroughPut(T,S)(immutable(S)[] xml)
{
	auto dummy = new SliceResults!(S)();
	dummy.parseSlice(xml);
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
	check(s);
}


void runTests(string inputFile, uintptr_t runs)
{
	int bomMark = -1;

    auto s = readTextBom!char(inputFile, bomMark);

	simpleBookLoad(s);
	testValidate(s);
	fullCollect();

	enum uint numTests = 5;
	double[numTests] sum;
	double[numTests] sample;

	testPrintDom!char(s);

	sum[] = 0.0;

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
                        dxmlSliceThroughPut!(char,char)(s);
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
	writefln(" %8s %8s %8s %8s %8s %8s", "std.xml",  "check",  "input",  "slice2",  "linkdom", "handler");
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
	alias XMLAttribute!char		 attr_t;
	alias attr_t.XmlAttribute     XmlAttribute;
	alias attr_t.AttributeMap     AttributeMap;

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
	writeln("speed.exe  --input <path to books.xml>	--runs <repetitions (default==100)>");
	getchar();
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
    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "--input" && i < act)
            inputFile = argv[i++];
        else if (arg == "--runs" && i < act)
            runs = to!(uint)(argv[i++]);
    }

    if (inputFile.length == 0)
    {
		usage();
        return;
    }
    if (inputFile.length > 0)
    {
        if (!exists(inputFile))
        {
            writeln("File not found : ", inputFile, "from ", getcwd());
            usage();
            return;
        }

		runTests(inputFile,runs);

    }
	//fullCollect();
	version(GC_STATS)
	{
		//GCStatsSum.AllStats();
		//writeln("If some objects are still alive, try calling  methods.explode");
		//version(TrackCount)
		//	listTracks();
		writeln("Enter to exit");

	}
	writeln("All done");
	getchar();
}

void unit_test_1()
{

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

void unit_test_2()
{
    string s = q"EOS
<?xml version="1.0" encoding="utf-8"?>
<Tests><Test thing="What &amp; Up">What &amp; Up Second</Test></Tests>
EOS";

    auto xml = new DocumentParser(s);

    xml.onStartTag["Test"] = (ElementParser xml) {
        assert(xml.tag.attr["thing"] == "What & Up");
    };

    xml.onEndTag["Test"] = (in Element e) {
        assert(e.text() == "What & Up Second");
    };
    xml.parse();
}

void unit_test_3()
{
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
    string s = `<tag attr="&quot;value&gt;" />`;
    auto doc = new Document(s);
    assert(doc.toString() == s);
}
