module xml.test.speed;
/**
Test program to try and measure the performance cost of building internal XML document, Elements, attributes, etc, from its streamed XML text form.
Trade offs include, the number of function calls and call-backs, size of the character buffers, size of character and UTF encoding, overheads of validation.
*/

import xml.parse.dxml;
import xml.ixml, xml.xmlerror;
import xml.parse.domt;
import xml.dom.domt;
import xml.dom.arrayt;
import xml.parse.arrayt;
import xml.util.visit, xml.parse.input, xml.util.read;

import core.memory;
import std.stdio, std.datetime,std.string, std.stdint;

import std.variant, std.conv, std.random, std.file;

import alt.buffer, alt.bomstring;

alias xml.ixml.xmlt!char.XmlEvent	XmlReturn;
alias xml.ixml.XmlResult		xr;

alias xml.dom.arrayt.XMLARRAY!char			arraydom;
alias xml.parse.arrayt.ArrayDomBuilder!char	ArrayDomBuilder;

alias xml.dom.domt.XMLDOM!char			linkdom;
alias xml.parse.domt.DXmlDomBuild!char	LinkDomBuilder;

alias xml.util.visit.XmlDelegate!char	TagBlock;
alias xml.util.visit.TagVisitor!char	TagVisitor;

version(GC_STATS)
{
	import alt.gcstats;
}

string Example4 =
`<?xml version="1.0" encoding="utf-8"?>
<A>
                 <!-- Comment 1 -->
                  <B> <C id="1" value="&quot;test&quot;" >
                   <D> Xml &quot;Text&quot; in D &apos;&amp;&lt;&gt; </D> </C> <C id="2" />
                   <!-- Comment 2 -->
                   <C id="3"></C>
                   </B>
<![CDATA[ This is <Another sort of text ]]>
<?Lua   --[[ Dense hard to follow script
                                                                  --]]
?>
</A>`;


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


void nesting_tagvisitor()
{
	alias xml.util.visit.TagVisitor!char	TagVisitor;
	alias xml.util.visit.XmlDelegate!char	TagBlock;
	alias XmlEvent!char	XmlReturn;

    auto tv = new TagVisitor();


    /// The callbacks will all have different keys, so only need one set, for this kind of document
    /// But still need to set the parser stack callback object for each level, usually in a TAG_START callback.
    ///
    string[] allText;

    /// const prebuilt keys for non tagged nodes
    auto textDg = (XmlReturn xml)
    {
        allText ~= xml.scratch;
    };

    auto piDg = (XmlReturn xml)
    {
		auto p = xml.attr.atIndex(0);
		allText ~= text(p.id," ",p.value);
    };

    tv.defaults[xr.TEXT] = textDg;
    tv.defaults[xr.CDATA] = textDg;
    tv.defaults[xr.XML_PI] = piDg;
    tv.defaults[xr.COMMENT] = textDg;


    tv.defaults[xr.XML_DEC] = (XmlReturn xml)
    {
		foreach(p,q ; xml.attr)
			writefln("%s='%s'",p, q);
    };

	TagBlock[]	saveDefaults;
	auto bce = new  ArrayDomBuilder();

	auto ctags = new TagBlock("C");
	tv.put(ctags);

	tv["C",xr.TAG_EMPTY] = (XmlReturn xml)
	{
		if (xml.attr.length > 0)
			foreach(n, v ; xml.attr)
                writefln("%s = '%s'", n, v);
	};

    tv["C",xr.TAG_START] = (XmlReturn xml)
    {
		saveDefaults ~= tv.defaults;
		tv.defaults = new TagBlock(tv.defaults);
		tv.defaults.setInterface(bce);
		bce.startTag(xml);
	};

	tv["C",xr.TAG_END] = (XmlReturn xml)
	{
		auto slen = saveDefaults.length;
		if (slen > 0)
		{
			slen--;
			tv.defaults = saveDefaults[slen];
			saveDefaults.length =  slen;
		}
		auto elem = bce.root;
		if (elem.hasAttributes())
		{
			foreach(n, v ; elem.getAttributes())
			{
                writefln("%s = '%s'", n, v);
			}
		}
		writeln("Content: ", elem.text);
	};


	tv["B",xr.TAG_START] = (XmlReturn xml)
	{
		writeln("B Start");
	};

	auto A_tags = new TagBlock("A");
	tv.put(A_tags);

    A_tags[xr.TAG_START] = (XmlReturn xml)
    {
        writeln("Document A Start");
    };

	A_tags[xr.TAG_END] = (XmlReturn xml)
    {
        writeln("Document A End");
    };

    tv.setupNormalize(Example4);
	tv.parseDocument();

    writefln("%s",allText);
	version(Explode)
	{
		bce.explode();
		tv.explode();
	}

}

