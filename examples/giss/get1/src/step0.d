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


void download_as_text(string baseURL, string fileName)
{
	auto textName = setExtension(fileName, "txt");
	auto url = text(baseURL,textName);
	writeln("get: ", textName);
	download(url,textName);

}
void main(string[] argv)
{

	int bomMark = BOM.NONE;
	string inputFile = "stationpt.html";
	string baseURL = "http://www.antarctica.ac.uk/met/READER/surface/";

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
	auto myTLink = boyerMooreFinder("All.temperature");

	auto myLinkDg = (const SaxEvent xml) {
		auto href = xml.attributes.get("href","");
		if (href.length > 0)
		{
			auto r = find(href,myTLink);
			if (r.length > 0)
				myLinks ~= href;
		}
	};

	mainNamespace["a", SAX.TAG_START] = myLinkDg;

	visitor.namespace = mainNamespace;
	auto handler = visitor.defaults;  // SaxParser looks after this

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
		download_as_text(baseURL, link);
	}
	//getchar();

}
