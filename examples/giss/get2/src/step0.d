module step0;
import std.stdio, std.file;
import std.path;
import std.algorithm;
import std.net.curl;
import std.conv;

import xml.txml;
import xml.util.bomstring;
import xml.xmlError;
import xml.sax;
import xml.util.buffer;

alias ReadRange!char  RData;
alias Buffer!char     WData;

// includes linefeed, tab, carriage return
int getSpaceCt( ref RData idata, ref dchar lastSpace)
{
	int   count = 0;
	dchar space = 0x00;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D: 
				space = test;
				count++;
				idata.popFront();
				break;
			default:
				lastSpace = space;
				return count;
		}
	}
	return 0;
}

int getCharCt( ref RData idata, ref WData wdata)
{
	int count = 0;
	while(!idata.empty)
	{
		dchar test = idata.front;
		switch(test)
		{
			case 0x20:
			case 0x0A:
			case 0x09:
			case 0x0D: 
				return count;
			default:
				wdata ~= test;
				count++;
				break;
		}
		idata.popFront;		
	}
	return count;
}

void extract_text(string baseURL, string fileName)
{
	auto textName = "temp_.html"; // prepare for further extraction
	auto url = text(baseURL,fileName);

	writeln("get: ", textName);

	download(url,textName);

	int bomMark = BOM.NONE;
	string inputFile = textName;

	string  pref_text;

	if (!exists(inputFile))
    {
        writeln("File not found : ", inputFile, "from ", getcwd());
        //getchar();
        return;
    }
	auto visitor = new SaxParser();
	visitor.isHtml(true);

	string htmldata = readFileBom!char(inputFile, bomMark);

	TagSpace mainNamespace = new TagSpace();

	auto prefDg = (const SaxEvent xml) {
		pref_text = xml.data;
	};

	mainNamespace["pre", SAX.TEXT] = prefDg;

	visitor.namespace = mainNamespace;

	//auto handler = visitor.defaults;  // SaxParser looks after this

	/*handler[SAX.TAG_START] = (const SaxEvent xml)
	{
		writeln(xml.data);
	};
	handler[SAX.TEXT] = (const SaxEvent xml)
	{
		writeln(xml.data);
	};*/

	try {
        visitor.setupNormalize(htmldata);
        visitor.parseDocument();
	}
	catch(XmlError ex)
	{
		writeln(ex.toString());
	}
	catch(Exception ex)
	{
		writeln(ex.msg);
	}

	if (pref_text.length > 0)
	{
		auto outfile = setExtension(fileName,"txt");
		auto fout = File(outfile,"w");
		fout.write(pref_text);
		fout.close();
	}

}

void pull_sources()
{
	int bomMark = BOM.NONE;
	string inputFile = "temperature.html";
	string baseURL = "http://www.antarctica.ac.uk/met/READER/";

	string[] myLinks;

	if (!exists(inputFile))
    {
        writeln("File not found : ", inputFile, "from ", getcwd());
        //getchar();
        return;
    }
	auto visitor = new SaxParser();
	visitor.isHtml(true);

	string htmldata = readFileBom!char(inputFile, bomMark);

	TagSpace mainNamespace = new TagSpace();
	auto myTLink = boyerMooreFinder("temp_html/");

	auto myLinkDg = (const SaxEvent xml) {
		auto href = xml.attributes.get("href",[]);
		if (href.length == 0)
			href = xml.attributes.get("HREF", []);
		if (href.length > 0)
		{
			auto r = find(href,myTLink);
			if (r.length > 0)
				myLinks ~= href;
		}
	};

	mainNamespace["a", SAX.TAG_START] = myLinkDg;
	mainNamespace["A", SAX.TAG_START] = myLinkDg;
	visitor.namespace = mainNamespace;

	/*auto handler = visitor.defaults;  // SaxParser looks after this

	handler[SAX.TAG_START] = (const SaxEvent xml)
	{
		writeln(xml.data);
	};
	handler[SAX.TEXT] = (const SaxEvent xml)
	{
		writeln(xml.data);
	};
    */
    
	try {
        visitor.setupNormalize(htmldata);
        visitor.parseDocument();
	}
	catch(XmlError ex)
	{
		writeln(ex.toString());
	}
	catch(Exception ex)
	{
		writeln(ex.msg);
	}

	foreach(link ; myLinks)
	{
		extract_text(baseURL, link);
		//break; // only do first one so far
	}
	getchar();

}

bool stopAfterChar(ref RData idata, dchar c)
{
	while(!idata.empty)
	{
		dchar test = idata.front;
		if (test == c)
		{
			idata.popFront();
			return true;
		}
		idata.popFront();
	}
	return false;
}


void reparse(string txt)
{
	int bomMark = BOM.NONE;
	auto f = readFileBom!char(txt,bomMark);

	WData wr;
	dchar lastSpace = 0;
	auto rd = RData(f);
	WData buf;

	while( !rd.empty)
	{
		int spaceCt = getSpaceCt(rd,lastSpace);

		// 1st text
		int charCt = getCharCt(rd,buf);
		if (buf.data == "SELECTED")
		{
			stopAfterChar(rd,0x0A);

			spaceCt = getSpaceCt(rd,lastSpace);
			buf.reset();
			charCt = getCharCt(rd,buf);
			wr ~= buf.data; // first part of name
			// keep going until get a number (a latitude)
			while(true)
			{
				spaceCt = getSpaceCt(rd,lastSpace);
				buf.reset();
				charCt = getCharCt(rd,buf);
				RData number = buf.data;
				NumberClass nc = parseNumber(number,buf);
				if (nc == NumberClass.NUM_INTEGER)
				{
					break; // collect data
				}
				else {
					// part of name
					wr ~= 0x20;
					wr ~= buf.data;

				}
			}

		}

	}

}
void main(string[] argv)
{

	chdir("temp_html");
	string[] sources;

	auto tfiles = dirEntries("","*.txt",SpanMode.depth);
	foreach(f; tfiles)
	{
		sources ~= f.name;
	}

	foreach(s; sources)
	{
		writeln("src: ", s);
		reparse(s);
	}
}
