module xml.test.validate;
/**
Test program to try and measure the performance cost of building internal XML document, Elements, attributes, etc, from its streamed XML text form.
Trade offs include, the number of function calls and call-backs, size of the character buffers, size of character and UTF encoding, overheads of validation.
*/

import std.stdint;
import std.datetime;
import std.variant;
import std.file;
import xml.util.buffer;
import coreMemory = core.memory; // for GC stats
import xml.xmlLinkDom;
import xml.dom.domt;

import std.conv;
import std.string;

version(GC_STATS)
{
	import alt.gcstats;
}

import xml.std.xmlSlicer;
import std.stdio;
import xml.util.bomstring;
import xml.xmlAttribute;
import xml.textInput;
import xml.xmlParser;
import xml.txml;
import xml.xmlError;

double timedSeconds(ref StopWatch sw)
{
    auto duration = sw.peek();

    return duration.to!("seconds",double)();
}

void fullCollect()
{
	coreMemory.GC.collect();
	ulong created, deleted;

	writeln("Enter to continue");
	getchar();
}

import std.stream;


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

class ParseErrorHandler : DOMErrorHandler
{
	uint	  domErrorLevel;
	string	  msg;
    string[]  errors;
	bool xmlversion11;
	bool validate;
	bool namespaceAware;
	bool hadError;
	uint maxEdition;
	string inputFile;

	void init()
	{
		hadError = false;
		xmlversion11 = false;
		validate = true;
		namespaceAware = false;
		domErrorLevel = 0;
		maxEdition = 5;
	}
	version(GC_STATS)
	{
		mixin GC_statistics;
		static this()
		{
			setStatsId(typeid(typeof(this)).toString());
		}
	}
	this()
	{
		init();
		version(GC_STATS)
			gcStatsSum.inc();
	}
	~this()
	{
		version(GC_STATS)
			gcStatsSum.dec();
	}

	override bool handleError(DOMError error)
	{
		auto checkLevel = error.getSeverity();
		if (checkLevel > domErrorLevel)
			domErrorLevel = checkLevel;

		msg = error.getMessage();

		if (msg !is null)
		{
			errors ~= to!string(msg);
		}

		DOMLocator loc = error.getLocation();
		if (loc !is null)
		{
			errors ~= format("filepos %d,  line %d, col %d", loc.getByteOffset(), loc.getLineNumber(), loc.getColumnNumber());
		}
		auto ex = error.getRelatedException();
		if (ex !is null)
		{
			auto xe = cast(XmlError) ex;
			if (xe !is null)
				errors ~= xe.errorList;
		}

		if (errors.length == 0)
		{
			errors ~= "unknown error";

		}

		msg = std.string.join(errors,"\n");

		return false;
	}

	override string toString() const
	{
		return msg;
	}
}

	alias XMLDOM!(char).DOMConfiguration	DOMConfiguration;
	alias XMLDOM!(char).Document  Document;

void xmlValidate(string inputFile, ParseErrorHandler eh)
{
	int bomMark = -1;

	StopWatch sw;
	sw.start();

	auto doc = new Document();


	DOMConfiguration config = doc.getDomConfig();
	// The cast is essential, polymorphism fails for Variant.get!

	config.setParameter(xmlNamespaces,Variant(eh.namespaceAware) );
	config.setParameter("namespace-declarations",Variant(eh.namespaceAware));

	config.setParameter("error-handler",Variant( cast(DOMErrorHandler) eh ));
	config.setParameter("edition", Variant( eh.maxEdition ) );
	try {
		parseXmlFile!(char)(doc,inputFile);
	}

	catch(XmlError x)
	{
		// bombed
			if (eh.errors.length > 0)
			{
				writefln("DOM Error Handler exception");
				foreach(s ; eh.errors)
					writeln(s);

			}
			else
			{
				writefln("General exception %s", x.toString());
			}
		//destroy(x);
	}

	catch(Exception ex)
	{
		// anything unexpected.

		writefln("Non parse exception %s", ex.toString());

		writeln("General Exception");
		eh.domErrorLevel = DOMError.SEVERITY_FATAL_ERROR;
		eh.hadError = true;
	}

	sw.stop();
}



void usage()
{
	writefln("Working directory is %s", getcwd());
	writeln("validate.exe  [options] [--input] <xml file to validate>");
	writeln(" Options: --xml10 --xml11 --namespace --namespace+ --namespace- --validate --wellformed");
	return;
}

class ValidateOptions {
	bool xmlversion11;
	bool validate;
	bool namespaceAware;
	this()
	{
		xmlversion11 = false;
		validate = true;
		namespaceAware = false;
	}
}
/* validate one file from the input */
void main(string[] argv)
{
    string inputFile;
	ParseErrorHandler eh = new ParseErrorHandler();

	auto act = argv.length;
	auto i = 0;
    while (i < act)
    {
        string arg = argv[i++];
		if (arg.length > 2 && arg[0..2] == "--")
		{
			string option = arg[2..$];

			if (option == "xml11")
			{
				eh.xmlversion11 = true;
			}
			else if (option == "xml10")
			{
				eh.xmlversion11 = false;
			}
			else if (option == "validate")
			{
				eh.validate = true;
			}
			else if (option =="wellformed")
			{
				eh.validate = false;
			}
			else if (option == "namespace" || option == "namespace+")
			{
				eh.namespaceAware = true;
			}
			else if (option == "namespace-")
			{
				eh.namespaceAware = false;
			}
			else if (option == "input" && i < act)
			{
				inputFile = argv[i++];
			}

		}
		else 
			inputFile = arg;
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
		eh.inputFile = inputFile;
		xmlValidate(inputFile,eh);

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
	getchar();
}