void outputBooks(Book[] books)
{
	alias linkdom.Document domDocument;
	alias linkdom.Element domElement;

    // Put it back together again, to see the information was extracted
    auto doc = new domDocument(new domElement("catalog"));
    foreach(bk; books)
    {
        auto element = new domElement("book");
        element.setAttribute("id",bk.id);

        element ~= new domElement("author",      bk.author);
        element ~= new domElement("title",       bk.title);
        element ~= new domElement("genre",       bk.genre);
        element ~= new domElement("price",       bk.price);
        element ~= new domElement("publish_date",bk.pubDate);
        element ~= new domElement("description", bk.description);

        doc ~= element;
    }
    doc.setXmlVersion("1.0");
    // Pretty-print it
    writefln(std.string.join(doc.pretty(3),"\n"));
	version(Explode)
	{
		doc.explode();
	}
}

// another way to do it.
void books2collect(string s)
{

    alias xml.util.visit.TagVisitor!char Visitor;
	alias XmlEvent!char	XmlReturn;
	alias Visitor.Namespace Namespace;

	auto visitor = new Visitor();
    // get a set of callbacks at the current state.

    // Check for well-formedness. Note that this is superfluous as it does same as parse.
    //sdom.check(s);

    // Take it apart
    Book[]  books;
	Book	book;

	Namespace mainNamespace, bookNamespace;

    auto bookcb = visitor.create("book");

	bookcb[xr.TAG_START] = (XmlReturn xml) {
		book.id = xml.attr["id"];
		visitor.namespace = bookNamespace;
	};
	bookcb[xr.TAG_END] = (XmlReturn xml) {
		books ~= book;
		visitor.namespace = mainNamespace;
	};

	mainNamespace = visitor.namespace;
	visitor.namespace = null;

	/// single delegate assignment for tag
	visitor["author", xr.TEXT] = (XmlReturn xml) {
		book.author = xml.scratch;
	};
	visitor["title", xr.TEXT] = (XmlReturn xml) {
		book.title = xml.scratch;
	};
	visitor["genre", xr.TEXT] = (XmlReturn xml) {
		book.genre = xml.scratch;
	};
	visitor["price",xr.TEXT] = (XmlReturn xml)
	{
		book.price = xml.scratch;
	};
	visitor["publish_date",xr.TEXT] = (XmlReturn xml)
	{
		book.pubDate = xml.scratch;
	};
	visitor["description",xr.TEXT] = (XmlReturn xml)
	{
		book.description = xml.scratch;
	};

	bookNamespace = visitor.namespace;
	visitor.namespace = mainNamespace;

	visitor.setupNormalize(s);
	visitor.parseDocument();
	outputBooks(books);

	version(Explode)
	{
		visitor.explode();
	}
}


void xml1_books(string s)
{
	alias xml.util.visit.XmlHandler!char ElementParser;

	with(xml.dom.arrayt.XMLARRAY!char)
	{

		// Take it apart
		Book[] books;


		auto xml = new ElementParser(s);

		xml.onStartTag["book"] = (ElementParser xml)
		{
			Book book;
			book.id = xml.tag.attr.get("id",null);
			xml.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
			xml.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
			xml.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
			xml.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
			xml.onEndTag["publish_date"] = (in Element e) { book.pubDate     = e.text(); };
			xml.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

			xml.parseDocument(-1);	// -1 to exit after book tag ends.

			books ~= book;
		};
		xml.setupNormalize();
		xml.parseDocument(); // exit at same element depth level, ie 0

		version(Explode)
			xml.explode();

		outputBooks(books);
	}
}

