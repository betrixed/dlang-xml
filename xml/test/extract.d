module xml.test.speed;

import xml.txml, xml.xmlError;
import xml.dom.domt;
import xml.xmlSax;
import xml.textInput, xml.util.read;
import xml.xmlArrayDom;

import std.stdio, std.datetime,std.string, std.stdint;

import std.variant, std.conv, std.random, std.file;

alias XMLArrayDom!char  ArrayDOM;
alias ArrayDOM.ArrayDomBuilder	ArrayDomBuilder;

import core.memory;
import xml.util.bomstring;

alias xml.xmlSax.XMLSAX!char	SaxTpl;

alias SaxTpl.Sax		Sax;
alias SaxTpl.SaxDg		SaxDg;
alias SaxTpl.SaxParser  SaxParser;
alias SaxTpl.SaxEvent   SaxEvent;
alias SaxTpl.TagSpace	TagSpace;

version(GC_STATS)
{
	import xml.util.gcstats;
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
    auto tv = new SaxParser();
	auto nspace = new TagSpace();
	tv.namespace = nspace;

    /// The callbacks will all have different keys, so only need one set, for this kind of document
    /// But still need to set the parser stack callback object for each level, usually in a TAG_START callback.
    ///
    string[] allText;

    /// const prebuilt keys for non tagged nodes
    SaxDg textDg = (const SaxEvent xml)
    {
        allText ~= xml.data;
    };

    SaxDg piDg = (const SaxEvent xml)
    {
		auto p = xml.attributes.peek[0];
		allText ~= text(p.name," ",p.value);
    };

	SaxDg xmlDecDg = (const SaxEvent xml)
    {
		/*foreach(p,q ; xml.attributes.peek)
			writefln("%s='%s'",p, q); */
    };

	auto handler = tv.defaults;  // SaxParser looks after this
    handler[SAX.TEXT] = textDg;
    handler[SAX.CDATA] = textDg;
    handler[SAX.XML_PI] = piDg;
    handler[SAX.COMMENT] = textDg;
    handler[SAX.XML_DEC] = xmlDecDg;


	Sax[]	saveDefaults;   // a  stack of handler sets
	auto bce = new  ArrayDomBuilder();

	auto ctags = new Sax("C");
	nspace.put(ctags);

	SaxDg onTagEmpty = (const SaxEvent xml)
	{
		if (xml.attributes.length > 0)
		{
			auto attr = xml.attributes.peek;
			foreach(n, v ; attr)
                writefln("%s = '%s'", n, v);
		}
	};
	SaxDg onTagStart =  (const SaxEvent xml)
    {
		saveDefaults ~= tv.defaults;
		tv.defaults = new Sax(tv.defaults);
		tv.defaults.setInterface(bce);
		bce.startTag(xml);
	};

	SaxDg onTagEnd = (const SaxEvent xml)
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



    nspace["C",SAX.TAG_START] = onTagStart;
	nspace["C",SAX.TAG_EMPTY] = onTagEmpty;
	nspace["C",SAX.TAG_END] = onTagEnd;

	nspace["B",SAX.TAG_START] = (const SaxEvent xml)
	{
		writeln("B Start");
	};

	auto A_tags = new Sax("A");
	nspace.put(A_tags); // this now part of current

    A_tags[SAX.TAG_START] = (const SaxEvent xml)
    {
        writeln("Document A Start");
    };

	A_tags[SAX.TAG_END] = (const SaxEvent xml)
    {
        writeln("Document A End");
    };

    tv.setupNormalize(Example4);
	tv.parseDocument();

    writefln("%s",allText);

	destroy(tv);
	destroy(nspace);

}


// Faster way to do it, only set up parser once
void sax2_speed(string s)
{
	auto visitor = new SaxParser();
    // get a set of callbacks at the current state.

    // Check for well-formedness. Note that this is superfluous as it does same as parse.
    //sdom.check(s);

    // Take it apart
    Book[]  books;
	Book	book;

	TagSpace mainNamespace, bookNamespace;
	mainNamespace = new TagSpace();
	bookNamespace = new TagSpace();

	scope(exit)
	{
		destroy(visitor);
		destroy(mainNamespace);
		destroy(bookNamespace);
	}
    auto bookcb = mainNamespace.create("book");

	bookcb[SAX.TAG_START]
    = (const SaxEvent xml) {
		book.id = xml.attributes.get("id");
		visitor.namespace = bookNamespace;
	};

	bookcb[SAX.TAG_END]
	= (const SaxEvent xml) {
		books ~= book;
		visitor.namespace = mainNamespace;
	};

	visitor.namespace = mainNamespace;

	/// single delegate assignment for tag
	bookNamespace["author", SAX.TEXT] = (const SaxEvent xml) {
		book.author = xml.data;
	};
	bookNamespace["title", SAX.TEXT] = (const SaxEvent xml) {
		book.title = xml.data;
	};
	bookNamespace["genre", SAX.TEXT] = (const SaxEvent xml) {
		book.genre = xml.data;
	};
	bookNamespace["price",SAX.TEXT] = (const SaxEvent xml)
	{
		book.price = xml.data;
	};
	bookNamespace["publish_date",SAX.TEXT] = (const SaxEvent xml)
	{
		book.pubDate = xml.data;
	};
	bookNamespace["description",SAX.TEXT] = (const SaxEvent xml)
	{
		book.description = xml.data;
	};

	visitor.setupNormalize(s);
	visitor.parseDocument();

}

