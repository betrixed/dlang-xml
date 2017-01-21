module xml.sxml;

import xml.dom.domt;
import xml.xmlLinkDom;
import xml.xmlOutput;
import xml.xmlAttribute;
import xml.txml;
alias XMLDOM!char.XmlString DOMString;
alias XMLDOM!char.XmlString XmlString;

alias XMLDOM!char.Element Element;
alias XMLDOM!char.Node   Item;
alias XMLDOM!char.Node   Node;
alias XMLDOM!char.Attr    Attribute;
alias XMLDOM!char.Attr    Attr;
alias XMLDOM!char.Document Document;
alias XMLDOM!char.NodeList NodeList;
alias XMLDOM!char.NamedNodeMap NamedNodeMap;
alias XMLDOM!char.Text	   Text;
alias XMLDOM!char.ProcessingInstruction	   ProcessingInstruction;

alias XMLOutput!char.XmlPrintOptions XmlPrintOptions;
alias XMLOutput!char.XmlPrinter    XmlPrinter;

alias XMLAttribute!char.XmlAttribute XmlAttribute;
alias XMLAttribute!char.AttributeMap XmlAttributeMap;

Document xmlArray(char[] data)
{
	Document doc = new Document();
	parseXmlSlice!char(doc, data, true);
	return doc;

}
Document xmlFile(string srcPath)
{
	Document doc = new Document();
	parseXmlFile!char(doc, srcPath, true);
	return doc;
}

string NodeAsString(Node n)
{
    return (n.getNodeType()==NodeType.Element_node) ? n.getTextContent() : n.getNodeValue();
}