// Tends to be slower. Handlers are set for every instance of book.
// depends on parseOne. Requires build of some DOM Element for text.

void xml1_books_speed(string s)
{
	alias xml.util.visit.XmlHandler!char ElementParser;

	with(xml.dom.arrayt.XMLARRAY!char)
	{
		// Take it apart
		Book[] books;

		auto xml = new ElementParser(s);

		xml.onStartTag["book"] = (ElementParser xml)
		{
			Book book;
			book.id = xml.tag.attr.get("id",null);
			xml.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
			xml.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
			xml.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
			xml.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
			xml.onEndTag["publish_date"] = (in Element e) { book.pubDate     = e.text(); };
			xml.onEndTag["description"]  = (in Element e) { book.description = e.text(); };

			xml.parseDocument(-1);	// We are inside book, but want to exit after book pops.

			books ~= book;
		};
		xml.setupNormalize();
		xml.parseDocument();

		version(Explode)
			xml.explode();

	}
}


/// The XmlHandler can be used as a HandlerSet, as Namespaces.
/// Handler set remains in force until replaced.

void xml1_books_flattened_speed(string s)
{
	alias xml.util.visit.XmlHandler!char ElementParser;
	alias ElementParser.HandlerSet	HandlerSet;
	alias ElementParser.Element	Element;


	Book[]  books;
	Book	book;

	auto xml = new ElementParser(s);

	auto bookHandlers = xml.new HandlerSet();

	bookHandlers.onEndTag["author"]       = (in Element e) { book.author      = e.text(); };
	bookHandlers.onEndTag["title"]        = (in Element e) { book.title       = e.text(); };
	bookHandlers.onEndTag["genre"]        = (in Element e) { book.genre       = e.text(); };
	bookHandlers.onEndTag["price"]        = (in Element e) { book.price       = e.text(); };
	bookHandlers.onEndTag["publish_date"] = (in Element e) { book.pubDate     = e.text(); };
	bookHandlers.onEndTag["description"]  = (in Element e) { book.description = e.text(); };


	xml.onStartTag["book"] = (ElementParser xml)
	{
		book.id = xml.tag.attr.get("id",null);

		xml.pushHandlerSet(bookHandlers);
		xml.parseDocument(-1);	// We are inside book, but want to exit after book pops.
		xml.popHandlerSet();

		books ~= book;
	};
	xml.setupNormalize();
	xml.parseDocument();

	version(Explode)
		xml.explode();

}

/// Slightly faster, because no DOM dependency required for Element construction/destruction
/// All delegates assigned only once.
/// Reduced delegate function stack depth.
/// All callbacks from single call to parseDocument.

/// Handler name space based on element tag name.
/// For instance, if main document also had an "author" and "title" tag,
/// these would need to be set only when in the "book" tag.
/// Swap the name space "tagHandlers" while in book tag.
/// Multiple nesting of delegate functions is too awkward to attempt with this,
/// as it works best when the main context sticks around