import xml.std.xmlSlicer;
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
	doc.explode();
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

void sax1_speed(string s)
{

    auto visitor = new SaxParser();
	//alias xml.parseitem.XmlResult	xr;


	Book[] books;
	Book book;

/// Two AA references, for 2 tag namespaces
	TagSpace	bookHandlers, mainHandlers;

	mainHandlers = new TagSpace();
	bookHandlers = new TagSpace();
	visitor.namespace = mainHandlers;

	scope(exit)
	{	// wipeouts do help
		destroy(bookHandlers);
		destroy(mainHandlers);
		destroy(visitor);
	}
	mainHandlers["book", SAX.TAG_START] = (const SaxEvent xml) {
		book.id = xml.attributes.get("id");
		visitor.namespace = bookHandlers;	// to book namespace
		visitor.parseDocument(-1);			// -1 to exit just after book TAG_END
		visitor.namespace = mainHandlers;
		books ~= book;
	};

	visitor.namespace = mainHandlers;

	/// Use convenience to set up a TagBlock for each element.
	bookHandlers["author", SAX.TEXT] = (const SaxEvent xml) {
		book.author = xml.data;
	};
	bookHandlers["title", SAX.TEXT] = (const SaxEvent xml) {
		book.title = xml.data;
	};
	bookHandlers["genre", SAX.TEXT] = (const SaxEvent xml) {
		book.genre = xml.data;
	};
	bookHandlers["price",SAX.TEXT] = (const SaxEvent xml)
	{
		book.price = xml.data;
	};
	bookHandlers["publish_date",SAX.TEXT] = (const SaxEvent xml)
	{
		book.pubDate = xml.data;
	};
	bookHandlers["description",SAX.TEXT] = (const SaxEvent xml)
	{
		book.description = xml.data;
	};

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

double timedSeconds(ref StopWatch sw)
{
    auto duration = sw.peek();

    return duration.to!("seconds",double)();
}

void fullCollect()
{
	GC.collect();
	ulong created, deleted;

	writeln("Post Collect : Enter to continue");
	getchar();
}



import std.stream;
void runTests(string inputFile, uintptr_t runs)
{
    int bomMark = -1;
    string s = readTextBom!char(inputFile, bomMark);
	fullCollect();

	enum uint numTests = 3;
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
                        StdXmlRun(s);
                    }
                    sw.stop();
                    break;

                case 1:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        sax1_speed(s);
                    }
                    sw.stop();
                    break;

                case 2:
                    sw.start();
                    for(i = 0;  i < runs; i++)
                    {
                        sax2_speed(s);
                    }
                    sw.stop();
                    break;
                    break;
                case 3:

                    break;
                case 5:
                    break;
                case 4:

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
    auto control = sum[0];
    foreach(d ; sum)
        if (control > d)
            control = d;

	writeln("averages: ", runs, " runs");
	writefln(" %8s %8s %8s %8s %8s %8s", "std.xml",  "sax1",  "sax2",  "-",  "-", "-");
	foreach(v ; sum)
        writef(" %8.4f", v);
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
	ticketTests();
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
        writefln("%s  --input <path to books.xml>	--runs <repetitions (default==100)>", argv[0]);
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
	fullCollect();
	version(GC_STATS)
	{
		GCStatsSum.AllStats();
		//writeln("If some objects are still alive, try calling  methods.explode");
		//version(TrackCount)
		//	listTracks();
		writeln("Enter to exit");

	}
	getchar();
}



void emptyDocElement()
{
    string doc;

    doc =`<?xml version="1.0" encoding="utf-8"?><main test='"what&apos;s up doc?"'/>`;

	SaxDg xdg = (const SaxEvent xml)
    {
        // main item
        writeln("Got main test=",xml.attributes.get("test"));
    };

    auto tv = new SaxParser();
	auto handler = new TagSpace();

	scope(exit)
	{
		destroy(tv);
		destroy(handler);
	}
	tv.setupNormalize(doc);
	tv.namespace = handler;

    handler["main", SAX.TAG_START] = xdg;

    tv.parseDocument();


}


void testTicket8()
{

    bool testTicket(string src)
    {
        try
        {
            auto tv = new SaxParser();
			auto handler = new TagSpace();

			scope(exit)
			{
				destroy(tv);
				destroy(handler);
			}
			char[]	btext;

			handler["B", SAX.TAG_START] = (const SaxEvent ret)
			{
				btext = null;
			};

			handler["B", SAX.TEXT] = (const SaxEvent ret)
			{
				btext ~= ret.data;
			};

            handler["B",SAX.TAG_END] = (const SaxEvent xml)
            {
				assert (btext == "\nhello\n\n", "Collect text only");
            };
			tv.namespace = handler;
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
		void outdoc(const(char)[] s)
		{
			write(s);
		}
        try
        {
            auto xml = new ArrayDomBuilder();
			xml.setSource(src);
            xml.parseDocument();
			xml.document.printOut(&outdoc,2);
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

    testTicket7();
    testTicket8();
}



