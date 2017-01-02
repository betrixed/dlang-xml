module step0;
import std.stdio, std.file;
import std.algorithm;

import xml.txml;
import xml.util.bomstring;
import xml.xmlError;
import xml.sax;

void main(string[] argv)
{

	int bomMark = BOM.NONE;
	string inputFile = "stationpt.html";
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
				writeln("link: ", href);
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
	//getchar();

}