void tagvisitor_speed(immutable(char)[] s)
{

    //auto parser = new XmlStringParser(s);
	alias xml.util.visit.TagVisitor!char Visitor;
	alias Visitor.TagBlock TagBlock;
	alias Visitor.Namespace Namespace;

    auto visitor = new Visitor();
	//alias xml.parseitem.XmlResult	xr;


	Book[] books;
	Book book;

	version(Explode)
	{
		scope(exit)
		{
			visitor.explode();
		}
	}
/// Two AA references, for 2 tag namespaces
	Namespace	bookHandlers, mainHandlers;

	visitor["book", xr.TAG_START] = (XmlReturn xml) {
		book.id = xml.attr["id"];
		visitor.namespace = bookHandlers;	// to book namespace
		visitor.parseDocument(-1);			// exit after book end tag
		visitor.namespace = mainHandlers;
		books ~= book;
	};

	mainHandlers = visitor.namespace;		// get namespace for document
	visitor.namespace = null;				// creates a new namespace for book

	/// Use convenience to set up a TagBlock for each element.
	visitor["author", xr.TEXT] = (XmlReturn xml) {
		book.author = xml.scratch;
	};
	visitor["title", xr.TEXT] = (XmlReturn xml) {
		book.title = xml.scratch;
	};
	visitor["genre", xr.TEXT] = (XmlReturn xml) {
		book.genre = xml.scratch;
	};
	visitor["price",xr.TEXT] = (XmlReturn xml)
	{
		book.price = xml.scratch;
	};
	visitor["publish_date",xr.TEXT] = (XmlReturn xml)
	{
		book.pubDate = xml.scratch;
	};
	visitor["description",xr.TEXT] = (XmlReturn xml)
	{
		book.description = xml.scratch;
	};

	bookHandlers = visitor.namespace; // get AA bookHandlers,
	visitor.namespace = mainHandlers; // start with main namespace.

	visitor.setupNoSlice!char(s);
	visitor.parseDocument();


}

class storeErrorMsg : DOMErrorHandler
{
    string remember;

    override bool handleError(DOMError error)
    {
        remember = error.getMessage();
        return false; // stop processing
    }
}

