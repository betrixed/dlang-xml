module step0;
import std.stdio, std.file;

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
        getchar();
        return;
    }
	auto visitor = new SaxParser();
	visitor.isHtml(true);

	string htmldata = readFileBom!char(inputFile, bomMark);

	TagSpace mainNamespace = new TagSpace();

    SaxDg textDg = (const SaxEvent xml)
    {
        writeln(xml.eventId, ": ", xml.data);
    };

	mainNamespace["a", SAX.TEXT] = (const SaxEvent xml) {
		writeln(xml.data);
	};
	visitor.namespace = mainNamespace;
	auto handler = visitor.defaults;  // SaxParser looks after this
	handler[SAX.TAG_START] = textDg;
    handler[SAX.TEXT] = textDg;
    handler[SAX.CDATA] = textDg;
    handler[SAX.XML_PI] = textDg;
    handler[SAX.COMMENT] = textDg;
    handler[SAX.XML_DEC] = textDg;

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

}
