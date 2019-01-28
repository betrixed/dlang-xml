module main;

import stdxml = xml.jcn;
import std.stdio;
import std.file;

import core.time: Duration;
import std.datetime.stopwatch : benchmark, StopWatch;

import core.memory, xml.util.buffer;
import xml.xmlLinkDom;
import xml.util.bomstring;
import xml.dom.domt;
import std.variant;
//import stdxml = std.xml; // only if modified as for GC_STATS

// How good is your garbage collection service. Is it fast? Does it work?
// Can it cope with entropy? How about a large XML document into linked DOM structure?
// help the GC by blowing up intransigant referencing data structures

double timedSeconds(ref StopWatch sw)
{
    auto d = sw.peek();
    // 100 ns hecto-nanoseconds 10^7
    return d.total!"hnsecs" * 1e-7;
}

void fullCollectNode()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();
	writeln("Full collection in ", timedSeconds(sw), " [s]");

}

void nodeGCStats()
{
	version (GC_STATS)
	{
		ulong created, deleted;
		XMLDOM!char.Node.gcStatsSum.stats(created, deleted);
		if (created > deleted)
			writeln("Node: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}

void fullCollectItem()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();

	writeln("Full collection in ", timedSeconds(sw), " [s]");

}
/*
void ardGCStats()
{
	version (GC_STATS)
	{
		ulong created, deleted;
		ard.Item.gcStatsSum.stats(created, deleted);
		writeln("Item: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}
*/

void fullCollectStdXml()
{
	writeln("full GC");
	auto sw = StopWatch();
	sw.start();
	GC.collect();
	sw.stop();

	writeln("Full collection in ", timedSeconds(sw), " [s]");

}

void stdGCStats()
{
	version (GC_STATS)
	{
		ulong created, deleted;
		stdxml.Item.gcStatsSum.stats(created, deleted);
		if (created > deleted)
			writeln("Item: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
		stdxml.Element.gcStatsSum.stats(created, deleted);
		if (created > deleted)
			writeln("Element: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
		stdxml.ElementParser.gcStats(created, deleted);
		if (created > deleted)
			writeln("ElementParser: created ",created, " deleted ", deleted, " diff ", created - deleted, " %", ((created-deleted)*100.0)/created);
	}
}

// This is faster because of the single file load
void loadFileStdXml(string fname)
{
    with (stdxml)
    {
		auto sw = StopWatch();
		sw.start();

		int bomMark = -1;

		auto s = readFileBom!char(fname, bomMark);
		auto doc = new stdxml.Document(s);
		//doc.explode();
		destroy(doc);
		sw.stop();

		writeln(fname, " link dom loaded in ", timedSeconds(sw), " [s]");

		//delete doc; // no backpointers;
    }
}

version=FILE_LOAD;
/*
void loadFileArrayDom(string fname)
{
    with (ard)
    {
		auto sw = StopWatch();
		sw.start();

		version(FILE_LOAD)
		{
			string s = cast(string)std.file.read(fname);
			auto p = new XmlStringParser(s);
			//auto sf = new SliceFill!char(s);
			//auto p = new XmlParser(sf);

		}
		else {
			auto fstream = new BufferedFile(fname);
			auto sf = new XmlStreamFiller(fstream);
			auto p = new XmlParser(sf);

		}
		auto tv = new TagVisitor(p);
		Document doc = new Document();

        auto bc = new ardb.ArrayDomBuilder(doc);
		auto dtag = new DefaultTagBlock();
		dtag.setBuilder(bc);
        tv.defaults = dtag;

        tv.parseDocument(0);
		sw.stop();

		writeln(fname, " to arraydom loaded in ", sw.peek().msecs, " [ms]");
		doc.explode();
		tv.explode();
    }
}
*/

void loadFileTest(string fname)
{
	writeln("start.. ", fname);
	auto sw = StopWatch();
	sw.start();


	alias xml.dom.domt.XMLDOM!char	xmldom;
	auto doc = new xmldom.Document();
	auto config = doc.getDomConfig();
	config.setParameter("namespace-declarations",Variant(false));

	parseXmlFile!(char)(doc, fname, true);
	doc.explode();
	sw.stop();
	writeln(fname, " link dom loaded in ", timedSeconds(sw), " [s]");


}


void showBlockBits(const(void)* p)
{
	auto bits = GC.getAttr(p);
	Buffer!char	bitset;

	if ((bits & GC.BlkAttr.NO_SCAN) != 0)
		bitset.put("no_scan,");
	if ((bits & GC.BlkAttr.FINALIZE) != 0)
		bitset.put("finalize,");
	if ((bits & GC.BlkAttr.NO_MOVE) != 0)
		bitset.put("no_move,");
	if ((bits & GC.BlkAttr.APPENDABLE) != 0)
		bitset.put("appendable,");
	if ((bits & GC.BlkAttr.NO_INTERIOR) != 0)
		bitset.put("no_interior,");
	writefln("Pointer %x bits %x  %s",p, bits, bitset.data);
}

void printUsage()
{
	writeln("arguments:  inputfile1 [inputfile2]* ");
	writeln("working directory here is %s", getcwd());
}
void main(string[] argv)
{
	if (argv.length <= 1)
	{
		printUsage();
		getchar();
		return;
	}
	enum repeats = 4;
	writeln("Repeats = ",repeats);
	writeln("Working Dir = ",getcwd());
	writeln("< Enter > for workflow");
	getchar();
	foreach(arg ; argv[1..$])
	{
		if (!exists(arg))
		{
			writefln("File not found : %s", arg);
			getchar();
			return;
		}
		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileTest(arg);
			fullCollectNode();
		}
		fullCollectNode();
		nodeGCStats();
		writeln(" linkdom.Node results. Enter to continue");
		getchar();

/*
		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileArrayDom(arg);
			fullCollectItem();
		}
		fullCollectItem();
		ardGCStats();
		writeln(" arraydom.Item results. Enter to continue");
		getchar();
		*/



		for(auto i = 0; i < repeats; i++)
		{
			writeln("test ", i+1);
			loadFileStdXml(arg);
			fullCollectStdXml();
		}

		fullCollectStdXml();
		stdGCStats();
		writeln(" std.xml Results. Enter to continue");
		getchar();
		writeln(" All GC Results. Enter to continue");
		getchar();
		//cd GCStatsSum.AllStats();
	}

	writeln("All done -- Enter to exit");
	getchar();
	writeln("Shutting down now . . .");

}