void test_validate(string inputFile)
{

	auto doc = new linkdom.Document(); // not the element tag name, just the id
	version(Explode)
	{
		scope(exit)
			doc.explode();
	}

	auto config = doc.getDomConfig();
	auto sm = new storeErrorMsg();
	config.setParameter("error-handler",Variant(cast(DOMErrorHandler) sm));
	try
	{
		auto builder = new LinkDomBuilder();
		builder.parseFile(doc,inputFile);
		version(Explode)
		{
 		scope(exit)
			builder.explode();
		}
	}
	catch(XmlError pe)
	{
		writeln(pe.toString());
		writeln(sm.remember);
	}

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

void dxmlStreamTest(T,S)(immutable(S)[] xml)
{
	auto builder = new DXmlDomBuild!(T)();
	ulong pos = 0;
	auto df = new SliceFill!S(xml);

	bool getData(ref const(dchar)[] buf)
	{
		return df.fillData(buf, pos);
	}

	scope(exit)
		delete df;

	builder.parseInputDg(new tdom.XMLDOM!T.Document(), &getData);
}

/// T - character type for XMLDOM and XmlString used by parser
/// T == char , is most efficient for 8-bit codeable languages.
/// S - character type of xml array
void dxmlSliceTest(T,S)(const(S)[] s)
{
	alias xml.dom.domt.XMLDOM!T	tdom;

	auto builder = new DXmlDomBuild!(T)();
	builder.parseSlice(new tdom.Document(), s);
	auto doc = builder.doc_;
	builder.doc_ = null;
	version(Explode)
	{
        doc.explode();
        builder.explode();
	}


}
// parser, dom must match input array character type
void dxmlSliceDom(T)(immutable(T)[] s)
{
	alias xml.dom.domt.XMLDOM!T	tdom;
    auto doc = new tdom.Document();


	auto builder = new DXmlDomBuild!(T)();
	builder.parseSlice( s);
	auto doc = builder.doc_;
	builder.doc_ = null;
	version (Explode)
	{
		doc.explode();
	}


}
// parser and dom assembly independent of source character type
void dxmlNonSliceDom(T,S)(immutable(S)[] s)
{
	alias xml.dom.domt.XMLDOM!T	tdom;

	auto builder = new DXmlDomBuild!(T)();
	builder.parseNoSlice!S(new tdom.Document(), s);
	auto doc = builder.doc_;
	builder.doc_ = null;
	version(Explode)
	{
		builder.explode();
	}
	version(Explode)
	{
		doc.explode();
	}
}
// parser and dom assembly independent of source character type

void dxmlSliceTestPrint(T,S)(immutable(S)[] s)
{
	alias xml.dom.domt.XMLDOM!T tdom;

	auto builder = new DXmlDomBuild!T();

	builder.parseSlice(new tdom.Document(), s);
	auto doc = builder.doc_;
	builder.doc_ = null;
	version(Explode)
	{
		builder.explode();
	}
    void output(const(char)[] p)
    {
        write(p);
    }
	tdom.printDocument(doc, &output, cast(uint)2);
	version(Explode)
	{
		doc.explode();
	}
	writeln();
}

/// for dxml through put, use a none functioning IXmlEvents, with generic exception
class StreamResults(T,S) : NullDocHandler!T  {

	SliceFill!S			sf_;
	ulong				pos_;

	bool getData(ref const(dchar)[] data)
	{
		return sf_.fillData(data,pos_);
	}

	void parseSlice(immutable(S)[] xml)
	{
		sf_ = new SliceFill!S(xml);
		auto parser = new DXmlParser!T();
		parser.errorInterface = this;
		parser.docInterface = this;
		parser.initSource(&getData);
		parser.parseAll();
	}

}
class SliceResults(T) : NullDocHandler!T  {

	void parseSlice(immutable(T)[] xml)
	{
		auto parser = new DXmlParser!T();
		parser.errorInterface = this;
		parser.docInterface = this;
		parser.initSource(xml);
		parser.parseAll();
	}

}
void dxmlStreamThroughPut(T,S)(immutable(S)[] xml)
{
	auto dummy = new StreamResults!(T,S)();
	dummy.parseSlice(xml);
}
void dxmlSliceThroughPut(T,S)(immutable(S)[] xml)
{
	auto dummy = new SliceResults!(S)();
	dummy.parseSlice(xml);
}

import std.stream;
void runTests(string inputFile, uintptr_t runs)
{
    int bomMark = -1;


	//string s = std.file.read(inputFile);
	//dstring ds = to!dstring(s);
	//wstring ws = to!wstring(s);

    ubyte[] raw;


    raw.length = 4525;
    writefln("Ptr %x, Length %s",raw.ptr, raw.length);
    raw.length = 0;
    writefln("Ptr %x, Length %s",raw.ptr, raw.length);
        //f.readBlock(raw.ptr, bufSize);

    string s;
    //auto s = readTextBom!char(inputFile, bomMark);
	//dxmlSliceTestPrint!(char,char)(s);
    return;
	//ticketTests();

	//writeln("ticketTests OK?");
	fullCollect();
	//books2collect(s);
	//writeln("That was XmlParse and TagVisitor, books array, then manual build linkdom.Document");
	//fullCollect();
	//test_validate(inputFile);
	//fullCollect();
	//version(GC_STATS)
    //    GCStatsSum.AllStats();
	//testTicket12(inputFile);
	//xml1_books(s);
	//writeln("That was using ElementParser, similar to std.xml");
	//getchar();
	//fullCollect();


	enum uint numTests = 6;
	double[numTests] sum;
	double[numTests]	sample;

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
                        dxmlSliceThroughPut!(char,char)(s);
                    }
                    sw.stop();
                    break;

                case 1:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        dxmlStreamThroughPut!(char,char)(s);
                    }
                    sw.stop();
                    break;

                case 2:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        dxmlSliceDom!(char)(s);
                        //test_throughput(s);
                    }
                    sw.stop();
                    break;
                case 3:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        dxmlNonSliceDom!(char,char)(s);
                        //test_throughput(s);
                    }
                    sw.stop();
                    break;
                case 5:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        //xml1_books_speed(s);
						xml1_books_flattened_speed(s);
                    }
                    sw.stop();
                    break;
                case 4:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        tagvisitor_speed(s);
                    }
                    sw.stop();
                    break;
                default:
                    break;
			}
			sample[startix] = timedSeconds(sw);
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
	writeln("Through-put slice, stream, slicedom, streamdom, tagvisitor, handler");
	foreach(v ; sum)
        writef(" %7.4f", v);
	writeln(" ---");

	sum[] *= (100.0/control);
	write("t/control %% = ");
	foreach(v ; sum)
        writef(" %3.0f", v);
	writeln(" ---");
}

void main(string[] argv)
{
    string inputFile;
    uintptr_t	  runs = 100;

    // testDomAssembly();

    uintptr_t act = argv.length;

    uintptr_t i = 0;
    while (i < act)
    {
        string arg = argv[i++];
        if (arg == "input" && i < act)
            inputFile = argv[i++];
        else if (arg == "runs" && i < act)
            runs = to!(uint)(argv[i++]);
    }

    if (inputFile.length == 0)
    {
        writeln("sxml.exe  input <path to books.xml>	runs <repetitions (default==100)>");
        return;
    }
    if (inputFile.length > 0)
    {
        if (!exists(inputFile))
        {
            writeln("File not found : ", inputFile, "from ", getcwd());
            getchar();
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
		getchar();
	}
}



bool ticketTest(string src)
{
    try
    {
        auto bld = new SliceResults!char();
		bld.parseSlice(src);
    }
    catch(Exception e)
    {
        writeln(e.toString());
        return false;
    }
    return true;
}

void emptyDocElement()
{
    string doc;

    doc =`<?xml version="1.0" encoding="utf-8"?><main test='"what&apos;s up doc?"'/>`;

    auto tv = new TagVisitor();
	tv.setupNormalize(doc);

	version(Explode)
        scope(exit)
        {
            tv.explode();
        }
    tv["main", xr.TAG_START] = (XmlReturn xml)
    {
        // main item
        writeln("Got main test=",xml.attr["test"]);
    };

    tv.parseDocument();




}
void testTicket12(string inputFile)
{
	// Load file access violation?
	auto doc = new linkdom.Document();
	parseXmlFile(doc, inputFile,false);
	version(Explode) doc.explode();
}
void testTicket4()
{
    string src = Example4;
    assert(ticketTest(src));
}
void testTicket8()
{

    bool testTicket(string src)
    {
        try
        {
            auto tv = new TagVisitor();

			version(Explode)
                scope(exit)
                {
                    tv.explode();
                }

			char[]	btext;

			tv["B", xr.TAG_START] = (XmlReturn ret)
			{
				btext = null;
			};

			tv["B", xr.TEXT] = (XmlReturn ret)
			{
				btext ~= ret.scratch;
			};

            tv["B",xr.TAG_END] = (XmlReturn xml)
            {
				assert (btext == "\nhello\n\n", "Collect text only");
            };
            tv.setupNormalize(src);
			tv.parseDocument();


        }
        catch(Exception e)
        {
            writeln("Ticket 8 example error ", e.toString());
            return false;
        }
        return true;
    }

    string src = q"[<?xml version='1.0' encoding='utf-8'?>
<A>
<B>
hello
<!-- Stop me -->
</B>
</A>]";

    testTicket(src);
}


void testTicket7()
{
    bool ticketTest(string src)
    {
        try
        {
            auto xml = new TagVisitor();
			xml.setupRaw(src);
            xml.parseDocument();
			version(Explode)
			{
			scope(exit)
				xml.explode();
			}
		}
        catch(Exception e)
        {
            writeln("Ticket 7 example error ", e.toString());
            return false;
        }
        return true;

    }
    string src = q"[<?xml version="1.0" encoding="utf-8"?>
<Workbook>
<ExcelWorkbook><WindowHeight>11580</WindowHeight>
</ExcelWorkbook>
</Workbook>]";

    assert(ticketTest(src));



}
void ticketTests()
{
    emptyDocElement();
    testTicket4();
    testTicket7();
    testTicket8();
}


void testDomAssembly()
{
    auto doc = new linkdom.Document(null,"TestDoc"); // not the element tag name, just the id

    string myns = "http:\\anyold.namespace.will.do";

    auto elem = doc.createElementNS(myns,"m:doc");
    elem.setAttribute("xmlns:m",myns);

    doc.appendChild(elem);
	version(Explode) {
	scope(exit)
		doc.explode();
	}
    void output(const(char)[] p)
    {
        writeln(p);
    }

    doc.printOut(&output,2);

    writeln("Dom construction. <Enter to exit>");
    getchar();

}
